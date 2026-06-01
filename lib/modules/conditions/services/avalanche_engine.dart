// lib/modules/conditions/services/avalanche_engine.dart
//
// Port Dart du modèle Python core/avalanche_model.py.
//
// Calcule les zones de départ et cônes d'avalanche entièrement en local,
// à partir des tuiles HGT déjà téléchargées pour le module Temps.
//
// Avantages vs appel backend Render :
//   - Aucun cold-start (Render free tier = jusqu'à 2min de latence)
//   - Fonctionne hors réseau (refuge, départ tôt le matin)
//   - Seul appel réseau restant : BERA quotidien (~10KB, cacheable)
//
// ── Pipeline ────────────────────────────────────────────────────────────────
//
//   1. Échantillonner une grille de points sur la bbox dessinée
//   2. Pour chaque point, interpoler altitude depuis HGT (déjà en cache)
//   3. Calculer pente (slope) et exposition (aspect) par différences finies
//      sur la grille HGT — même formule que build_slope_grids.py côté backend
//   4. Filtrer les zones de départ selon BERA (altitude, pente, exposition)
//      avec la même logique riskOverride qu'avalanche_model.py
//   5. Propager les cônes (port direct de propagate_cone())
//   6. Retourner AvalancheResponse — identique à la réponse backend
//
// ── Résolution de la grille ─────────────────────────────────────────────────
//
// On échantillonne à ~200m de résolution (configurable). C'est suffisant
// pour identifier les zones de départ (pentes > 25-35°) sans surcharger
// le thread UI. Le calcul tourne dans un Isolate via compute().
//
// ── Convention aspect ────────────────────────────────────────────────────────
//
// On utilise la convention standard atan2(dzDx, dzDy) — sans le signe moins.
// L'aspect pointe vers l'amont (upslope). downslope = aspect + 180° pointe
// vers l'aval, ce qui est la direction de propagation correcte pour les cônes.
//
// Le backend utilise atan2(dz_dx, -dz_dy) (convention .npz) qui inverse
// Est/Ouest. Cette convention n'est PAS reproduite ici — elle était un
// artefact du précalcul backend, pas une convention géographique standard.

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/elevation/hgt_provider.dart';
import '../models/avalanche_zone.dart';
import '../models/bera_full.dart';

// ── Paramètres BERA (identiques à avalanche_model.py) ───────────────────────

const _beraParams = {
  1: _BERAParams(slopeMin: 35, coneLengthM: 120,  coneAngleDeg: 18),
  2: _BERAParams(slopeMin: 32, coneLengthM: 220,  coneAngleDeg: 22),
  3: _BERAParams(slopeMin: 29, coneLengthM: 400,  coneAngleDeg: 28),
  4: _BERAParams(slopeMin: 25, coneLengthM: 650,  coneAngleDeg: 34),
  5: _BERAParams(slopeMin: 20, coneLengthM: 900,  coneAngleDeg: 42),
};

class _BERAParams {
  final double slopeMin;
  final double coneLengthM;
  final double coneAngleDeg;
  const _BERAParams({
    required this.slopeMin,
    required this.coneLengthM,
    required this.coneAngleDeg,
  });
}

// ── Données de calcul (sérialisable pour Isolate) ────────────────────────────

class _ComputeArgs {
  final List<_GridPoint> grid;
  final _BeraSimple bera;
  final int? riskOverride;
  final int maxZones;
  const _ComputeArgs({
    required this.grid,
    required this.bera,
    required this.riskOverride,
    required this.maxZones,
  });
}

/// Version sérialisable de BeraFull pour passage en Isolate.
class _BeraSimple {
  final int risqueBas;
  final int? risqueHaut;
  final double? risqueAltitudeM;
  final double? limiteNordM;
  final double? limiteSudM;
  final Map<String, bool> pentesDangereuses;

  const _BeraSimple({
    required this.risqueBas,
    required this.risqueHaut,
    required this.risqueAltitudeM,
    required this.limiteNordM,
    required this.limiteSudM,
    required this.pentesDangereuses,
  });

  factory _BeraSimple.fromFull(BeraFull full) {
    final Map<String, bool> pd = {
      'N':  full.pentesDangereuses.n,
      'NE': full.pentesDangereuses.ne,
      'E':  full.pentesDangereuses.e,
      'SE': full.pentesDangereuses.se,
      'S':  full.pentesDangereuses.s,
      'SW': full.pentesDangereuses.sw,
      'W':  full.pentesDangereuses.w,
      'NW': full.pentesDangereuses.nw,
    };
    return _BeraSimple(
      risqueBas:       full.risqueBas  ?? 1,
      risqueHaut:      full.risqueHaut,
      risqueAltitudeM: full.risqueAltitudeM?.toDouble(),
      limiteNordM:     full.limiteNordM?.toDouble(),
      limiteSudM:      full.limiteSudM != null && full.limiteSudM! > 0
                         ? full.limiteSudM!.toDouble()
                         : null,
      pentesDangereuses: pd,
    );
  }
}

