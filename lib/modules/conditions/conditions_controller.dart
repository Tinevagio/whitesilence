// lib/modules/conditions/conditions_controller.dart
//
// Orchestrateur du module Conditions.
//
// Responsabilités :
//   - Fetcher la grille de conditions sur la zone visible (avec debounce)
//   - Servir le cache si réseau indisponible
//   - Exposer l'état (loading / error / stale) à l'UI
//   - Fetcher le BERA pour le centre de la zone visible
//   - Gérer le slider "heure" (par défaut : heure courante UTC)

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'models/avalanche_zone.dart';
import 'models/bera_full.dart';
import 'models/bera_info.dart';
import 'models/best_window.dart';
import 'models/point_conditions.dart';
import 'services/avalanche_engine.dart';
import 'services/bera_full_service.dart';
import 'services/conditions_api.dart';
import 'services/conditions_cache.dart';
import 'services/snow_heatmap.dart';

enum ConditionsStatus {
  empty,        // jamais rien chargé — état initial
  loading,
  ready,        // grille fraîche disponible
  staleCache,   // on a une vieille donnée locale, pas pu rafraîchir
  error,
}

/// Mode de visualisation du meilleur créneau.
enum BestWindowMode {
  powder, // poudreuse : couleur selon l'heure jusqu'à laquelle ça tient
  spring, // moquette / printemps : couleur selon l'heure idéale
  both,   // les deux superposés
}

class ConditionsController extends ChangeNotifier {
  static final ConditionsController _instance = ConditionsController._();
  factory ConditionsController() => _instance;
  ConditionsController._();

  final ConditionsApi   _api   = ConditionsApi();
  final ConditionsCache _cache = ConditionsCache();

  // ── État ─────────────────────────────────────────────────────────────────
  ConditionsStatus _status = ConditionsStatus.empty;
  ConditionsStatus get status => _status;

  ConditionsResponse? _grid;
  DateTime?           _gridFetchedAt;
  ConditionsResponse? get grid => _grid;
  DateTime?           get gridFetchedAt => _gridFetchedAt;

  // ── Points cumulés (multi-bbox) ──────────────────────────────────────────
  // Quand l'utilisateur dessine une 2ème, 3ème bbox, on ne perd pas les
  // points précédents — ils restent affichés sur la carte. Pratique pour
  // explorer un massif en plusieurs zones successives.
  //
  // Dé-dup spatial : deux points à moins de ~100m l'un de l'autre, on garde
  // le plus récent (vu que les conditions évoluent dans le temps).
  final List<PointConditions> _accumulatedPoints = [];

  /// Tous les points actuellement affichés sur la carte (cumul des bbox
  /// dessinées dans la session). Inclut ceux de _grid.
  List<PointConditions> get accumulatedPoints =>
      List.unmodifiable(_accumulatedPoints);

  /// Vide tous les points cumulés. Utile si l'utilisateur veut repartir
  /// à zéro (par exemple bouton "Effacer la carte" dans l'action panel).
  /// Efface tout : points de conditions, heatmap, bbox dessinées,
  /// polygones avalanche. Remet le module dans son état initial.
  void clearAccumulatedPoints() {
    _accumulatedPoints.clear();
    _grid          = null;
    _gridFetchedAt = null;
    _snowHeatmap   = null;
    _avalancheByBbox.clear();
    _drawnBboxes.clear();
    _currentBboxKey = null;
    _drawAnchor  = null;
    _drawCurrent = null;
    notifyListeners();
  }

  /// Ajoute les points d'une nouvelle réponse au cumul, avec dé-dup spatial.
  void _mergeIntoAccumulated(ConditionsResponse response) {
    // Distance seuil pour considérer 2 points comme "le même"
    const double threshDegLat = 0.0009; // ~100m en latitude
    const double threshDegLon = 0.0013; // ~100m en longitude à 45°

    for (final newP in response.points) {
      _accumulatedPoints.removeWhere((oldP) =>
          (oldP.lat - newP.lat).abs() < threshDegLat &&
          (oldP.lon - newP.lon).abs() < threshDegLon);
      _accumulatedPoints.add(newP);
    }

    // La heatmap d'enneigement devient obsolète. Si elle était visible, on
    // la reconstruit avec les nouveaux points cumulés. Sinon on la dégage
    // pour qu'elle soit recalculée au prochain toggle.
    _snowHeatmap = null;
    if (_snowHeatmapVisible) {
      // Asynchrone fire-and-forget : pas bloquant.
      unawaited(rebuildSnowHeatmap());
    }
  }

