// lib/modules/conditions/services/conditions_api.dart
//
// Client HTTP vers l'API Névé.
// Documentation des endpoints : cf. README de snow-conditions ou /docs en prod.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../../core/secrets.dart';
import '../models/avalanche_zone.dart';
import '../models/bera_info.dart';
import '../models/best_window.dart';
import '../models/point_conditions.dart';

class ConditionsApiException implements Exception {
  final String message;
  final int? statusCode;
  ConditionsApiException(this.message, {this.statusCode});
  @override
  String toString() => 'ConditionsApi: $message'
      '${statusCode != null ? " (HTTP $statusCode)" : ""}';
}

class ConditionsApi {
  /// Base URL configurable via .env (NEVE_API_URL).
  String get _base => WSSecrets.neveApiUrl;

  /// Timeout par défaut. Le backend Render free tier peut être très lent au
  /// cold-start (jusqu'à 2 min pour réveiller une instance Python endormie),
  /// donc on est généreux pour le premier appel. Combiné avec wakeUp() qui
  /// ping /health au démarrage du module, ça rend la lenteur invisible dans
  /// la plupart des cas.
  Duration get _timeout => const Duration(seconds: 120);

  // ── /health ─────────────────────────────────────────────────────────────

  /// Ping le backend pour le réveiller s'il était endormi.
  /// N'attend pas la réponse fonctionnelle, juste que la connexion s'établisse.
  /// Sur Render free tier, ça déclenche le réveil de l'instance Python.
  ///
  /// Retourne true si le backend a répondu correctement, false sinon. On ne
  /// jette jamais : c'est un "best-effort warm-up".
  Future<bool> wakeUp() async {
    final uri = Uri.parse('$_base/health');
    try {
      debugPrint('[conditions] WAKE-UP $uri');
      final r = await http.get(uri).timeout(const Duration(seconds: 90));
      return r.statusCode == 200;
    } catch (e) {
      debugPrint('[conditions] wake-up failed: $e');
      return false;
    }
  }

  // ── /conditions ─────────────────────────────────────────────────────────

  /// Grille de conditions sur une bbox.
  /// [bbox] = (sw, ne). [date] = aujourd'hui si null.
  Future<ConditionsResponse> getConditions({
    required LatLng sw,
    required LatLng ne,
    DateTime? date,
    double resolutionM = 500,
  }) async {
    final bboxStr = _bboxParam(sw, ne);
    final dateStr = _dateParam(date);
    final qp = {
      'bbox':         bboxStr,
      'resolution_m': resolutionM.toString(),
      if (dateStr != null) 'date': dateStr,
    };
    final uri = Uri.parse('$_base/conditions').replace(queryParameters: qp);
    final body = await _getJson(uri);
    return ConditionsResponse.fromJson(body as Map<String, dynamic>);
  }

  // ── /conditions/point ───────────────────────────────────────────────────

  /// Conditions détaillées pour un point précis (24h horaires + BERA).
  Future<PointConditions> getPointConditions({
    required LatLng point,
    DateTime? date,
  }) async {
    final dateStr = _dateParam(date);
    final qp = {
      'lat': point.latitude.toString(),
      'lon': point.longitude.toString(),
      if (dateStr != null) 'date': dateStr,
    };
    final uri = Uri.parse('$_base/conditions/point')
        .replace(queryParameters: qp);
    final body = await _getJson(uri);
    return PointConditions.fromJson(body as Map<String, dynamic>);
  }

  // ── /debug/bera ─────────────────────────────────────────────────────────

  /// Infos BERA brutes pour un point (massif, niveaux d'enneigement, risque).
  /// Retourne null si le backend n'a pas trouvé de massif pour ce point.
  Future<BeraInfo?> getBeraInfo(LatLng point) async {
    final uri = Uri.parse('$_base/debug/bera').replace(queryParameters: {
      'lat': point.latitude.toString(),
      'lon': point.longitude.toString(),
    });
    try {
      final body = await _getJson(uri) as Map<String, dynamic>;
      // L'endpoint renvoie {"error": "..."} si le corrector n'est pas
      // initialisé côté backend. On traduit en null.
      if (body['error'] != null) return null;
      if (body['massif_name'] == null && body['massif_id'] == null) return null;
      return BeraInfo.fromJson(body);
    } on ConditionsApiException catch (e) {
      // 404 = pas de massif pour ce point → null plutôt que jeter
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  // ── /best-window ────────────────────────────────────────────────────────

  /// Récupère le créneau optimal poudreuse/moquette pour chaque point de la
  /// bbox. [date] optionnel au format YYYY-MM-DD (défaut : demain côté backend).
  /// [resolutionM] : résolution de la grille en mètres (500 par défaut, plage
  /// 100-2000).
  Future<BestWindowResponse> fetchBestWindow(
    LatLng sw,
    LatLng ne, {
    DateTime? date,
    double resolutionM = 500,
  }) async {
    final params = <String, String>{
      'bbox':         _bboxParam(sw, ne),
      'resolution_m': resolutionM.toString(),
    };
    if (date != null) {
      params['date'] =
          '${date.year}-${date.month.toString().padLeft(2, "0")}-${date.day.toString().padLeft(2, "0")}';
    }
    final uri = Uri.parse('$_base/best-window').replace(queryParameters: params);
    final body = await _getJson(uri) as Map<String, dynamic>;
    return BestWindowResponse.fromJson(body);
  }

  // ── /avalanche ──────────────────────────────────────────────────────────

  /// Récupère les zones de départ + cônes d'avalanche pour la bbox.
  /// [riskOverride] permet de forcer un niveau 1-5 différent du BERA réel
  /// (utile pour "voir ce qui se passe si on monte le risque").
  Future<AvalancheResponse> fetchAvalanche(
    LatLng sw,
    LatLng ne, {
    int? riskOverride,
    int maxZones = 300,
  }) async {
    final params = <String, String>{
      'bbox':      _bboxParam(sw, ne),
      'max_zones': maxZones.toString(),
    };
    if (riskOverride != null) {
      params['risque_override'] = riskOverride.toString();
    }
    final uri = Uri.parse('$_base/avalanche').replace(queryParameters: params);
    final body = await _getJson(uri) as Map<String, dynamic>;
    return AvalancheResponse.fromJson(body);
  }

  // ── Internes ────────────────────────────────────────────────────────────

  static String _bboxParam(LatLng sw, LatLng ne) =>
      '${sw.latitude},${sw.longitude},${ne.latitude},${ne.longitude}';

  static String? _dateParam(DateTime? d) {
    if (d == null) return null;
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  Future<dynamic> _getJson(Uri uri) async {
    debugPrint('[conditions] GET $uri');
    try {
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      }
      throw ConditionsApiException(
        'HTTP ${response.statusCode}: ${response.body}',
        statusCode: response.statusCode,
      );
    } on ConditionsApiException {
      rethrow;
    } catch (e) {
      throw ConditionsApiException('Erreur réseau : $e');
    }
  }
}
