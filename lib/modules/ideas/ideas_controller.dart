// lib/modules/ideas/ideas_controller.dart
//
// Orchestrateur d'état du module Idées.
//
// Responsabilités :
//   - Cold-start handling (ping /health au démarrage)
//   - Stocke les filtres utilisateur (singleton durée de session)
//   - Lance la recherche /ideas et expose loading/error/results
//   - Track l'idée sélectionnée (pour la mise en évidence sur la carte)
//   - Charge les métadonnées (liste de massifs / dates dispo) une fois.

import 'package:flutter/foundation.dart';

import 'models/idea.dart';
import 'models/ideas_filter.dart';
import 'models/ideas_response.dart';
import 'services/ideas_api.dart';
import 'services/ideas_preferences.dart';

enum IdeasStatus {
  idle,        // pas encore lancé
  warming,     // cold start backend en cours
  metadataLoading,
  loading,     // recherche en cours
  ready,       // résultats prêts
  empty,       // 0 résultats trouvés
  error,
}

class IdeasController extends ChangeNotifier {
  static final IdeasController _instance = IdeasController._();
  factory IdeasController() => _instance;
  IdeasController._() {
    // Quand l'utilisateur masque/ajoute en wishlist depuis n'importe où dans
    // l'UI, on rebuild aussi (le filtrage des masqués se refait au vol via
    // `displayedIdeas`, et les icônes des cards rebuild).
    _preferences.addListener(_onPreferencesChanged);
  }

  void _onPreferencesChanged() {
    // Si l'idée actuellement sélectionnée vient d'être masquée, la liste
    // affichée a rétréci et _selectedIndex peut pointer dans le vide.
    // On le clamp à la nouvelle longueur (ou -1 si liste vide).
    final list = displayedIdeas;
    if (_selectedIndex >= list.length) {
      _selectedIndex = list.isEmpty ? -1 : list.length - 1;
    }
    notifyListeners();
  }

  final IdeasApi _api = IdeasApi();
  final IdeasPreferences _preferences = IdeasPreferences();

  // ── État ────────────────────────────────────────────────────────────────
  IdeasStatus _status = IdeasStatus.idle;
  IdeasStatus get status => _status;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  IdeasFilter _filter = IdeasFilter(date: _defaultDate());
  IdeasFilter get filter => _filter;

  IdeasMetadata? _metadata;
  IdeasMetadata? get metadata => _metadata;

  IdeasResponse? _lastResponse;
  IdeasResponse? get lastResponse => _lastResponse;

  /// Indice de l'idée actuellement focalisée (pin agrandi sur la carte +
  /// Indice de l'idée actuellement focalisée DANS LA LISTE AFFICHÉE
  /// (`displayedIdeas`), pas dans la réponse brute backend. -1 = aucune.
  /// Quand l'utilisateur tap un pin sur la carte, ce champ est mis à jour
  /// et le carousel doit scroller pour montrer la card correspondante.
  int _selectedIndex = -1;
  int get selectedIndex => _selectedIndex;

  /// Idées effectivement affichées à l'utilisateur : on part de la réponse
  /// backend et on filtre les sorties masquées (sauf si `filter.showHidden`
  /// est vrai, auquel cas on les laisse passer pour permettre le démasquage).
  List<Idea> get displayedIdeas {
    if (_lastResponse == null) return const [];
    final all = _lastResponse!.ideas;
    if (_filter.showHidden) return all;
    return all.where((i) => !_preferences.isHidden(i.url)).toList();
  }

  Idea? get selectedIdea {
    final list = displayedIdeas;
    if (_selectedIndex < 0 || _selectedIndex >= list.length) return null;
    return list[_selectedIndex];
  }

  /// Accès direct aux préférences pour l'UI (icônes des cards, sheet wishlist).
  IdeasPreferences get preferences => _preferences;

  bool _wakeSucceeded = false;

  // ── Cycle de vie ────────────────────────────────────────────────────────