  BeraInfo? _bera;
  BeraInfo? get bera => _bera;

  // BeraFull : bulletin enrichi depuis Tinevagio/Ski-touring-live.
  // Chargé en parallèle du BERA léger. Utilisé par AvalancheEngine pour
  // le calcul local des cônes (pentes dangereuses, limites, enneigement).
  BeraFull? _beraFull;
  BeraFull? get beraFull => _beraFull;
  final BeraFullService _beraFullService = BeraFullService();

  // ── Avalanche ────────────────────────────────────────────────────────────
  // L'avalanche se déclenche à part du fetch de la grille de conditions :
  // c'est plus lourd (potentiellement 300 zones + cônes), donc opt-in via
  // un toggle dans l'action panel. Quand activé, on fetch sur la même bbox.
  // Map bbox_key → AvalancheResponse pour conserver les résultats de
  // toutes les bbox dessinées. Une nouvelle bbox n'efface plus les anciennes.
  // Clé = "\${sw.lat},\${sw.lon},\${ne.lat},\${ne.lon}" arrondie à 4 décimales.
  final Map<String, AvalancheResponse> _avalancheByBbox = {};

  /// Union de toutes les AvalancheResponse connues — pour l'affichage.
  /// L'overlay itère sur toutes les bbox et affiche l'ensemble.
  Map<String, AvalancheResponse> get avalancheByBbox =>
      Map.unmodifiable(_avalancheByBbox);

  /// Réponse avalanche pour la bbox courante (rétrocompat).
  AvalancheResponse? get avalanche {
    final key = _currentBboxKey;
    return key != null ? _avalancheByBbox[key] : null;
  }

  bool _avalancheVisible = false;
  bool get avalancheVisible => _avalancheVisible;

  bool _avalancheLoading = false;
  bool get avalancheLoading => _avalancheLoading;

  /// Override du risque BERA pour visualiser "ce qui se passerait si…"
  /// null = on prend le risque réel du massif.
  int? _riskOverride;
  int? get riskOverride => _riskOverride;

  // ── Best window (créneau moquette/poudreuse) ─────────────────────────────
  // Le mode "best window" affiche, pour chaque point de la grille, la
  // dernière heure où la poudre tient ET l'heure idéale moquette. C'est un
  // mode d'affichage alternatif à la grille de conditions standard.
  BestWindowResponse? _bestWindow;
  BestWindowResponse? get bestWindow => _bestWindow;

  bool _bestWindowVisible = false;
  bool get bestWindowVisible => _bestWindowVisible;

  bool _bestWindowLoading = false;
  bool get bestWindowLoading => _bestWindowLoading;

  /// Mode de visualisation du best window : 'powder' (poudreuse), 'spring'
  /// (moquette), ou 'both' (les deux superposés).
  BestWindowMode _bestWindowMode = BestWindowMode.both;
  BestWindowMode get bestWindowMode => _bestWindowMode;

  void setBestWindowMode(BestWindowMode mode) {
    if (_bestWindowMode == mode) return;
    _bestWindowMode = mode;
    notifyListeners();
  }

  // ── Heatmap d'enneigement ────────────────────────────────────────────────
  // Affiche une carte d'opacité montrant l'enneigement (en cm) interpolé
  // par IDW sur la bbox de tous les points cumulés. Utilise les niveaux
  // BERA + altitude + exposition.
  SnowHeatmap? _snowHeatmap;
  SnowHeatmap? get snowHeatmap => _snowHeatmap;

  bool _snowHeatmapVisible = false;
  bool get snowHeatmapVisible => _snowHeatmapVisible;

  bool _snowHeatmapLoading = false;
  bool get snowHeatmapLoading => _snowHeatmapLoading;

  /// Opacité 0-1 du calque heatmap. Slider dans l'action panel.
  double _snowHeatmapOpacity = 0.65;
  double get snowHeatmapOpacity => _snowHeatmapOpacity;

