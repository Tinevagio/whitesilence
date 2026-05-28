// lib/modules/conditions/models/point_conditions.dart
//
// Réponses des endpoints /conditions et /conditions/point.

import 'package:latlong2/latlong.dart';
import 'aspect_helper.dart';
import 'bera_info.dart';

class HourlyCondition {
  final int    hour;          // UTC, 0-23
  final String condition;     // code SnowConditionCode
  final String label;         // libellé serveur (on remappe côté client)
  final String color;         // couleur serveur "#XXXXXX" (fallback si code inconnu)
  final double tempSurface;   // °C
  final double windSpeed;     // km/h

  const HourlyCondition({
    required this.hour,
    required this.condition,
    required this.label,
    required this.color,
    required this.tempSurface,
    required this.windSpeed,
  });

  factory HourlyCondition.fromJson(Map<String, dynamic> j) => HourlyCondition(
        hour:        (j['hour'] as num).toInt(),
        condition:   j['condition'] as String,
        label:       j['label'] as String,
        color:       j['color'] as String,
        tempSurface: (j['temp_surface'] as num).toDouble(),
        windSpeed:   (j['wind_speed'] as num).toDouble(),
      );
}

class PointConditions {
  /// Seuil en cm sous lequel on considère que le point est "sans neige".
  /// Aligné avec le frontend Netlify d'origine.
  static const double noSnowThresholdCm = 5.0;

  final double lat;
  final double lon;
  final double elevationM;
  final double aspectDeg;
  final String aspectLabel;   // "N", "NE", ... ou "Plat"
  final double slopeDeg;
  final BeraInfo? bera;
  final List<HourlyCondition> hours;

  const PointConditions({
    required this.lat,
    required this.lon,
    required this.elevationM,
    required this.aspectDeg,
    required this.aspectLabel,
    required this.slopeDeg,
    required this.bera,
    required this.hours,
  });

  LatLng get latLng => LatLng(lat, lon);

  factory PointConditions.fromJson(Map<String, dynamic> j) {
    final aspDeg = (j['aspect_deg'] as num).toDouble();
    return PointConditions(
      lat:         (j['lat'] as num).toDouble(),
      lon:         (j['lon'] as num).toDouble(),
      elevationM:  (j['elevation_m'] as num).toDouble(),
      aspectDeg:   aspDeg,
      // On REMPLACE le aspect_label du backend (qui a Est/Ouest inversés sur
      // les diagonales) par le label corrigé calculé depuis aspect_deg.
      // Cf. labelForAspectDeg pour les détails.
      aspectLabel: labelForAspectDeg(aspDeg),
      slopeDeg:    (j['slope_deg'] as num).toDouble(),
      bera:        j['bera'] == null
                     ? null
                     : BeraInfo.fromJson(j['bera'] as Map<String, dynamic>),
      hours: (j['hours'] as List)
          .map((e) => HourlyCondition.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Retourne la condition pour une heure UTC donnée. Si l'heure n'existe pas,
  /// retourne la plus proche disponible. Null si la liste est vide.
  HourlyCondition? conditionAt(int utcHour) {
    if (hours.isEmpty) return null;
    HourlyCondition best = hours.first;
    int bestDist = (best.hour - utcHour).abs();
    for (final h in hours) {
      final d = (h.hour - utcHour).abs();
      if (d < bestDist) {
        best = h;
        bestDist = d;
      }
    }
    return best;
  }

  // ── Épaisseur de neige estimée (interpolation BERA) ─────────────────────
  //
  // Le backend ne fournit pas directement une hauteur de neige pour ce point :
  // il fournit un BERA avec 3 paliers d'altitude (typ. 1500/2000/2500 m), et
  // c'est au client d'interpoler en fonction de l'altitude réelle du point
  // et de son exposition (Nord ou Sud).
  //
  // Reprise de la logique du frontend Netlify (cf. Front End V7.html).

  /// Épaisseur de neige estimée en cm pour ce point.
  /// Null si pas de BERA disponible ou pas de niveaux d'enneigement.
  double? get estimatedDepthCm =>
      bera?.estimatedDepthCm(elevationM, aspectDeg);

  /// Vrai si l'épaisseur estimée est ≤ noSnowThresholdCm (5 cm).
  /// Permet d'afficher "Pas de neige" au lieu d'une condition trompeuse.
  bool get isNoSnow {
    final d = estimatedDepthCm;
    return d != null && d <= noSnowThresholdCm;
  }
}

/// Réponse complète de /conditions (grille).
class ConditionsResponse {
  final String date;
  final List<double> bbox; // [lat_min, lon_min, lat_max, lon_max]
  final double resolutionM;
  final String generatedAt;
  final List<PointConditions> points;

  const ConditionsResponse({
    required this.date,
    required this.bbox,
    required this.resolutionM,
    required this.generatedAt,
    required this.points,
  });

  factory ConditionsResponse.fromJson(Map<String, dynamic> j) =>
      ConditionsResponse(
        date:        j['date'] as String,
        bbox:        (j['bbox'] as List).map((e) => (e as num).toDouble()).toList(),
        resolutionM: (j['resolution_m'] as num).toDouble(),
        generatedAt: j['generated_at'] as String,
        points: (j['points'] as List)
            .map((e) => PointConditions.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}