/// Un point de la grille d'échantillonnage avec élévation + slope + aspect
/// déjà calculés (résultat du prefetch HGT).
class _GridPoint {
  final double lat;
  final double lon;
  final double elevM;
  final double slopeDeg;
  final double aspectDeg; // convention atan2(dz_dx, -dz_dy) — cf. backend
  const _GridPoint({
    required this.lat,
    required this.lon,
    required this.elevM,
    required this.slopeDeg,
    required this.aspectDeg,
  });
}

// ── Helper interne ───────────────────────────────────────────────────────────

/// Paire (zone de départ, aspect brut en degrés) pour passage à _propagateCone
/// sans aller-retour destructeur deg→code→deg.
class _AspectedZone {
  final AvalancheStartZone zone;
  final double aspectDeg; // valeur brute depuis la grille HGT, convention backend
  const _AspectedZone(this.zone, this.aspectDeg);
}

// ── Engine public ─────────────────────────────────────────────────────────────

class AvalancheEngine {
  AvalancheEngine._();

  /// Résolution d'échantillonnage par défaut en mètres.
  /// 200m = bon compromis perf/précision pour identifier les zones de départ.
  /// Peut être réduit à 100m pour plus de détail (×4 points, ×4 temps).
  static const double defaultResolutionM = 200;

  /// Calcule les zones d'avalanche pour une bbox et un BERA donnés.
  ///
  /// [sw] et [ne] : coins de la zone dessinée par l'utilisateur.
  /// [bera] : bulletin BERA complet du massif (déjà en cache local).
  /// [riskOverride] : null = risque réel, 1-5 = simulation aggravée/réduite.
  ///                  Si > risque réel → filtre exposition désactivé (tous
  ///                  versants éligibles). Même logique qu'avalanche_model.py.
  /// [resolutionM] : pas de grille en mètres.
  /// [maxZones] : nombre max de zones de départ (protection perf).
  ///
  /// Retourne null si les tuiles HGT ne sont pas disponibles pour cette zone.
  static Future<AvalancheResponse?> computeZones({
    required LatLng sw,
    required LatLng ne,
    required BeraFull bera,
    int? riskOverride,
    double resolutionM = defaultResolutionM,
    int maxZones = 300,
  }) async {
    // 1. Vérifier disponibilité HGT
    final hgtAvailable = await _checkHgtCoverage(sw, ne);
    if (!hgtAvailable) {
      debugPrint('[avalanche] HGT non disponible pour cette zone → fallback backend');
      return null;
    }

    // 2. Construire la grille d'échantillonnage et calculer slope/aspect
    //    Opération I/O (lecture HGT) → thread principal avec compute()
    final grid = await _buildGrid(sw, ne, resolutionM);
    if (grid.isEmpty) {
      debugPrint('[avalanche] grille vide — bbox trop petite ?');
      return AvalancheResponse(
        massifName: bera.massif,
        risqueBas:  bera.risqueBas ?? 1,
        risqueHaut: bera.risqueHaut,
        startZones: const [],
        cones:      const [],
      );
    }

    debugPrint('[avalanche] grille : ${grid.length} points à ${resolutionM.round()}m');

    // 3. Filtrage + propagation dans un Isolate pour ne pas bloquer l'UI
    final args = _ComputeArgs(
      grid:         grid,
      bera:         _BeraSimple.fromFull(bera),
      riskOverride: riskOverride,
      maxZones:     maxZones,
    );

    final result = await compute<_ComputeArgs, AvalancheResponse>(_runInIsolate, args);

    debugPrint('[avalanche] ${result.startZones.length} zones départ, '
        '${result.cones.length} cônes');

    return AvalancheResponse(
      massifName: bera.massif,
      risqueBas:  bera.risqueBas  ?? 1,
      risqueHaut: bera.risqueHaut,
      startZones: result.startZones,
      cones:      result.cones,
    );
  }

  // ── Vérification HGT ───────────────────────────────────────────────────────

  static Future<bool> _checkHgtCoverage(LatLng sw, LatLng ne) async {
    // On vérifie les 4 coins + le centre
    final points = [
      sw,
      ne,
      LatLng(sw.latitude, ne.longitude),
      LatLng(ne.latitude, sw.longitude),
      LatLng((sw.latitude + ne.latitude) / 2, (sw.longitude + ne.longitude) / 2),
    ];
    for (final p in points) {
      if (!await HgtElevationProvider.isAvailable(p.latitude, p.longitude)) {
        return false;
      }
    }
    return true;
  }