  void setSnowHeatmapOpacity(double v) {
    _snowHeatmapOpacity = v.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// Toggle l'affichage. Reconstruit la heatmap si elle n'existe pas encore
  /// ou si les points cumulés ont changé depuis le dernier build.
  Future<void> toggleSnowHeatmap() async {
    _snowHeatmapVisible = !_snowHeatmapVisible;
    notifyListeners();
    if (_snowHeatmapVisible && _snowHeatmap == null) {
      await rebuildSnowHeatmap();
    }
  }

  /// (Re)construit la heatmap sur les points cumulés actuels.
  /// Appelé manuellement ou automatiquement après un nouveau fetch.
  Future<void> rebuildSnowHeatmap() async {
    if (_accumulatedPoints.isEmpty) return;
    _snowHeatmapLoading = true;
    notifyListeners();
    try {
      _snowHeatmap =
          await SnowHeatmapBuilder.build(_accumulatedPoints);
    } catch (e) {
      debugPrint('[conditions] heatmap build failed: $e');
      _snowHeatmap = null;
    } finally {
      _snowHeatmapLoading = false;
      notifyListeners();
    }
  }

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // ── Mode dessin de bbox ──────────────────────────────────────────────────
  bool _isDrawing = false;
  bool get isDrawing => _isDrawing;

  LatLng? _drawAnchor;   // premier coin (où le drag a commencé)
  LatLng? _drawCurrent;  // deuxième coin (à jour pendant le drag)

  // Historique des bbox validées (affichage de tous les rectangles)
  final List<({LatLng sw, LatLng ne})> _drawnBboxes = [];
  List<({LatLng sw, LatLng ne})> get drawnBboxes =>
      List.unmodifiable(_drawnBboxes);

  // Clé de la bbox courante pour indexer _avalancheByBbox
  String? _currentBboxKey;
  String? get currentBboxKey => _currentBboxKey;

  static String _bboxKey(LatLng sw, LatLng ne) =>
      '${sw.latitude.toStringAsFixed(4)},${sw.longitude.toStringAsFixed(4)},'
      '${ne.latitude.toStringAsFixed(4)},${ne.longitude.toStringAsFixed(4)}';

  /// Limite côté en km : on ne laisse pas l'utilisateur dessiner plus grand
  /// que ça. Reprise du frontend Netlify (5 km) avec marge un peu plus large
  /// pour les sorties à grand rayon.
  ///
  /// Au-delà, /conditions devient très lent (perf backend) et risque de
  /// faire exploser le quota Render. Et un BERA + grille à 100 km² couvre
  /// déjà la quasi-totalité des sorties ski de rando réalistes.
  static const double maxBboxSideKm = 10.0;

  /// Bbox actuellement dessinée (ou en cours de dessin). Null si pas de dessin.
  /// Toujours normalisée : sw = coin sud-ouest, ne = coin nord-est.
  ///
  /// **Clampée à maxBboxSideKm dans chaque dimension**, centrée sur le milieu
  /// de la zone que l'utilisateur tente de dessiner. Du coup le rectangle
  /// visuel s'arrête tout seul quand l'utilisateur essaie d'étirer plus
  /// grand — pas besoin de blocage explicite côté UI.
  ({LatLng sw, LatLng ne})? get drawnBbox {
    final a = _drawAnchor, c = _drawCurrent;
    if (a == null || c == null) return null;
    final swLat = a.latitude  < c.latitude  ? a.latitude  : c.latitude;
    final swLon = a.longitude < c.longitude ? a.longitude : c.longitude;
    final neLat = a.latitude  > c.latitude  ? a.latitude  : c.latitude;
    final neLon = a.longitude > c.longitude ? a.longitude : c.longitude;
    return _clampBbox(swLat, swLon, neLat, neLon);
  }

  /// Mesure haversine en km entre deux points. Logique reprise du frontend
  /// Netlify (Front End V7.html, fonction haversineKm).
  static double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLon = (lon2 - lon1) * math.pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2)
        + math.cos(lat1 * math.pi / 180.0) * math.cos(lat2 * math.pi / 180.0)
          * math.sin(dLon / 2) * math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Clamp d'une bbox à `maxBboxSideKm` dans chaque dimension, centré sur
  /// le milieu. Logique reprise du frontend Netlify (fonction clampBbox).
  static ({LatLng sw, LatLng ne}) _clampBbox(
      double latS, double lonW, double latN, double lonE) {
    double dLat = latN - latS;
    double dLon = lonE - lonW;

    final hKm = _haversineKm(latS, lonW, latN, lonW); // hauteur (latitude)
    final wKm = _haversineKm(latS, lonW, latS, lonE); // largeur (longitude)

    if (hKm > maxBboxSideKm) {
      final ratio  = maxBboxSideKm / hKm;
      final center = (latS + latN) / 2;
      dLat = dLat * ratio;
      latS = center - dLat / 2;
      latN = center + dLat / 2;
    }
    if (wKm > maxBboxSideKm) {
      final ratio  = maxBboxSideKm / wKm;
      final center = (lonW + lonE) / 2;
      dLon = dLon * ratio;
      lonW = center - dLon / 2;
      lonE = center + dLon / 2;
    }
    return (sw: LatLng(latS, lonW), ne: LatLng(latN, lonE));
  }

