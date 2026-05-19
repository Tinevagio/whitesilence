// lib/core/secrets.dart
//
// Accès typé et tolérant aux clés API.
// Charge le .env au démarrage de l'app (cf. main.dart).
//
// Convention : si une clé est absente ou vide, le getter renvoie une chaîne
// vide. Les services qui en dépendent doivent gérer ça proprement (afficher
// un message explicite, désactiver la fonctionnalité), pas planter.

import 'package:flutter_dotenv/flutter_dotenv.dart';

class WSSecrets {
  WSSecrets._();

  static String _get(String key) {
    try {
      return dotenv.env[key]?.trim() ?? '';
    } catch (_) {
      // dotenv n'a pas été chargé (mode test, ou .env absent)
      return '';
    }
  }

  // ── Groq ───────────────────────────────────────────────────────────────
  static String get groqApiKey => _get('GROQ_API_KEY');
  static bool   get hasGroq    => groqApiKey.isNotEmpty;

  // ── Supabase ───────────────────────────────────────────────────────────
  static String get supabaseUrl     => _get('SUPABASE_URL');
  static String get supabaseAnonKey => _get('SUPABASE_ANON_KEY');
  static bool   get hasSupabase     =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  // ── Backend Névé (conditions + BERA) ───────────────────────────────────
  /// URL du backend Névé. Par défaut, l'instance Render publique.
  /// Réservé pour d'éventuels appels Flutter natifs aux endpoints API.
  static String get neveApiUrl {
    final fromEnv = _get('NEVE_API_URL');
    return fromEnv.isNotEmpty
        ? fromEnv.replaceFirst(RegExp(r'/$'), '')
        : 'https://snow-conditions.onrender.com';
  }

  /// URL du frontend Névé (UI HTML hébergée sur Netlify).
  /// C'est cette URL qu'on charge dans la WebView du module Conditions.
  static String get neveFrontendUrl {
    final fromEnv = _get('NEVE_FRONTEND_URL');
    return fromEnv.isNotEmpty
        ? fromEnv.replaceFirst(RegExp(r'/$'), '')
        : 'https://snow-conditions.netlify.app';
  }

  // ── Ski Touring API (module Idées natif) ───────────────────────────────
  /// URL de l'API FastAPI de recommandation d'itinéraires.
  /// Source backend : https://github.com/Tinevagio/ski-touring-api
  /// Le module Idées en Flutter consomme cette API (remplace l'ancienne
  /// WebView vers Streamlit).
  static String get ideasApiUrl {
    final fromEnv = _get('IDEAS_API_URL');
    return fromEnv.isNotEmpty
        ? fromEnv.replaceFirst(RegExp(r'/$'), '')
        : 'https://ski-touring-api.onrender.com';
  }
}
