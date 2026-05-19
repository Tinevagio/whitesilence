// lib/modules/ideas/services/ideas_preferences.dart
//
// Persistence locale des préférences utilisateur sur les idées :
//   - hidden : sorties masquées (ne plus me proposer ça, j'ai déjà fait ou ça
//     ne m'intéresse pas)
//   - wishlist : sorties à faire un jour (mes envies)
//
// Stockage : SharedPreferences, en JSON sérialisé.
// Identifiant stable : l'URL Camptocamp/Skitour de l'itinéraire.
// Tout est purement local — rien ne part en réseau, cohérent avec la philo
// WhiteSilence "sans inscription, sans tracking".
//
// Pattern : singleton + ChangeNotifier pour que l'UI rebuild quand on
// toggle (ex: l'icône change instantanément après tap, le carousel se
// rafraîchit après masquage).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class IdeasPreferences extends ChangeNotifier {
  static final IdeasPreferences _instance = IdeasPreferences._();
  factory IdeasPreferences() => _instance;
  IdeasPreferences._();

  static const _kHiddenKey   = 'ideas.hidden_urls';
  static const _kWishlistKey = 'ideas.wishlist_urls';

  /// Set des URLs masquées. On utilise un Set en RAM pour des lookups O(1)
  /// pendant le rendu (chaque card vérifie son état).
  final Set<String> _hidden = <String>{};
  final Set<String> _wishlist = <String>{};
  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Vues immutables exposées au reste de l'app.
  Set<String> get hiddenUrls   => Set.unmodifiable(_hidden);
  Set<String> get wishlistUrls => Set.unmodifiable(_wishlist);

  int get hiddenCount   => _hidden.length;
  int get wishlistCount => _wishlist.length;

  /// À appeler au démarrage de l'app (ou lazy au premier accès). Idempotent.
  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _hidden..clear()..addAll(_decode(prefs.getString(_kHiddenKey)));
    _wishlist..clear()..addAll(_decode(prefs.getString(_kWishlistKey)));
    _loaded = true;
    notifyListeners();
  }

  // ── Checks ──────────────────────────────────────────────────────────────

  bool isHidden(String? url) {
    if (url == null || url.isEmpty) return false;
    return _hidden.contains(url);
  }

  bool isInWishlist(String? url) {
    if (url == null || url.isEmpty) return false;
    return _wishlist.contains(url);
  }

  // ── Toggles ─────────────────────────────────────────────────────────────

  /// Masque l'itinéraire (l'utilisateur ne veut plus le voir proposé).
  /// Le retire de la wishlist au passage : masqué + wishlist serait
  /// contradictoire.
  Future<void> hide(String url) async {
    if (url.isEmpty) return;
    final changed = _hidden.add(url);
    final removedFromWish = _wishlist.remove(url);
    if (changed || removedFromWish) {
      await _persist();
      notifyListeners();
    }
  }

  /// Dé-masque (l'utilisateur veut le revoir dans les propositions).
  Future<void> unhide(String url) async {
    if (_hidden.remove(url)) {
      await _persist();
      notifyListeners();
    }
  }

  /// Ajoute à la wishlist. Si l'itinéraire était masqué, on le dé-masque
  /// — wishlist gagne sur hidden.
  Future<void> addToWishlist(String url) async {
    if (url.isEmpty) return;
    final added = _wishlist.add(url);
    final unhidden = _hidden.remove(url);
    if (added || unhidden) {
      await _persist();
      notifyListeners();
    }
  }

  /// Retire de la wishlist.
  Future<void> removeFromWishlist(String url) async {
    if (_wishlist.remove(url)) {
      await _persist();
      notifyListeners();
    }
  }

  // ── Utilitaires ─────────────────────────────────────────────────────────

  /// Vide TOUTES les préférences. Bouton "Réinitialiser" dans Réglages plus
  /// tard si tu veux.
  Future<void> clearAll() async {
    _hidden.clear();
    _wishlist.clear();
    await _persist();
    notifyListeners();
  }

  // ── Privé ───────────────────────────────────────────────────────────────

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHiddenKey,   jsonEncode(_hidden.toList()));
    await prefs.setString(_kWishlistKey, jsonEncode(_wishlist.toList()));
  }

  List<String> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list.cast<String>();
    } catch (e) {
      debugPrint('[ideas_prefs] decode failed: $e');
      return const [];
    }
  }
}