  void startDrawing() {
    _isDrawing   = true;
    _drawAnchor  = null;
    _drawCurrent = null;
    notifyListeners();
  }

  void cancelDrawing() {
    _isDrawing   = false;
    _drawAnchor  = null;
    _drawCurrent = null;
    notifyListeners();
  }

  /// Appelé par le _DragHandler quand le geste commence.
  void onDrawStart(LatLng p) {
    if (!_isDrawing) return;
    _drawAnchor  = p;
    _drawCurrent = p;
    notifyListeners();
  }

  void onDrawUpdate(LatLng p) {
    if (!_isDrawing || _drawAnchor == null) return;
    _drawCurrent = p;
    notifyListeners();
  }

  /// Fin du drag : si la zone dessinée est trop petite, on ignore. Sinon on
  /// quitte le mode dessin et on déclenche un fetch.
  void onDrawEnd(LatLng p) {
    if (!_isDrawing) return;
    if (_drawAnchor == null) {
      _isDrawing = false;
      notifyListeners();
      return;
    }
    _drawCurrent = p;

    final box = drawnBbox;
    // Bbox dégénérée (tap sans drag, ou zone < ~50m) → on annule sans fetch
    if (box == null ||
        (box.ne.latitude  - box.sw.latitude)  < 0.0005 ||
        (box.ne.longitude - box.sw.longitude) < 0.0005) {
      _isDrawing = false;
      _drawAnchor = null;
      _drawCurrent = null;
      notifyListeners();
      return;
    }

    _isDrawing = false;

    // Enregistrer la nouvelle bbox dans l'historique
    _drawnBboxes.add(box);
    _currentBboxKey = _bboxKey(box.sw, box.ne);
    _bestWindow = null;

    notifyListeners();

    // Fetch automatique de la zone qu'on vient de dessiner
    fetchGrid(box.sw, box.ne, force: true);
    fetchBeraFor(LatLng(
      (box.sw.latitude  + box.ne.latitude)  / 2,
      (box.sw.longitude + box.ne.longitude) / 2,
    ));
    // Avalanche : toujours fetcher pour une nouvelle bbox
    // (pas de guard containsKey — chaque nouvelle bbox doit être calculée)
    if (_avalancheVisible) {
      fetchAvalanche(box);
    }
    if (_bestWindowVisible) {
      fetchBestWindow();
    }
  }

  // Slider d'heure UTC (0-23). Par défaut, l'heure courante.
  int _selectedHourUtc = DateTime.now().toUtc().hour;
  int get selectedHourUtc => _selectedHourUtc;
  set selectedHourUtc(int h) {
    _selectedHourUtc = h.clamp(0, 23);
    notifyListeners();
  }

  // Date sélectionnée (par défaut : aujourd'hui)
  DateTime _selectedDate = DateTime.now();
  DateTime get selectedDate => _selectedDate;

  Future<void> setSelectedDate(DateTime d) async {
    _selectedDate = DateTime(d.year, d.month, d.day);
    notifyListeners();
    if (_lastBbox != null) {
      await fetchGrid(_lastBbox!.sw, _lastBbox!.ne, force: true);
    }
  }

  // Dernière bbox demandée
  _Bbox? _lastBbox;

  // Debounce pour les déplacements rapides de la carte
  Timer? _fetchDebounce;
  static const _debounceDelay = Duration(milliseconds: 700);

