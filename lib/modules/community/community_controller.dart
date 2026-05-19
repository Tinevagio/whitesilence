// lib/modules/community/community_controller.dart
//
// Orchestrateur du module Obs (communauté).
//
// Responsabilités :
//   - Fetcher les obs partagées depuis Supabase
//   - Gérer les filtres : types de neige sélectionnés, plage de dates
//   - Exposer l'état (loading / ready / error) à l'UI
//
// L'écriture d'obs reste dans le module Neige — ici c'est lecture seule.
// On ne stocke rien localement (pas de cache SQLite pour l'instant) — chaque
// rafraîchissement re-fetche depuis Supabase.

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../snow/models/observation.dart';
import '../snow/services/supabase_service.dart';

enum CommunityStatus {
  idle,
  loading,
  ready,
  error,
}

class CommunityController extends ChangeNotifier {
  static final CommunityController _instance = CommunityController._();
  factory CommunityController() => _instance;
  CommunityController._();

  final SupabaseService _supabase = SupabaseService();

  // ── État ─────────────────────────────────────────────────────────────────
  CommunityStatus _status = CommunityStatus.idle;
  CommunityStatus get status => _status;

  List<Observation> _all = [];
  List<Observation> get all => List.unmodifiable(_all);

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // ── Filtres ──────────────────────────────────────────────────────────────
  // Types de neige sélectionnés (vide = tous)
  final Set<String> _selectedTypes = {};
  Set<String> get selectedTypes => Set.unmodifiable(_selectedTypes);

  bool isTypeSelected(String type) => _selectedTypes.contains(type);

  void toggleType(String type) {
    if (_selectedTypes.contains(type)) {
      _selectedTypes.remove(type);
    } else {
      _selectedTypes.add(type);
    }
    notifyListeners();
  }

  void clearTypeFilter() {
    if (_selectedTypes.isEmpty) return;
    _selectedTypes.clear();
    notifyListeners();
  }

  // Fenêtre temporelle. Par défaut : 7 jours.
  int _windowDays = 7;
  int get windowDays => _windowDays;
  void setWindowDays(int days) {
    if (days == _windowDays) return;
    _windowDays = days.clamp(1, 90);
    notifyListeners();
    // Re-fetch avec la nouvelle fenêtre
    refresh();
  }

  /// Obs visibles après application des filtres.
  List<Observation> get filtered {
    if (_selectedTypes.isEmpty) return _all;
    return _all.where((o) {
      final t = o.snowType;
      return t != null && _selectedTypes.contains(t);
    }).toList();
  }

  // ── Démarrage ────────────────────────────────────────────────────────────
  bool _started = false;
  Future<void> start() async {
    if (_started) return;
    _started = true;
    // Premier fetch au démarrage du module
    await refresh();
  }

  /// Recharge depuis Supabase la fenêtre courante.
  Future<void> refresh() async {
    _status = CommunityStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      _all = await _supabase.fetchCommunityObs(
        hoursBack: _windowDays * 24,
      );
      _status = CommunityStatus.ready;
    } catch (e) {
      _status = CommunityStatus.error;
      _errorMessage = e.toString();
    }
    notifyListeners();
  }
}