  /// Idempotent. Appelé quand le module devient actif. Ping le backend en
  /// arrière-plan + charge les métadonnées. Si le réseau n'est pas dispo,
  /// retentera silencieusement à la prochaine action (search ou ouverture
  /// de la sheet de filtres).
  Future<void> start() async {
    // Charger les préférences locales (hidden + wishlist). Idempotent.
    // C'est rapide (SharedPreferences) donc on attend la complétion.
    if (!_preferences.isLoaded) {
      await _preferences.load();
    }

    if (_wakeSucceeded) return;
    if (_status == IdeasStatus.warming) return; // déjà en cours
    _status = IdeasStatus.warming;
    notifyListeners();

    final ok = await _api.wakeUp();
    _wakeSucceeded = ok;

    // Métadonnées en arrière-plan, sans bloquer l'UI
    _loadMetadata();
    _status = IdeasStatus.idle;
    notifyListeners();
  }

  Future<void> _loadMetadata() async {
    try {
      _metadata = await _api.getMetadata();
      notifyListeners();
    } catch (e) {
      debugPrint('[ideas] metadata load failed: $e');
      // Pas bloquant : on continuera avec les valeurs par défaut côté UI.
      // L'UI peut rappeler `ensureMetadata()` quand l'utilisateur l'ouvre.
    }
  }

  /// Garantit que les métadonnées sont chargées. Si elles le sont déjà,
  /// no-op. Sinon, retente un fetch. Appelé par la bottom sheet de filtres
  /// à son ouverture pour récupérer après une panne réseau au démarrage.
  Future<void> ensureMetadata() async {
    if (_metadata != null) return;
    await _loadMetadata();
  }

  // ── Filtres ─────────────────────────────────────────────────────────────

  void updateFilter(IdeasFilter newFilter) {
    _filter = newFilter;
    notifyListeners();
  }

  // ── Recherche ───────────────────────────────────────────────────────────

  /// Lance la recherche avec les filtres courants.
  /// Si le backend n'a pas encore été réveillé (panne réseau au démarrage),
  /// affiche le status "warming" pendant le wake-up puis fait la requête.
  Future<void> search() async {
    // Wake-up préalable si on n'est pas sûr que le backend tourne
    if (!_wakeSucceeded) {
      _status = IdeasStatus.warming;
      notifyListeners();
      _wakeSucceeded = await _api.wakeUp();
      // Si /metadata n'avait pas chargé, on en profite (best-effort)
      if (_metadata == null) {
        await _loadMetadata();
      }
    }

    _status = IdeasStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await _api.getIdeas(_filter);
      _lastResponse = res;
      // Sélection initiale par rapport à la liste AFFICHÉE (post-filtrage
      // des masqués). Si tout est masqué, on a une liste vide même si le
      // backend a retourné des résultats — status reste 'ready' mais le
      // carousel ne montrera rien (l'utilisateur peut activer "Voir les
      // sorties masquées" dans les filtres pour démasquer).
      final shown = displayedIdeas;
      _selectedIndex = shown.isEmpty ? -1 : 0;
      _status = res.ideas.isEmpty
          ? IdeasStatus.empty
          : IdeasStatus.ready;
    } on IdeasApiException catch (e) {
      _errorMessage = e.message;
      _status = IdeasStatus.error;
    } catch (e) {
      _errorMessage = e.toString();
      _status = IdeasStatus.error;
    }
    notifyListeners();
  }

  /// Sélectionne une idée par son index dans la LISTE AFFICHÉE.
  /// Notif pour que la carte recentre et le carousel scrolle.
  void selectIdea(int index) {
    final list = displayedIdeas;
    if (index < 0 || index >= list.length) return;
    if (index == _selectedIndex) return;
    _selectedIndex = index;
    notifyListeners();
  }

  /// Vide les résultats (utile quand on revient sur l'écran).
  void clearResults() {
    _lastResponse = null;
    _selectedIndex = -1;
    _status = IdeasStatus.idle;
    notifyListeners();
  }

  static DateTime _defaultDate() {
    final now = DateTime.now();
    // Par défaut : demain (planification typique d'une sortie)
    return DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  }
}