  // ── État de réveil du backend ────────────────────────────────────────────
  // Render free tier met l'instance en veille après inactivité. wakeUp() ping
  // /health au démarrage du module pour la réveiller en background, le temps
  // que l'utilisateur trouve le bouton "Dessiner" et trace sa zone.
  bool _isWakingUp = false;
  bool _hasWokenUp = false;
  bool get isWakingUp => _isWakingUp;
  bool get hasWokenUp => _hasWokenUp;

  bool _started = false;
  Future<void> start() async {
    if (_started) return;
    _started = true;
    // Cleanup léger du cache au démarrage
    unawaited(_cache.cleanup());
    // Réveille le backend en background pour éviter le cold start visible
    unawaited(_wakeUpBackend());
  }

  Future<void> _wakeUpBackend() async {
    if (_hasWokenUp || _isWakingUp) return;
    _isWakingUp = true;
    notifyListeners();
    final ok = await _api.wakeUp();
    _isWakingUp = false;
    _hasWokenUp = ok;
    notifyListeners();
  }

  // ── Fetch grille ─────────────────────────────────────────────────────────

  /// Demande de fetch déclenchée par le module (mouvement de carte, etc.).
  /// Débouncée pour ne pas spammer l'API quand l'utilisateur navigue.
  void requestFetch(LatLng sw, LatLng ne) {
    _lastBbox = _Bbox(sw, ne);
    _fetchDebounce?.cancel();
    _fetchDebounce = Timer(_debounceDelay, () {
      fetchGrid(sw, ne);
    });
  }

  /// Réessaie le dernier fetch tenté. Utilisé par le bouton "Réessayer"
  /// affiché quand la grille a échoué (timeout, erreur réseau…).
  /// Si on avait dessiné une bbox, on prend celle-là ; sinon on prend la
  /// dernière bbox demandée par requestFetch.
  Future<void> retry() async {
    final box = drawnBbox ?? (_lastBbox == null
        ? null
        : (sw: _lastBbox!.sw, ne: _lastBbox!.ne));
    if (box == null) return;
    await fetchGrid(box.sw, box.ne, force: true);
    await fetchBeraFor(LatLng(
      (box.sw.latitude  + box.ne.latitude)  / 2,
      (box.sw.longitude + box.ne.longitude) / 2,
    ));
  }

  /// Fetch immédiat (sans debounce). Si `force=false` et qu'on a un cache
  /// frais, on utilise le cache sans appel réseau.
  Future<void> fetchGrid(LatLng sw, LatLng ne, {bool force = false}) async {
    // Défense en profondeur : tronque la bbox à maxBboxSideKm dans chaque
    // dimension, peu importe l'appelant (drag, "Fetch ici", navigation
    // depuis Idées, etc.). Si la bbox est déjà sous la limite, ce clamp
    // est une no-op.
    final clamped = _clampBbox(
      sw.latitude, sw.longitude, ne.latitude, ne.longitude,
    );
    sw = clamped.sw;
    ne = clamped.ne;

    _lastBbox = _Bbox(sw, ne);
    final key = ConditionsCache.makeKey(
      sw: sw,
      ne: ne,
      date: _selectedDate,
      resolutionM: 500,
    );

    // 1. Cache frais ?
    if (!force) {
      final cached = await _cache.load(key);
      if (cached != null && !cached.isStale(ConditionsCache.defaultTtl)) {
        _grid          = cached.response;
        _gridFetchedAt = cached.fetchedAt;
        _status        = ConditionsStatus.ready;
        _errorMessage  = null;
        _mergeIntoAccumulated(cached.response);
        notifyListeners();
        return;
      }
    }

    // 2. Sinon, fetch réseau
    _status = ConditionsStatus.loading;
    notifyListeners();

    try {
      final response = await _api.getConditions(
        sw: sw,
        ne: ne,
        date: _selectedDate,
        resolutionM: 500,
      );
      _grid          = response;
      _gridFetchedAt = DateTime.now();
      _status        = ConditionsStatus.ready;
      _errorMessage  = null;
      _mergeIntoAccumulated(response);
      await _cache.store(key, response);
    } on ConditionsApiException catch (e) {
      // Fallback cache stale si disponible
      final stale = await _cache.load(key);
      if (stale != null) {
        _grid          = stale.response;
        _gridFetchedAt = stale.fetchedAt;
        _status        = ConditionsStatus.staleCache;
        _errorMessage  = e.message;
        _mergeIntoAccumulated(stale.response);
      } else {
        _status       = ConditionsStatus.error;
        _errorMessage = e.message;
      }
    } catch (e) {
      _status       = ConditionsStatus.error;
      _errorMessage = 'Erreur inattendue : $e';
    } finally {
      notifyListeners();
    }
  }

