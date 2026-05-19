// lib/modules/ideas/services/ideas_api.dart
//
// Client HTTP vers le backend ski-touring-api (FastAPI sur Render).
// Endpoints : /health, /metadata, /ideas.
//
// Pattern cold-start identique à conditions_api : Render free tier dort
// après 15 min d'inactivité, donc on prévoit un timeout généreux et un
// endpoint /health pour réveiller le service en arrière-plan.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/secrets.dart';
import '../models/idea.dart';
import '../models/ideas_filter.dart';
import '../models/ideas_response.dart';

class IdeasApiException implements Exception {
  final String message;
  final int? statusCode;
  const IdeasApiException(this.message, {this.statusCode});
  @override String toString() => 'IdeasApiException($statusCode): $message';
}

class IdeasApi {
  final String _base;

  IdeasApi({String? baseUrl}) : _base = baseUrl ?? WSSecrets.ideasApiUrl;

  /// Ping le backend pour le sortir d'hibernation (Render free tier).
  /// Ne lève pas d'exception si ça rate — c'est best-effort.
  Future<bool> wakeUp() async {
    try {
      final r = await http.get(Uri.parse('$_base/health'))
          .timeout(const Duration(seconds: 90));
      return r.statusCode == 200;
    } catch (e) {
      debugPrint('[ideas] wakeUp failed: $e');
      return false;
    }
  }

  /// Charge les métadonnées : massifs dispo, dates dispo, etc.
  Future<IdeasMetadata> getMetadata() async {
    final uri = Uri.parse('$_base/metadata');
    final body = await _getJson(uri) as Map<String, dynamic>;
    return IdeasMetadata.fromJson(body);
  }

  /// Recherche les meilleurs itinéraires selon les filtres.
  /// Timeout étendu à 180s car le scoring de tous les itinéraires sur
  /// Render free tier peut prendre 1-2 min la première fois (avant que
  /// le cache spatial du backend ne soit chaud).
  Future<IdeasResponse> getIdeas(IdeasFilter filter) async {
    final params = <String, String>{
      'date':       _formatDate(filter.date),
      'niveau':     filter.niveau,
      'dplus_min':  filter.dplusMin.toString(),
      'dplus_max':  filter.dplusMax.toString(),
      'expositions': filter.expositions.join(','),
      'n_results':  filter.nResults.toString(),
      'include_ai': filter.includeAi.toString(),
    };
    if (filter.massifs.isNotEmpty) {
      params['massifs'] = filter.massifs.join(',');
    }
    final uri = Uri.parse('$_base/ideas').replace(queryParameters: params);
    final body = await _getJson(uri,
      timeout: const Duration(seconds: 180),
    ) as Map<String, dynamic>;
    return IdeasResponse.fromJson(body);
  }

  // ── Internes ────────────────────────────────────────────────────────────

  static String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';

  Future<dynamic> _getJson(Uri uri, {Duration? timeout}) async {
    if (_base.isEmpty) {
      throw const IdeasApiException(
          'URL backend non configurée (IDEAS_API_URL manquant)');
    }
    debugPrint('[ideas] GET $uri');
    try {
      final r = await http.get(uri)
          .timeout(timeout ?? const Duration(seconds: 120));
      if (r.statusCode == 200) {
        return jsonDecode(utf8.decode(r.bodyBytes));
      }
      // 503 attendu si météo trop ancienne (cf. backend)
      String detail = r.body;
      try {
        final j = jsonDecode(r.body);
        if (j is Map && j['detail'] != null) detail = j['detail'].toString();
      } catch (_) {}
      throw IdeasApiException(detail, statusCode: r.statusCode);
    } on TimeoutException {
      throw const IdeasApiException(
          'Le serveur met trop de temps à répondre. Réveil en cours ?');
    } on IdeasApiException {
      rethrow;
    } catch (e) {
      throw IdeasApiException('Erreur réseau : $e');
    }
  }
}