  // ── Construction de la grille ──────────────────────────────────────────────

  static Future<List<_GridPoint>> _buildGrid(
    LatLng sw,
    LatLng ne,
    double resolutionM,
  ) async {
    // Pas en degrés correspondant à resolutionM
    final stepLat = resolutionM / 111000;
    final midLat  = (sw.latitude + ne.latitude) / 2;
    final stepLon = resolutionM / (111000 * math.cos(midLat * math.pi / 180));

    final hgt = HgtElevationProvider();
    final grid = <_GridPoint>[];

    // On a besoin d'un voisinage de 1 step pour calculer le gradient →
    // on démarre 1 step à l'intérieur de la bbox
    var lat = sw.latitude + stepLat;
    while (lat < ne.latitude - stepLat) {
      var lon = sw.longitude + stepLon;
      while (lon < ne.longitude - stepLon) {
        // 5 points pour le gradient central (centre + 4 voisins)
        final e  = await hgt.getElevation(lat, lon);
        final eN = await hgt.getElevation(lat + stepLat, lon);
        final eS = await hgt.getElevation(lat - stepLat, lon);
        final eE = await hgt.getElevation(lat, lon + stepLon);
        final eW = await hgt.getElevation(lat, lon - stepLon);

        // Gradient en m/m (on convertit les pas en mètres)
        final dzDy = (eN - eS) / (2 * stepLat * 111000); // Nord-Sud
        final dzDx = (eE - eW) / (2 * stepLon * 111000 *
                     math.cos(lat * math.pi / 180)); // Est-Ouest

        // Pente en degrés
        final grad    = math.sqrt(dzDx * dzDx + dzDy * dzDy);
        final slopeDeg = math.atan(grad) * 180 / math.pi;

        // Aspect convention atan2(dz_dx, -dz_dy) — MÊME convention que le
        // backend Python. Donne des aspects inversés Est/Ouest (documenté),
        // mais cohérent avec les cônes qui compensent via +180°.
        // Convention standard : atan2(dzDx, dzDy), sans le signe moins.
        // aspect pointe vers l'amont → downslope = aspect + 180° pointe vers l'aval.
        final aspectRad = math.atan2(dzDx, dzDy);
        final aspectDeg = (aspectRad * 180 / math.pi + 360) % 360;

        grid.add(_GridPoint(
          lat:       lat,
          lon:       lon,
          elevM:     e,
          slopeDeg:  slopeDeg,
          aspectDeg: aspectDeg,
        ));

        lon += stepLon;
      }
      lat += stepLat;
    }

    return grid;
  }

  // ── Calcul dans l'Isolate ─────────────────────────────────────────────────

  static AvalancheResponse _runInIsolate(_ComputeArgs args) {
    final aspected = _findStartZonesAspected(
      args.grid,
      args.bera,
      args.riskOverride,
      args.maxZones,
    );
    final zones = aspected.map((a) => a.zone).toList();
    final cones = aspected.map((a) => _propagateCone(a)).toList();
    return AvalancheResponse(
      massifName: null,
      risqueBas:  args.bera.risqueBas,
      risqueHaut: args.bera.risqueHaut,
      startZones: zones,
      cones:      cones,
    );
  }

  // ── Filtrage zones de départ ───────────────────────────────────────────────

