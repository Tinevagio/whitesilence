// lib/modules/snow/services/supabase_service.dart
//
// Partage anonyme des observations enrichies.
// Migré depuis Hey Snowy. Différences :
//   - URL et clé anon lues depuis WSSecrets
//   - Initialisation déplacée dans main.dart (avant runApp)
//   - Si pas de clés → toutes les méthodes sont des no-ops silencieux

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/secrets.dart';
import '../models/observation.dart';

class SupabaseService {
  /// À appeler dans main() avant runApp(). Initialise Supabase si les clés
  /// sont présentes, sinon log et continue (l'app ne plante pas).
  static Future<void> initialize() async {
    if (!WSSecrets.hasSupabase) {
      debugPrint('[supabase] SUPABASE_URL ou SUPABASE_ANON_KEY absent — partage désactivé');
      return;
    }
    try {
      await Supabase.initialize(
        url:     WSSecrets.supabaseUrl,
        anonKey: WSSecrets.supabaseAnonKey,
      );
      debugPrint('[supabase] initialisé');
    } catch (e) {
      debugPrint('[supabase] init failed: $e');
    }
  }

  bool get _isReady {
    if (!WSSecrets.hasSupabase) return false;
    try {
      Supabase.instance.client;
      return true;
    } catch (_) {
      return false;
    }
  }

  SupabaseClient? get _client {
    if (!_isReady) return null;
    return Supabase.instance.client;
  }

  /// Upload une obs anonyme. Retourne true si OK.
  Future<bool> uploadObservation(Observation obs) async {
    final client = _client;
    if (client == null) return false;
    try {
      await client.from('observations').upsert({
        'id':              obs.id,
        'lat':             obs.lat,
        'lon':             obs.lon,
        'altitude_m':      obs.altitudeM,
        'timestamp':       obs.timestamp.toIso8601String(),
        'snow_type':       obs.snowType,
        'depth_cm':        obs.depthCm,
        'stability_score': obs.stabilityScore,
        'aspect':          obs.aspect,
        'raw_notes':       obs.rawNotes,
      });
      return true;
    } catch (e) {
      debugPrint('[supabase] upload error: $e');
      return false;
    }
  }

  Future<void> deleteObservation(String id) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.from('observations').delete().eq('id', id);
    } catch (e) {
      debugPrint('[supabase] delete error: $e');
    }
  }

  /// Récupère les obs communautaires des dernières [hoursBack] heures.
  Future<List<Observation>> fetchCommunityObs({int hoursBack = 48}) async {
    final client = _client;
    if (client == null) return [];
    try {
      final since = DateTime.now()
          .subtract(Duration(hours: hoursBack))
          .toIso8601String();

      final data = await client
          .from('observations')
          .select()
          .gte('timestamp', since)
          .order('timestamp', ascending: false);

      return (data as List).map((row) => Observation(
            id:         row['id'],
            lat:        (row['lat'] as num).toDouble(),
            lon:        (row['lon'] as num).toDouble(),
            altitudeM:  (row['altitude_m'] as num?)?.toDouble(),
            timestamp:  DateTime.parse(row['timestamp']),
            audioPath:  '',
            snowType:   row['snow_type'],
            depthCm:    row['depth_cm'],
            stabilityScore: row['stability_score'],
            aspect:     row['aspect'],
            rawNotes:   row['raw_notes'],
            uploaded:   true,
          )).toList();
    } catch (e) {
      debugPrint('[supabase] fetch error: $e');
      return [];
    }
  }
}
