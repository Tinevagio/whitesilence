// lib/modules/time/time_controller.dart
//
// Contrôleur du module Temps.
//
// Orchestre :
//   - le MunterEngine (reconstruit quand le profil global change)
//   - le GpsCalibrator (branché sur GpsService partagé)
//   - le DEM sélectionné (HGT > Open-Meteo > Demo)
//   - le calcul d'isochrones
//   - l'estimation ponctuelle vers un point tap
//
// Remplace la partie "temps/isochrones" de l'ancien app_state.dart de TimeToGo.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/elevation/dem_selector.dart';
import '../../core/elevation/elevation_provider.dart';
import '../../core/gps/gps_service.dart';
import '../../shared/settings/user_profile.dart';
import 'gps_calibrator.dart';
import 'isochrone.dart';
import 'munter.dart';
import 'profile_adapter.dart';

/// Clé SharedPreferences pour la persistance de la calibration Munter.
/// Format JSON : { "profile": "skiTouring/trained/normal", "measurements": [...] }
const String _kMunterSnapshotKey = 'time.munter.snapshot';

class TimeController extends ChangeNotifier {
  static final TimeController _instance = TimeController._();
  factory TimeController() => _instance;
  TimeController._() {
    _rebuildEngine();
    _userProfile.addListener(_onProfileChanged);
  }

  // ── Dépendances ──────────────────────────────────────────────────────────
  final UserProfile _userProfile = UserProfile();
  final GpsService  _gps         = GpsService();

  // ── Munter ───────────────────────────────────────────────────────────────
  late MunterEngine _munter;
  late GpsCalibrator _calibrator;

  MunterEngine get munter => _munter;
  bool get isCalibrated   => _munter.isCalibrated;
  Map<String, dynamic> get calibrationReport => _munter.calibrationReport();
  Map<String, String>  get calibratorReport  => _calibrator.report;

  // ── Isochrones ───────────────────────────────────────────────────────────
  Map<int, List<LatLng>> _contours = {};
  Map<int, List<LatLng>> get contours => _contours;

  bool      _computing = false;
  Duration? _lastComputeDuration;
  bool      get computing => _computing;
  Duration? get lastComputeDuration => _lastComputeDuration;

  // ── DEM cache ────────────────────────────────────────────────────────────
  ElevationProvider? _cachedDem;
  LatLng?           _cachedDemCenter;
  DemSource         _demSource = DemSource.openMeteo;
  DemSource get demSource => _demSource;
  String  get demSourceLabel => _demSource.label;

  // ── Affichage couverture HGT ─────────────────────────────────────────────
  // Toggle pour afficher les tuiles HGT (installées en vert, manquantes en
  // orange cliquable) directement sur la carte. Off par défaut pour ne pas
  // surcharger visuellement quand on veut juste consulter les isochrones.
  bool _showHgtCoverage = false;
  bool get showHgtCoverage => _showHgtCoverage;

  void toggleHgtCoverage() {
    _showHgtCoverage = !_showHgtCoverage;
    notifyListeners();
  }

  // ── Estimation ponctuelle ────────────────────────────────────────────────
  LatLng? _targetPoint;
  String? _pointEstimate;
  LatLng? get targetPoint   => _targetPoint;
  String? get pointEstimate => _pointEstimate;

  // ── Point d'origine épinglé ──────────────────────────────────────────────
  // Si non-null, prime sur la position GPS pour le calcul d'isochrones et
  // l'estimation ponctuelle. Posé via long-press sur la carte.
  LatLng? _pinnedOrigin;
  LatLng? get pinnedOrigin => _pinnedOrigin;

  /// Point utilisé comme origine des calculs : pin si posé, sinon position GPS.
  LatLng? get effectiveOrigin => _pinnedOrigin ?? _gps.lastLatLng;

  /// Pose un pin d'origine (long-press) ou le déplace.
  /// Invalide les isochrones précédentes pour éviter la confusion.
  void setPinnedOrigin(LatLng pos) {
    _pinnedOrigin = pos;
    _contours      = {};
    _targetPoint   = null;
    _pointEstimate = null;
    notifyListeners();
  }

  /// Retire le pin et revient à la position GPS comme origine.
  void clearPinnedOrigin() {
    if (_pinnedOrigin == null) return;
    _pinnedOrigin = null;
    _contours      = {};
    _targetPoint   = null;
    _pointEstimate = null;
    notifyListeners();
  }

  // ── Réaction au changement de profil ─────────────────────────────────────
  void _onProfileChanged() => _rebuildEngine();

  // Marqueur : est-ce qu'on a déjà construit le calibrateur ?
  // (évite un LateInitializationError au premier _rebuildEngine)
  bool _calibratorInitialized = false;
  // Marqueur : est-ce qu'on a déjà branché le calibrateur sur le GPS ?
  // (pour ne pas oublier le re-branchement lors d'un rebuild de l'engine)
  bool _calibratorAttached = false;

