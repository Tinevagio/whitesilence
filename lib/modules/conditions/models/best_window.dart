// lib/modules/conditions/models/best_window.dart
//
// Modèle pour le créneau optimal moquette/poudreuse.
//
// L'endpoint /best-window retourne, pour chaque point d'une grille, deux
// indicateurs horaires :
//   - powderUntilHour   : dernière heure de la journée où la poudreuse est
//                         encore exploitable (typiquement matin, jusqu'à
//                         ce que le soleil chauffe)
//   - springOptimalHour : heure idéale pour la moquette / neige de printemps
//                         transformée (typiquement milieu de journée, juste
//                         après le ramollissement contrôlé)
//
// Si null, c'est qu'aucun créneau pertinent n'existe ce jour pour ce point.

import 'package:latlong2/latlong.dart';
import 'aspect_helper.dart';

/// Réponse complète de /best-window.
class BestWindowResponse {
  /// Date pour laquelle le calcul a été fait (par défaut : demain).
  final String date;
  /// Bbox demandée [lat_min, lon_min, lat_max, lon_max].
  final List<double> bbox;
  /// Points de la grille avec leurs créneaux.
  final List<BestWindowPoint> points;

  const BestWindowResponse({
    required this.date,
    required this.bbox,
    required this.points,
  });

  factory BestWindowResponse.fromJson(Map<String, dynamic> json) {
    return BestWindowResponse(
      date: (json['date'] as String?) ?? '',
      bbox: ((json['bbox'] as List?) ?? [])
          .map((x) => (x as num).toDouble()).toList(),
      points: ((json['points'] as List?) ?? const [])
          .map((p) => BestWindowPoint.fromJson(p as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Point de la grille avec son créneau optimal.
class BestWindowPoint {
  final LatLng point;
  final double elevationM;
  final double aspectDeg;
  final String aspectLabel;     // "N", "NE", "E", etc.
  final double slopeDeg;

  /// Heure (0-23) jusqu'à laquelle la poudreuse reste bonne. Null si pas
  /// de poudreuse exploitable ce jour.
  final int? powderUntilHour;

  /// Heure (0-23) idéale pour la moquette / neige transformée. Null si
  /// pas de moquette ce jour.
  final int? springOptimalHour;

  const BestWindowPoint({
    required this.point,
    required this.elevationM,
    required this.aspectDeg,
    required this.aspectLabel,
    required this.slopeDeg,
    required this.powderUntilHour,
    required this.springOptimalHour,
  });

  factory BestWindowPoint.fromJson(Map<String, dynamic> j) {
    final aspDeg = (j['aspect_deg'] as num).toDouble();
    return BestWindowPoint(
      point: LatLng(
        (j['lat'] as num).toDouble(),
        (j['lon'] as num).toDouble(),
      ),
      elevationM:  (j['elevation_m'] as num).toDouble(),
      aspectDeg:   aspDeg,
      // Idem PointConditions : on remplace par le label corrigé (cf.
      // aspect_helper.dart pour les détails de la correction Est/Ouest).
      aspectLabel: labelForAspectDeg(aspDeg),
      slopeDeg:    (j['slope_deg']   as num).toDouble(),
      powderUntilHour:   (j['powder_until_hour']   as num?)?.toInt(),
      springOptimalHour: (j['spring_optimal_hour'] as num?)?.toInt(),
    );
  }

  /// True si ce point a au moins un créneau exploitable (poudre OU moquette).
  bool get hasAnyWindow =>
      powderUntilHour != null || springOptimalHour != null;
}
