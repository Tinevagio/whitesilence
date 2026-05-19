// lib/modules/conditions/services/conditions_cache.dart
//
// Cache des grilles de conditions Névé en SQLite.
//
// Clé = "bbox|date|resolution" (arrondi à 4 décimales pour pas exploser la
// cardinalité quand l'utilisateur bouge la carte d'1 pixel).
// TTL : par défaut 6h.
//
// Philosophie WhiteSilence : sans réseau, on sert quand même la dernière
// donnée connue, avec un badge "donnée d'hier" côté UI.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/storage/db.dart';
import '../models/point_conditions.dart';

class CachedConditions {
  final ConditionsResponse response;
  final DateTime fetchedAt;
  const CachedConditions(this.response, this.fetchedAt);

  Duration get age => DateTime.now().difference(fetchedAt);
  bool isStale(Duration ttl) => age > ttl;
}

class ConditionsCache {
  static const _table = 'conditions_cache';
  static const Duration defaultTtl = Duration(hours: 6);

  /// Construit la clé de cache. On arrondit la bbox à 4 décimales
  /// (~11m de précision) pour regrouper les requêtes proches.
  static String makeKey({
    required LatLng sw,
    required LatLng ne,
    required DateTime date,
    required double resolutionM,
  }) {
    String r4(double v) => v.toStringAsFixed(4);
    final d = '${date.year}-${date.month.toString().padLeft(2, '0')}'
        '-${date.day.toString().padLeft(2, '0')}';
    return '${r4(sw.latitude)},${r4(sw.longitude)},'
           '${r4(ne.latitude)},${r4(ne.longitude)}|'
           '$d|${resolutionM.round()}';
  }

  Future<void> store(String key, ConditionsResponse response) async {
    final db = await WSDatabase.instance();
    await db.insert(
      _table,
      {
        'cache_key':  key,
        'fetched_at': DateTime.now().toIso8601String(),
        'payload':    jsonEncode(_responseToJson(response)),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<CachedConditions?> load(String key) async {
    final db = await WSDatabase.instance();
    final rows = await db.query(_table,
        where: 'cache_key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    try {
      final row     = rows.first;
      final fetched = DateTime.parse(row['fetched_at'] as String);
      final json    = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
      return CachedConditions(ConditionsResponse.fromJson(json), fetched);
    } catch (e) {
      debugPrint('[cache] corrupt entry $key: $e');
      await db.delete(_table, where: 'cache_key = ?', whereArgs: [key]);
      return null;
    }
  }

  /// Supprime les entrées de cache trop anciennes (> 24h par défaut)
  /// pour ne pas faire grossir la BDD à l'infini.
  Future<void> cleanup({Duration maxAge = const Duration(hours: 24)}) async {
    final db     = await WSDatabase.instance();
    final cutoff = DateTime.now().subtract(maxAge).toIso8601String();
    await db.delete(_table, where: 'fetched_at < ?', whereArgs: [cutoff]);
  }

  Future<void> clear() async {
    final db = await WSDatabase.instance();
    await db.delete(_table);
  }

  // ── Sérialisation ───────────────────────────────────────────────────────
  // Pour ne pas dépendre d'un toJson() sur les modèles, on regénère depuis
  // le format API d'origine. La clé : on stocke un JSON équivalent à ce que
  // l'API renvoie, parsable par fromJson().

  static Map<String, dynamic> _responseToJson(ConditionsResponse r) => {
        'date':         r.date,
        'bbox':         r.bbox,
        'resolution_m': r.resolutionM,
        'generated_at': r.generatedAt,
        'points': r.points.map((p) => {
              'lat':          p.lat,
              'lon':          p.lon,
              'elevation_m':  p.elevationM,
              'aspect_deg':   p.aspectDeg,
              'aspect_label': p.aspectLabel,
              'slope_deg':    p.slopeDeg,
              'bera': p.bera == null
                  ? null
                  : {
                      'massif_name':       p.bera!.massifName,
                      'bera_date':         p.bera!.beraDate,
                      'limite_nord_m':     p.bera!.limiteNordM,
                      'limite_sud_m':      p.bera!.limiteSudM,
                      'bera_72h_cm':       p.bera!.bera72hCm,
                      'bera_24h_cm':       p.bera!.bera24hCm,
                      'risque_bas':        p.bera!.risqueBas,
                      'risque_haut':       p.bera!.risqueHaut,
                      'enneigement_niveaux': p.bera!.enneigementNiveaux
                          ?.map((n) => {
                                'alti': n.alti,
                                'N_cm': n.nCm,
                                'S_cm': n.sCm,
                              })
                          .toList(),
                    },
              'hours': p.hours.map((h) => {
                    'hour':         h.hour,
                    'condition':    h.condition,
                    'label':        h.label,
                    'color':        h.color,
                    'temp_surface': h.tempSurface,
                    'wind_speed':   h.windSpeed,
                  }).toList(),
            }).toList(),
      };
}