  bool _restoring = false;
  MunterEngine? _munterBeingRestored;

  void _rebuildEngine() {
    _munter = MunterEngine(munterProfileFrom(_userProfile));
    // Si on avait déjà un calibrateur, on le détache du GPS avant d'en
    // créer un nouveau lié au nouveau moteur.
    if (_calibratorInitialized) {
      _calibrator.dispose();
    }
    _calibrator = GpsCalibrator(munter: _munter, dem: _cachedDem);
    // Branche les notifications du calibrator pour que l'UI suive en
    // temps réel + sauver la calibration après chaque update.
    _calibrator.onUpdate = () {
      _saveSnapshot();
      notifyListeners();
    };
    _calibratorInitialized = true;
    if (_calibratorAttached) _calibrator.attachToGpsService();

    // Tente de restaurer la calibration précédente. Si la signature de
    // profil ne correspond plus, le snapshot est ignoré (calibration repart
    // proprement de zéro pour ce nouveau profil).
    // Fire-and-forget : on n'attend pas le résultat pour libérer le UI.
    _restoreSnapshot();

    if (!_computing) {
      _contours      = {};
      _targetPoint   = null;
      _pointEstimate = null;
    }
    notifyListeners();
  }

  /// À appeler une fois au démarrage de l'app si le module Temps est actif.
  void start() {
    if (_calibratorAttached) return;
    _calibrator.attachToGpsService();
    _calibratorAttached = true;
    AppLifecycleListener(
      onInactive: _onAppInactive,
      onPause:    _onAppInactive,
      onDetach:   _onAppInactive,
    );
  }

  void _onAppInactive() {
    _saveSnapshot();
  }

  @override
  void dispose() {
    _userProfile.removeListener(_onProfileChanged);
    _calibrator.dispose();
    super.dispose();
  }

  // ── Calcul d'isochrones ──────────────────────────────────────────────────

  /// Lance le calcul d'isochrones autour de [origin].
  /// Si [origin] est null, utilise le point épinglé (long-press) ou à défaut
  /// la position GPS courante.
  Future<void> computeIsochrones({LatLng? origin}) async {
    final from = origin ?? effectiveOrigin;
    if (from == null) {
      debugPrint('Time: pas de position pour calculer les isochrones');
      return;
    }
    if (_computing) return;

    _computing = true;
    _contours  = {};
    notifyListeners();

    try {
      // Utilise le moteur calibré (_munter) — et non un engine local vierge.
      // Bug corrigé v2 : créer un MunterEngine local ici ignorait toute la
      // calibration GPS accumulée pendant la sortie.
      final munter = _munter;

      // Grille Open-Meteo : 2 km de rayon
      const gridRadiusM = 2000.0;
      final gridDeg = gridRadiusM / 111000;
      final sw = LatLng(from.latitude  - gridDeg, from.longitude - gridDeg);
      final ne = LatLng(from.latitude  + gridDeg, from.longitude + gridDeg);

      // Rayon HGT élargi : on prefetche aussi les tuiles couvrant le rayon
      // max théorique des isochrones de 60 min
      final maxRayM = munter.maxHorizontalDistance(60 * 60.0)
          .clamp(3000.0, 12000.0) * 1.5;
      final maxRayDeg = maxRayM / 111000;
      final swFull = LatLng(from.latitude  - maxRayDeg, from.longitude - maxRayDeg);
      final neFull = LatLng(from.latitude  + maxRayDeg, from.longitude + maxRayDeg);

      // Sélection du DEM
      final selection = await DemSelector.select(
        center:          from,
        prefetchSw:      swFull,
        prefetchNe:      neFull,
        previous:        _cachedDem,
        previousCenter:  _cachedDemCenter,
        previousSource:  _demSource,
      );
      _cachedDem       = selection.provider;
      _cachedDemCenter = from;
      _demSource       = selection.source;
      _calibrator.updateDem(_cachedDem!);

      // Le DemSelector prefetche le rayon max, mais Open-Meteo n'utilise
      // qu'une grille 10x10 — on lui demande la grille resserrée 2km
      if (selection.source == DemSource.openMeteo) {
        await selection.provider.prefetch(sw, ne);
      }

      final engine = IsochroneEngine(
        munter: munter,
        dem:    selection.provider,
        config: IsochroneConfig(
          timeBudgetsMinutes: const [15, 30, 45, 60],
          rayCount:           72,
          baseStepM:          40,
          minStepM:           10,
          maxStepM:           80,
          maxRayDistanceM:    maxRayM,
        ),
      );

      final result = await engine.compute(from);
      _contours = result.contours.map(
        (k, v) => MapEntry(k, chaikinSmooth(v, iterations: 2)),
      );
      _lastComputeDuration = result.computeDuration;
    } catch (e, st) {
      debugPrint('Erreur isochrones: $e\n$st');
    } finally {
      _computing = false;
      notifyListeners();
    }
  }