  // ── Fetch BERA ───────────────────────────────────────────────────────────

  /// Fetch le BERA du centre d'une bbox. Idempotent dans une plage de quelques
  /// dizaines de km : on ne refetch que si on bouge significativement.
  LatLng? _lastBeraPoint;
  Future<void> fetchBeraFor(LatLng center) async {
    if (_lastBeraPoint != null) {
      final dLat = (center.latitude  - _lastBeraPoint!.latitude ).abs();
      final dLon = (center.longitude - _lastBeraPoint!.longitude).abs();
      // ~30 km à la latitude des Alpes
      if (dLat < 0.3 && dLon < 0.3) return;
    }

    // Invalider _beraFull IMMÉDIATEMENT avant l'appel réseau.
    // Sans ça, si fetchAvalanche() est appelé pendant le fetch BERA
    // (onBboxDrawn() les déclenche quasi-simultanément), il utilise le
    // _beraFull du massif précédent → cônes calculés avec le mauvais BERA.
    // Mieux vaut un fallback backend (beraFull=null) que des cônes faux.
    _beraFull = null;

    try {
      final info = await _api.getBeraInfo(center);
      final previousMassif = _bera?.massifName;
      _bera = info;
      _lastBeraPoint = center;

      // Charge BeraFull de façon synchrone (pas fire-and-forget).
      // fetchAvalanche() peut être rappelé après le changement de zone —
      // _beraFull sera disponible pour le prochain calcul.
      if (info?.massifName != null) {
        try {
          _beraFull = await _beraFullService.getByMassifName(info!.massifName!);
          debugPrint('[conditions] beraFull: ${_beraFull?.massif ?? "non trouvé"}');
        } catch (e) {
          debugPrint('[conditions] beraFull load failed: \$e');
          _beraFull = null;
        }
      }

      // Notifier seulement si le massif a changé — évite la boucle rebuild.
      if (info?.massifName != previousMassif) notifyListeners();
    } catch (e) {
      debugPrint('[conditions] BERA fetch failed: \$e');
      // Pas d'erreur visible — le BERA est secondaire
    }
  }

  // ── Avalanche ────────────────────────────────────────────────────────────

  /// Toggle l'affichage des cônes d'avalanche. Si on active et qu'on n'a pas
  /// encore les données, on fetch.
  Future<void> toggleAvalanche() async {
    _avalancheVisible = !_avalancheVisible;
    notifyListeners();
    if (_avalancheVisible) {
      // Fetcher toutes les bbox dessinées sans résultat encore
      for (final box in _drawnBboxes) {
        final key = _bboxKey(box.sw, box.ne);
        if (!_avalancheByBbox.containsKey(key)) {
          await fetchAvalanche(box);
        }
      }
    }
  }

  /// Change le risque appliqué (override). Refetch automatique sur toutes
  /// les bbox connues si l'avalanche est visible.
  /// Debounce : si setRiskOverride est appelé rapidement (slider), on
  /// annule le calcul précédent avant de relancer.
  int _riskOverrideVersion = 0;

  Future<void> setRiskOverride(int? risk) async {
    if (risk == _riskOverride) return;
    _riskOverride = risk;
    _riskOverrideVersion++; // invalide les calculs en cours
    final version = _riskOverrideVersion;
    notifyListeners();
    if (!_avalancheVisible) return;

    // Refetcher toutes les bbox avec le nouveau risque.
    // On ne vide PAS _avalancheByBbox avant — l'UI garde les anciens résultats
    // pendant le recalcul (pas de flash vide).
    for (final box in List.of(_drawnBboxes)) {
      // Si un nouveau setRiskOverride est arrivé entre-temps → abandonner
      if (version != _riskOverrideVersion) return;
      await fetchAvalanche(box);
    }
  }