  static List<_AspectedZone> _findStartZonesAspected(
    List<_GridPoint> grid,
    _BeraSimple bera,
    int? riskOverride,
    int maxZones,
  ) {
    // Risque réel maximal du massif
    final realMax = math.max(
      bera.risqueBas,
      bera.risqueHaut ?? 0,
    );

    // Désactiver le filtre exposition si override aggravé — même logique
    // qu'avalanche_model.py find_start_zones()
    final ignoreAspectFilter = riskOverride != null && riskOverride > realMax;

    final zones = <_AspectedZone>[];

    for (final pt in grid) {
      // Niveau de risque applicable
      final int risque;
      if (riskOverride != null) {
        risque = riskOverride;
      } else if (bera.risqueHaut != null &&
                 bera.risqueAltitudeM != null &&
                 pt.elevM >= bera.risqueAltitudeM!) {
        risque = bera.risqueHaut!;
      } else {
        risque = bera.risqueBas;
      }

      final params = _beraParams[risque];
      if (params == null) continue;

      // Filtre altitude minimum d'enneigement
      final isNorth = pt.aspectDeg <= 90 || pt.aspectDeg >= 270;
      final limite  = (isNorth ? bera.limiteNordM : bera.limiteSudM) ?? 1000;
      if (pt.elevM < limite) continue;

      // Filtre pente
      if (pt.slopeDeg < params.slopeMin) continue;

      // Filtre exposition — désactivé si override aggravé
      if (!ignoreAspectFilter) {
        if (!_isAspectDangerous(pt.aspectDeg, bera.pentesDangereuses)) continue;
      }

      zones.add(_AspectedZone(
        AvalancheStartZone(
          point:    LatLng(pt.lat, pt.lon),
          slope:    pt.slopeDeg,
          altitude: pt.elevM,
          aspect:   _aspectDegToCode(pt.aspectDeg),
          severity: _severityForRisk(risque),
          risque:   risque,
        ),
        pt.aspectDeg, // aspect brut — évite le round-trip deg→code→deg
      ));
    }

    // Sous-échantillonnage si trop de zones
    if (zones.length > maxZones) {
      final step = zones.length ~/ maxZones;
      return [for (int i = 0; i < zones.length; i += step) zones[i]]
          .take(maxZones)
          .toList();
    }

    return zones;
  }

  // ── Propagation des cônes ─────────────────────────────────────────────────

  static AvalancheCone _propagateCone(_AspectedZone aspected) {
    final zone       = aspected.zone;
    final params     = _beraParams[zone.risque]!;
    final halfAngle  = params.coneAngleDeg / 2;
    final lat        = zone.point.latitude;
    final lon        = zone.point.longitude;

    // Aspect brut depuis la grille HGT — pas de round-trip deg→code→deg.
    // Convention atan2(dzDx, dzDy) : aspect pointe vers l'amont.
    // downslope = aspect + 180° pointe vers l'aval — direction des cônes.
    final aspectDeg  = aspected.aspectDeg;
    final downslope  = (aspectDeg + 180) % 360;

    // Arc du cône : N points entre bord gauche et bord droit
    final nArc = math.max(5, (params.coneAngleDeg / 5).round());
    final arcPoints = <LatLng>[];
    for (int k = 0; k <= nArc; k++) {
      final t       = k / nArc;
      final bearing = (downslope - halfAngle + t * params.coneAngleDeg) % 360;
      arcPoints.add(_destinationPoint(lat, lon, bearing, params.coneLengthM));
    }

    // Polygone : apex → arc → apex (fermé)
    final ring = <LatLng>[
      LatLng(lat, lon),
      ...arcPoints,
      LatLng(lat, lon),
    ];

    return AvalancheCone(
      ring:      ring,
      startLat:  lat,
      startLon:  lon,
      severity:  _severityForRisk(zone.risque),
      risque:    zone.risque,
    );
  }

  // ── Helpers géographiques ─────────────────────────────────────────────────

  static LatLng _destinationPoint(
    double lat, double lon, double bearingDeg, double distanceM,
  ) {
    final bearing = bearingDeg * math.pi / 180;
    final dlat    = (distanceM / 111000) * math.cos(bearing);
    final dlon    = (distanceM / (111000 * math.cos(lat * math.pi / 180)))
                  * math.sin(bearing);
    return LatLng(lat + dlat, lon + dlon);
  }

  static bool _isAspectDangerous(
    double aspectDeg,
    Map<String, bool> pentesDangereuses,
  ) {
    const aspectDegrees = {
      'N': 0.0, 'NE': 45.0, 'E': 90.0, 'SE': 135.0,
      'S': 180.0, 'SW': 225.0, 'W': 270.0, 'NW': 315.0,
    };
    const toleranceDeg = 25.0;

    for (final entry in pentesDangereuses.entries) {
      if (!entry.value) continue;
      final center = aspectDegrees[entry.key] ?? 0;
      final diff   = ((aspectDeg - center + 180) % 360 - 180).abs();
      if (diff <= toleranceDeg) return true;
    }
    return false;
  }

  static String _aspectDegToCode(double deg) {
    const codes = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final idx   = ((deg + 22.5) / 45).floor() % 8;
    return codes[idx];
  }

  static double _aspectCodeToDeg(String code) {
    const map = {
      'N': 0.0, 'NE': 45.0, 'E': 90.0, 'SE': 135.0,
      'S': 180.0, 'SW': 225.0, 'W': 270.0, 'NW': 315.0,
    };
    return map[code] ?? 0.0;
  }

  static double _severityForRisk(int risque) {
    return switch (risque) {
      1 => 0.2,
      2 => 0.35,
      3 => 0.55,
      4 => 0.75,
      5 => 0.95,
      _ => 0.5,
    };
  }
}