  void clearIsochrones() {
    _contours = {};
    notifyListeners();
  }

  // ── Estimation ponctuelle ────────────────────────────────────────────────

  /// Estime le temps depuis l'origine effective (pin ou GPS) vers [target].
  Future<void> estimateToPoint(LatLng target) async {
    _targetPoint   = target;
    _pointEstimate = 'Calcul…';
    notifyListeners();

    final origin = effectiveOrigin;
    if (origin == null) {
      _pointEstimate = 'Position inconnue';
      notifyListeners();
      return;
    }

    // Si on n'a pas encore de DEM, on en charge un autour de l'origine
    if (_cachedDem == null) {
      final around = 0.02; // ~2 km
      final selection = await DemSelector.select(
        center:     origin,
        prefetchSw: LatLng(origin.latitude  - around, origin.longitude - around),
        prefetchNe: LatLng(origin.latitude  + around, origin.longitude + around),
      );
      _cachedDem       = selection.provider;
      _cachedDemCenter = origin;
      _demSource       = selection.source;
      _calibrator.updateDem(_cachedDem!);
    }

    double originAlt, targetAlt;
    try {
      originAlt = await _cachedDem!.getElevation(origin.latitude, origin.longitude);
      targetAlt = await _cachedDem!.getElevation(target.latitude, target.longitude);
    } catch (_) {
      _pointEstimate = 'Altitude indisponible';
      notifyListeners();
      return;
    }

    final elevDiff = targetAlt - originAlt;
    final distM    = const Distance().as(
        LengthUnit.Meter, origin, target);
    final secs = _munter.estimateSeconds(
      distanceM: distM,
      elevGain:  elevDiff > 0 ? elevDiff : 0,
      elevLoss:  elevDiff < 0 ? -elevDiff : 0,
    );

    final totalMin = (secs / 60).round();
    final h   = totalMin ~/ 60;
    final min = totalMin % 60;
    final timeStr = h > 0 ? '${h}h${min.toString().padLeft(2,'0')}' : '$min min';
    final distStr = distM < 1000
        ? '${distM.round()} m'
        : '${(distM / 1000).toStringAsFixed(1)} km';
    final elevStr = elevDiff >= 0
        ? '+${elevDiff.round()} m'
        : '${elevDiff.round()} m';

    _pointEstimate = '$timeStr  ·  $distStr  ·  $elevStr';
    notifyListeners();
  }

  void clearTarget() {
    _targetPoint   = null;
    _pointEstimate = null;
    notifyListeners();
  }

  // ── Persistance Munter ──────────────────────────────────────────────────
  //
  // On sauve les N dernières mesures GPS avec la signature du profil. Au
  // démarrage, on tente de recharger : si la signature matche, la
  // calibration reprend où elle en était. Si elle ne matche pas (profil
  // modifié), on ignore le snapshot et la calibration repart de zéro.
  //
  // Stratégie debounce : `_saveSnapshot()` est appelé après chaque mesure
  // GPS, soit potentiellement plusieurs fois par minute en sortie. C'est
  // OK car SharedPreferences est rapide (~ms) et le payload est petit
  // (< 1 KB). Pas besoin de debouncing complexe.

  Future<void> _saveSnapshot() async {
    if (_restoring) {
      return;
    }
    try {
      final snapshot = _munter.toSnapshot();
      final ms = snapshot['measurements'];
      if (ms is List && ms.isEmpty) {
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kMunterSnapshotKey, jsonEncode(snapshot));
    } catch (e) {
    }
  }

  Future<void> _restoreSnapshot() async {
    final targetMunter = _munter;
    _munterBeingRestored = targetMunter;
    _restoring = true;
    try {
      final prefs = await SharedPreferences.getInstance();

      if (!identical(_munter, targetMunter)) {
        return;
      }

      final raw = prefs.getString(_kMunterSnapshotKey);
      if (raw == null || raw.isEmpty) {
        return;
      }

      final snapshot = jsonDecode(raw) as Map<String, dynamic>;

      final ok = targetMunter.restoreFromSnapshot(snapshot);
      if (ok) {
        notifyListeners();
      } else {
        await prefs.remove(_kMunterSnapshotKey);
      }
    } catch (e) {
    } finally {
      _restoring = false;
      if (identical(_munterBeingRestored, targetMunter)) {
        _munterBeingRestored = null;
      }
    }
  }

  /// Efface manuellement la calibration sauvegardée.
  /// Utile pour un bouton "Réinitialiser la calibration" dans Réglages.
  Future<void> clearMunterCalibration() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kMunterSnapshotKey);
    _rebuildEngine();
  }
}