  /// Calcule les zones d'avalanche pour la bbox courante.
  ///
  /// Stratégie locale-first :
  ///   1. Si tuiles HGT disponibles → AvalancheEngine local (offline,
  ///      instantané, sans cold-start Render)
  ///   2. Sinon → fallback appel backend Render (comportement précédent)
  ///
  /// Même AvalancheResponse dans les deux cas — l'UI ne voit pas la différence.
  Future<void> fetchAvalanche([({LatLng sw, LatLng ne})? forcedBox]) async {
    // Si une bbox est passée explicitement (ex: depuis onDrawEnd après que
    // _drawAnchor a été mis à null), on l'utilise. Sinon on lit drawnBbox.
    final box = forcedBox ?? drawnBbox;
    if (box == null) {
      debugPrint('[conditions] avalanche fetch ignoré — pas de bbox dessinée');
      return;
    }

    final bboxKey = _bboxKey(box.sw, box.ne);
    _currentBboxKey = bboxKey;
    final beraFull  = _beraFull;
    // Snapshot de la version courante — si elle change pendant le calcul
    // (nouveau setRiskOverride), on abandonne silencieusement.
    final version = _riskOverrideVersion;

    _avalancheLoading = true;
    notifyListeners();

    debugPrint('[conditions] avalanche: beraFull=${beraFull?.massif ?? "null"}, '
        'bbox=${box.sw.latitude.toStringAsFixed(3)},${box.sw.longitude.toStringAsFixed(3)}');

    try {
      if (beraFull != null) {
        // ── Tentative locale (HGT) ─────────────────────────────────────────
        final local = await AvalancheEngine.computeZones(
          sw:           box.sw,
          ne:           box.ne,
          bera:         beraFull,
          riskOverride: _riskOverride,
          // maxZones calculé automatiquement selon la taille de la bbox
        );

        if (local != null) {
          if (version != _riskOverrideVersion) return; // résultat périmé
          debugPrint('[conditions] avalanche local : '
              '${local.startZones.length} zones, ${local.mergedZones?.length ?? 0} fusionnées');
          _avalancheByBbox[bboxKey] = local;
          return;
        }

        debugPrint('[conditions] HGT indispo → fallback backend Render');
      }

      // ── Fallback backend ───────────────────────────────────────────────
      final response = await _api.fetchAvalanche(
        box.sw,
        box.ne,
        riskOverride: _riskOverride,
      );
      if (response != null) _avalancheByBbox[bboxKey] = response;
    } catch (e) {
      debugPrint('[conditions] avalanche failed: $e');
      // En cas d'erreur on ne supprime pas les résultats précédents
      _errorMessage = 'Erreur avalanche : $e';
    } finally {
      _avalancheLoading = false;
      notifyListeners();
    }
  }

  // ── Best window (créneau moquette/poudreuse) ─────────────────────────────

  /// Toggle l'affichage du meilleur créneau. Fetch automatique si pas encore
  /// chargé et qu'on a une bbox dessinée.
  Future<void> toggleBestWindow() async {
    _bestWindowVisible = !_bestWindowVisible;
    notifyListeners();
    if (_bestWindowVisible && _bestWindow == null) {
      await fetchBestWindow();
    }
  }

  /// Fetch le best-window pour la bbox courante (dessinée par l'utilisateur).
  /// Sans bbox, n'a pas de sens — on ne fait rien.
  Future<void> fetchBestWindow() async {
    final box = drawnBbox;
    if (box == null) {
      debugPrint('[conditions] best-window fetch ignoré — pas de bbox');
      return;
    }
    _bestWindowLoading = true;
    notifyListeners();
    try {
      _bestWindow = await _api.fetchBestWindow(
        box.sw,
        box.ne,
        date: _selectedDate,
      );
    } catch (e) {
      debugPrint('[conditions] best-window fetch failed: $e');
      _bestWindow = null;
      _errorMessage = 'Erreur best-window : $e';
    } finally {
      _bestWindowLoading = false;
      notifyListeners();
    }
  }

  // ── Détail au tap (un point précis) ──────────────────────────────────────

  /// Récupère les conditions complètes d'un point — bypass cache, toujours
  /// frais (c'est appelé sur tap utilisateur, peu fréquent).
  Future<PointConditions?> fetchPointDetail(LatLng point) async {
    try {
      return await _api.getPointConditions(point: point, date: _selectedDate);
    } catch (e) {
      debugPrint('[conditions] point detail failed: $e');
      return null;
    }
  }

  @override
  void dispose() {
    _fetchDebounce?.cancel();
    super.dispose();
  }
}

class _Bbox {
  final LatLng sw;
  final LatLng ne;
  const _Bbox(this.sw, this.ne);
}