// lib/modules/conditions/services/bera_full_service.dart
//
// Récupère et cache le JSON BERA enrichi depuis le repo public
// Tinevagio/Ski-touring-live (mis à jour quotidiennement via cron CI).
//
// Stratégie cache :
//   - Au premier appel : tente de fetch live, fallback sur cache si erreur réseau.
//   - Si cache < 24h : on le sert direct, pas de fetch.
//   - Si cache > 24h : on fetch en background et on remplace.
//   - SharedPreferences pour stocker le JSON brut (typiquement ~70 KB,
//     largement dans les limites).
//
// L'app marche donc hors-ligne dès qu'on a fetché au moins une fois.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/bera_full.dart';

class BeraFullService {
  // Singleton léger.
  static final BeraFullService _instance = BeraFullService._();
  factory BeraFullService() => _instance;
  BeraFullService._();

  static const String _kUrl =
      'https://raw.githubusercontent.com/Tinevagio/Ski-touring-live/main/data/bera_enneigement.json';

  static const String _kPrefsBody = 'bera_full.body';
  static const String _kPrefsAt   = 'bera_full.fetched_at';
  static const Duration _kFreshness = Duration(hours: 24);
  static const Duration _kTimeout   = Duration(seconds: 15);

  /// Mémoire process : évite de relire SharedPreferences + parser à chaque appel.
  List<BeraFull>? _memCache;
  DateTime?       _memCacheAt;

  /// Liste de tous les massifs disponibles.
  /// - Sert depuis le cache mémoire si dispo, sinon SharedPreferences,
  ///   sinon fetch réseau, sinon throw.
  /// - Si `forceRefresh: true`, ignore les caches et re-fetch.
  Future<List<BeraFull>> getAll({bool forceRefresh = false}) async {
    // 1. Cache mémoire valide
    if (!forceRefresh && _memCache != null && _isFresh(_memCacheAt)) {
      return _memCache!;
    }

    // 2. Cache disque valide
    final prefs = await SharedPreferences.getInstance();
    if (!forceRefresh) {
      final cachedAt = _readInstant(prefs, _kPrefsAt);
      final cachedBody = prefs.getString(_kPrefsBody);
      if (cachedBody != null && _isFresh(cachedAt)) {
        final parsed = _parse(cachedBody);
        _memCache   = parsed;
        _memCacheAt = cachedAt;
        return parsed;
      }
    }

    // 3. Fetch réseau, avec fallback sur cache disque si erreur
    try {
      final body = await _fetch();
      final parsed = _parse(body);
      _memCache   = parsed;
      _memCacheAt = DateTime.now();
      await prefs.setString(_kPrefsBody, body);
      await prefs.setString(_kPrefsAt, _memCacheAt!.toIso8601String());
      return parsed;
    } catch (e) {
      // Plan B : tenter le cache disque même si expiré (réseau HS, on dépanne)
      final cachedBody = prefs.getString(_kPrefsBody);
      if (cachedBody != null) {
        debugPrint('[bera_full] Fetch failed ($e), serving stale cache.');
        final parsed = _parse(cachedBody);
        _memCache = parsed;
        _memCacheAt = _readInstant(prefs, _kPrefsAt);
        return parsed;
      }
      // Plan C : rien à servir
      rethrow;
    }
  }

  /// Récupère le BERA d'un massif par son nom (case-insensitive).
  /// Retourne null si le massif n'est pas dans la liste.
  Future<BeraFull?> getByMassifName(String name,
      {bool forceRefresh = false}) async {
    final all = await getAll(forceRefresh: forceRefresh);
    final lower = name.trim().toLowerCase();
    for (final b in all) {
      if (b.massif.toLowerCase() == lower) return b;
    }
    return null;
  }

  /// Date de dernière mise à jour locale du cache (peut être null si jamais fetché).
  Future<DateTime?> lastFetchedAt() async {
    if (_memCacheAt != null) return _memCacheAt;
    final prefs = await SharedPreferences.getInstance();
    return _readInstant(prefs, _kPrefsAt);
  }

  // ─── Helpers privés ───────────────────────────────────────────────────────

  Future<String> _fetch() async {
    final resp = await http
        .get(Uri.parse(_kUrl), headers: {'Accept': 'application/json'})
        .timeout(_kTimeout);
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode} sur $_kUrl');
    }
    return resp.body;
  }

  List<BeraFull> _parse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List) {
      throw const FormatException('JSON BERA: racine attendue = List');
    }
    return decoded
        .whereType<Map>()
        .map((e) => BeraFull.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  bool _isFresh(DateTime? at) {
    if (at == null) return false;
    return DateTime.now().difference(at) < _kFreshness;
  }

  DateTime? _readInstant(SharedPreferences prefs, String key) {
    final s = prefs.getString(key);
    if (s == null) return null;
    return DateTime.tryParse(s);
  }
}