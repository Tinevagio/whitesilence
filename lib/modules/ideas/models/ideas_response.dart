// lib/modules/ideas/models/ideas_response.dart
//
// Modèles de réponse haut-niveau pour les endpoints /ideas et /metadata.

import 'idea.dart';

class IdeasResponse {
  final String date;
  final String saison;         // "hiver" / "transition" / "printemps"
  final String weatherIcon;
  final List<String> weatherAlerts;
  final List<Idea> ideas;
  final Map<String, dynamic> stats;

  const IdeasResponse({
    required this.date,
    required this.saison,
    required this.weatherIcon,
    required this.weatherAlerts,
    required this.ideas,
    required this.stats,
  });

  factory IdeasResponse.fromJson(Map<String, dynamic> j) => IdeasResponse(
        date:        j['date']         as String,
        saison:      j['saison']       as String,
        weatherIcon: (j['weather_icon'] as String?) ?? '⛅',
        weatherAlerts: ((j['weather_alerts'] as List?) ?? const [])
            .map((e) => e as String).toList(),
        ideas: ((j['ideas'] as List?) ?? const [])
            .map((e) => Idea.fromJson(e as Map<String, dynamic>))
            .toList(),
        stats: Map<String, dynamic>.from(j['stats'] as Map? ?? {}),
      );
}

class IdeasMetadata {
  final List<String> massifs;
  final List<String> datesAvailable;
  final String? meteoLatest;
  final String? beraLatest;
  final int nbItineraires;

  const IdeasMetadata({
    required this.massifs,
    required this.datesAvailable,
    this.meteoLatest,
    this.beraLatest,
    required this.nbItineraires,
  });

  factory IdeasMetadata.fromJson(Map<String, dynamic> j) => IdeasMetadata(
        massifs: ((j['massifs'] as List?) ?? const [])
            .map((e) => e as String).toList(),
        datesAvailable: ((j['dates_available'] as List?) ?? const [])
            .map((e) => e as String).toList(),
        meteoLatest:   j['meteo_latest'] as String?,
        beraLatest:    j['bera_latest']  as String?,
        nbItineraires: (j['nb_itineraires'] as num?)?.toInt() ?? 0,
      );
}
