// lib/modules/conditions/services/avalanche_engine.dart
//
// Calcul local des zones d'avalanche depuis les tuiles HGT.
//
// ── Pipeline ────────────────────────────────────────────────────────────────
//
//   1. Grille 200m sur la bbox → filtrage des zones de départ (pente, aspect,
//      altitude, exposition BERA). Même logique qu'avalanche_model.py.
//
//   2. Pour chaque zone de départ retenue → flood-fill terrain-aware à 50m.
//      Le flood-fill propage la coulée cellule par cellule en suivant le
//      relief : il suit les vallées, se bloque sur les crêtes, se canalise
//      dans les couloirs.
//
//   3. L'ensemble des cellules atteintes par le flood-fill est converti en
//      polygone (contour) via un marching-squares simplifié.
//
// ── Flood-fill : règles de propagation ──────────────────────────────────────
//
//   Une cellule voisine est ajoutée à la propagation si :
//     a) Elle est en aval (élévation inférieure à la cellule courante)
//        OU sur un replat (différence < 2m) dans la direction de descente.
//     b) La pente de remontée vers cette cellule est ≤ UPSLOPE_BLOCK_DEG (5°).
//        Au-delà → crête, la propagation s'arrête dans cette direction.
//     c) La distance à la zone de départ est ≤ longueur BERA.
//     d) La cellule n'a pas déjà été visitée.
//
// ── Contour (marching squares simplifié) ────────────────────────────────────
//
//   On construit le polygone de contour des cellules atteintes en traçant
//   les bords entre cellules "inondées" et cellules "non inondées".
//   Algorithme : Graham scan sur les points de bord.
//
// ── Performance ─────────────────────────────────────────────────────────────
//
//   - La grille 200m (filtrage) : ~1300 points pour une bbox 8×8km. Rapide.
//   - Le flood-fill 50m : ~500-2000 cellules par zone de départ selon
//     la longueur BERA. Calcul dans un Isolate via compute().
//   - Les données HGT sont déjà en Int16List dans le cache statique de
//     HgtElevationProvider — pas de lecture disque supplémentaire.

import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/elevation/hgt_provider.dart';
import '../models/avalanche_zone.dart';
import '../models/bera_full.dart';

// ── Paramètres BERA ───────────────────────────────────────────────────────────

const _beraParams = {
  1: _BERAParams(slopeMin: 35, coneLengthM: 120,  coneAngleDeg: 18),
  2: _BERAParams(slopeMin: 32, coneLengthM: 220,  coneAngleDeg: 22),
  3: _BERAParams(slopeMin: 29, coneLengthM: 400,  coneAngleDeg: 28),
  4: _BERAParams(slopeMin: 25, coneLengthM: 650,  coneAngleDeg: 34),
  5: _BERAParams(slopeMin: 20, coneLengthM: 900,  coneAngleDeg: 42),
};

/// Angle de remontée max avant blocage (crête). Au-delà → flood-fill stoppé.
const double _upslopeBlockDeg = 5.0;

/// Résolution de la grille de filtrage des zones de départ.
const double _filterResolutionM = 200.0;

/// Résolution du flood-fill (propagation terrain-aware).
const double _floodResolutionM = 50.0;

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

// ── Structures de données ────────────────────────────────────────────────────

class _GridPoint {
  final double lat;
  final double lon;
  final double elevM;
  final double slopeDeg;
  final double aspectDeg;
  const _GridPoint({
    required this.lat,
    required this.lon,
    required this.elevM,
    required this.slopeDeg,
    required this.aspectDeg,
  });
}

/// Grille d'altitude pour le flood-fill — sérialisable pour l'Isolate.
class _ElevGrid {
  final List<double> lats;   // latitudes des lignes
  final List<double> lons;   // longitudes des colonnes
  final List<double> elevs;  // élévations [row * nCols + col]
  final int nRows;
  final int nCols;
  const _ElevGrid({
    required this.lats,
    required this.lons,
    required this.elevs,
    required this.nRows,
    required this.nCols,
  });

  double elev(int row, int col) => elevs[row * nCols + col];
}

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

  factory _BeraSimple.fromFull(BeraFull full) => _BeraSimple(
    risqueBas:       full.risqueBas  ?? 1,
    risqueHaut:      full.risqueHaut,
    risqueAltitudeM: full.risqueAltitudeM?.toDouble(),
    limiteNordM:     full.limiteNordM?.toDouble(),
    limiteSudM:      (full.limiteSudM != null && full.limiteSudM! > 0)
                       ? full.limiteSudM!.toDouble()
                       : null,
    pentesDangereuses: {
      'N':  full.pentesDangereuses.n,  'NE': full.pentesDangereuses.ne,
      'E':  full.pentesDangereuses.e,  'SE': full.pentesDangereuses.se,
      'S':  full.pentesDangereuses.s,  'SW': full.pentesDangereuses.sw,
      'W':  full.pentesDangereuses.w,  'NW': full.pentesDangereuses.nw,
    },
  );
}

class _AspectedZone {
  final AvalancheStartZone zone;
  final double aspectDeg;
  final double effectiveLengthM; // longueur réelle tronquée sur remontée
  const _AspectedZone(this.zone, this.aspectDeg, this.effectiveLengthM);
}

class _ComputeArgs {
  final List<_AspectedZone> startZones;
  const _ComputeArgs({required this.startZones});
}

// ── Engine public ─────────────────────────────────────────────────────────────

class AvalancheEngine {
  AvalancheEngine._();

  static Future<AvalancheResponse?> computeZones({
    required LatLng sw,
    required LatLng ne,
    required BeraFull bera,
    int? riskOverride,
  }) async {
    // 1. Vérifier disponibilité HGT
    if (!await _checkHgtCoverage(sw, ne)) {
      debugPrint('[avalanche] HGT non disponible → fallback backend');
      return null;
    }

    final hgt = HgtElevationProvider();

    // 2. Grille 200m → zones de départ
    final filterGrid = await _buildGrid(sw, ne, _filterResolutionM, hgt);
    if (filterGrid.isEmpty) return AvalancheResponse(
      massifName: null,
      risqueBas:  bera.risqueBas  ?? 1,
      risqueHaut: bera.risqueHaut,
      startZones: const [],
      cones:      const [],
    );

    final bera2 = _BeraSimple.fromFull(bera);
    final midLat = (sw.latitude + ne.latitude) / 2;
    final dLat   = ne.latitude  - sw.latitude;
    final dLon   = ne.longitude - sw.longitude;
    final bboxKm2 = dLat * 111.0 * dLon * 111.0 *
                    math.cos(midLat * math.pi / 180);
    final maxZones = (bboxKm2 * 8).clamp(50, 500).round();

    debugPrint('[avalanche] bbox ${bboxKm2.toStringAsFixed(1)} km² '
        '→ maxZones=$maxZones');

    final aspected = _findStartZones(filterGrid, bera2, riskOverride, maxZones);
    if (aspected.isEmpty) return AvalancheResponse(
      massifName: null,
      risqueBas:  bera.risqueBas  ?? 1,
      risqueHaut: bera.risqueHaut,
      startZones: const [],
      cones:      const [],
    );

    debugPrint('[avalanche] ${aspected.length} zones de départ trouvées');

    // 3. Affiner la longueur effective de chaque cône selon le terrain.
    //    On échantillonne l'altitude le long du downslope et on tronque
    //    à la première remontée > _upslopeBlockDeg (5°).
    //    Fait ici (thread principal) car nécessite HGT — pas dans l'Isolate.
    final refined = <_AspectedZone>[];
    for (final a in aspected) {
      final params    = _beraParams[a.zone.risque];
      final downslope = (a.aspectDeg + 180) % 360;
      final effLen    = params == null
          ? a.effectiveLengthM
          : await _computeEffectiveLength(
              a.zone.point.latitude,
              a.zone.point.longitude,
              downslope,
              params.coneLengthM,
              hgt,
            );
      refined.add(_AspectedZone(a.zone, a.aspectDeg, effLen));
    }

    // 4. Calcul des cônes dans l'Isolate
    final args = _ComputeArgs(startZones: refined);
    final result = await compute<_ComputeArgs, AvalancheResponse>(
      _runInIsolate, args,
    );

    debugPrint('[avalanche] ${result.startZones.length} zones, '
        '${result.cones.length} cônes');
    return result;
  }

  // ── HGT coverage ────────────────────────────────────────────────────────────

  static Future<bool> _checkHgtCoverage(LatLng sw, LatLng ne) async {
    final pts = [
      sw, ne,
      LatLng(sw.latitude, ne.longitude),
      LatLng(ne.latitude, sw.longitude),
      LatLng((sw.latitude + ne.latitude) / 2, (sw.longitude + ne.longitude) / 2),
    ];
    for (final p in pts) {
      if (!await HgtElevationProvider.isAvailable(p.latitude, p.longitude)) {
        return false;
      }
    }
    return true;
  }

  // ── Grille de filtrage (200m) ────────────────────────────────────────────────

  static Future<List<_GridPoint>> _buildGrid(
    LatLng sw, LatLng ne, double resolutionM, HgtElevationProvider hgt,
  ) async {
    final stepLat = resolutionM / 111000;
    final midLat  = (sw.latitude + ne.latitude) / 2;
    final stepLon = resolutionM / (111000 * math.cos(midLat * math.pi / 180));
    final grid    = <_GridPoint>[];

    var lat = sw.latitude + stepLat;
    while (lat < ne.latitude - stepLat) {
      var lon = sw.longitude + stepLon;
      while (lon < ne.longitude - stepLon) {
        final e  = await hgt.getElevation(lat, lon);
        final eN = await hgt.getElevation(lat + stepLat, lon);
        final eS = await hgt.getElevation(lat - stepLat, lon);
        final eE = await hgt.getElevation(lat, lon + stepLon);
        final eW = await hgt.getElevation(lat, lon - stepLon);
        final dzDy = (eN - eS) / (2 * stepLat * 111000);
        final dzDx = (eE - eW) / (2 * stepLon * 111000 *
                     math.cos(lat * math.pi / 180));
        final grad     = math.sqrt(dzDx * dzDx + dzDy * dzDy);
        final slopeDeg = math.atan(grad) * 180 / math.pi;
        final aspectRad = math.atan2(dzDx, dzDy);
        final aspectDeg = (aspectRad * 180 / math.pi + 360) % 360;

        grid.add(_GridPoint(
          lat: lat, lon: lon, elevM: e,
          slopeDeg: slopeDeg, aspectDeg: aspectDeg,
        ));
        lon += stepLon;
      }
      lat += stepLat;
    }
    return grid;
  }

  // ── Grille d'élévation pour flood-fill (50m) ────────────────────────────────

  static Future<_ElevGrid> _buildElevGrid(
    LatLng sw, LatLng ne, double resolutionM, HgtElevationProvider hgt,
  ) async {
    final stepLat = resolutionM / 111000;
    final midLat  = (sw.latitude + ne.latitude) / 2;
    final stepLon = resolutionM / (111000 * math.cos(midLat * math.pi / 180));

    final lats = <double>[];
    var lat = sw.latitude;
    while (lat <= ne.latitude + stepLat * 0.5) {
      lats.add(lat);
      lat += stepLat;
    }
    final lons = <double>[];
    var lon = sw.longitude;
    while (lon <= ne.longitude + stepLon * 0.5) {
      lons.add(lon);
      lon += stepLon;
    }

    final elevs = List<double>.filled(lats.length * lons.length, 0);
    for (int r = 0; r < lats.length; r++) {
      for (int c = 0; c < lons.length; c++) {
        elevs[r * lons.length + c] =
            await hgt.getElevation(lats[r], lons[c]);
      }
    }
    return _ElevGrid(
      lats: lats, lons: lons, elevs: elevs,
      nRows: lats.length, nCols: lons.length,
    );
  }

  // ── Filtrage zones de départ ──────────────────────────────────────────────────

  static List<_AspectedZone> _findStartZones(
    List<_GridPoint> grid,
    _BeraSimple bera,
    int? riskOverride,
    int maxZones,
  ) {
    final realMax     = math.max(bera.risqueBas, bera.risqueHaut ?? 0);
    final ignoreAspect = riskOverride != null && riskOverride > realMax;
    final zones        = <_AspectedZone>[];

    for (final pt in grid) {
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

      final isNorth = pt.aspectDeg <= 90 || pt.aspectDeg >= 270;
      final limite  = (isNorth ? bera.limiteNordM : bera.limiteSudM) ?? 1000;
      if (pt.elevM < limite) continue;
      if (pt.slopeDeg < params.slopeMin) continue;
      if (!ignoreAspect &&
          !_isAspectDangerous(pt.aspectDeg, bera.pentesDangereuses)) continue;

      zones.add(_AspectedZone(
        AvalancheStartZone(
          point:    LatLng(pt.lat, pt.lon),
          slope:    pt.slopeDeg,
          altitude: pt.elevM,
          aspect:   _aspectDegToCode(pt.aspectDeg),
          severity: _severityForRisk(risque),
          risque:   risque,
        ),
        pt.aspectDeg,
        (_beraParams[risque]?.coneLengthM ?? 300.0), // affinée après
      ));
    }

    if (zones.length > maxZones) {
      final step = zones.length ~/ maxZones;
      return [for (int i = 0; i < zones.length; i += step) zones[i]]
          .take(maxZones)
          .toList();
    }
    return zones;
  }

  // ── Isolate ───────────────────────────────────────────────────────────────────

  static AvalancheResponse _runInIsolate(_ComputeArgs args) {
    final zones = args.startZones.map((a) => a.zone).toList();

    // Un triangle par zone de départ, avec longueur effective (tronquée
    // si la pente remonte). Pas de regroupement — chaque couloir visible.
    final cones = <AvalancheCone>[];
    for (final a in args.startZones) {
      final ring = _propagateCone(a);
      if (ring.length >= 3) {
        cones.add(AvalancheCone(
          ring:     ring,
          startLat: a.zone.point.latitude,
          startLon: a.zone.point.longitude,
          severity: _severityForRisk(a.zone.risque),
          risque:   a.zone.risque,
        ));
      }
    }

    return AvalancheResponse(
      massifName:  null,
      risqueBas:   1,
      risqueHaut:  null,
      startZones:  zones,
      cones:       cones,
      mergedZones: null,
    );
  }

  // ── Flood-fill terrain-aware ──────────────────────────────────────────────────

  // ── Cône géométrique (triangle) ──────────────────────────────────────────

  /// Calcule les points du cône triangulaire d'une zone de départ.
  /// Retourne [apex, bord_gauche, arc..., bord_droit] — tous les points
  /// du périmètre du triangle, utilisés pour le convex hull par niveau.
  static List<LatLng> _propagateCone(_AspectedZone aspected) {
    final zone      = aspected.zone;
    final params    = _beraParams[zone.risque];
    if (params == null) return const [];

    final lat        = zone.point.latitude;
    final lon        = zone.point.longitude;
    final halfAngle  = params.coneAngleDeg / 2;
    final downslope  = (aspected.aspectDeg + 180) % 360;
    // Longueur effective : tronquée sur remontée de pente, sinon max BERA
    final lengthM    = aspected.effectiveLengthM;

    final nArc = math.max(5, (params.coneAngleDeg / 5).round());
    final points = <LatLng>[LatLng(lat, lon)]; // apex
    for (int k = 0; k <= nArc; k++) {
      final t       = k / nArc;
      final bearing = (downslope - halfAngle + t * params.coneAngleDeg) % 360;
      points.add(_destinationPoint(lat, lon, bearing, lengthM));
    }
    return points;
  }

  // ── Enveloppe convexe (Graham scan) ──────────────────────────────────────

  static List<LatLng> _convexHull(List<LatLng> pts) {
    if (pts.length < 3) return pts;
    int pivot = 0;
    for (int i = 1; i < pts.length; i++) {
      if (pts[i].latitude < pts[pivot].latitude ||
          (pts[i].latitude == pts[pivot].latitude &&
           pts[i].longitude < pts[pivot].longitude)) {
        pivot = i;
      }
    }
    final p0     = pts[pivot];
    final sorted = List<LatLng>.from(pts)..remove(p0);
    sorted.sort((a, b) {
      final angleA = math.atan2(a.latitude  - p0.latitude,
                                a.longitude - p0.longitude);
      final angleB = math.atan2(b.latitude  - p0.latitude,
                                b.longitude - p0.longitude);
      if (angleA != angleB) return angleA.compareTo(angleB);
      final da = (a.latitude  - p0.latitude)  * (a.latitude  - p0.latitude) +
                 (a.longitude - p0.longitude) * (a.longitude - p0.longitude);
      final db = (b.latitude  - p0.latitude)  * (b.latitude  - p0.latitude) +
                 (b.longitude - p0.longitude) * (b.longitude - p0.longitude);
      return da.compareTo(db);
    });
    final hull = <LatLng>[p0];
    for (final pt in sorted) {
      while (hull.length >= 2 && _cross(hull[hull.length-2], hull[hull.length-1], pt) <= 0) {
        hull.removeLast();
      }
      hull.add(pt);
    }
    hull.add(hull.first); // fermer
    return hull;
  }

  static double _cross(LatLng o, LatLng a, LatLng b) =>
      (a.longitude - o.longitude) * (b.latitude  - o.latitude) -
      (a.latitude  - o.latitude)  * (b.longitude - o.longitude);

  // ── Longueur effective du cône (tronquée sur remontée de pente) ─────────────

  /// Échantillonne l'altitude le long de la direction de descente (downslope)
  /// et retourne la distance réelle avant la première remontée significative.
  ///
  /// Paramètre [upslopeBlockDeg] : angle de remontée max avant troncature.
  /// Identique à [_upslopeBlockDeg] utilisé dans le flood-fill.
  static Future<double> _computeEffectiveLength(
    double startLat,
    double startLon,
    double downslopeDeg,
    double maxLengthM,
    HgtElevationProvider hgt, {
    double upslopeBlockDeg = _upslopeBlockDeg,
    double stepM = 50.0,
  }) async {
    double prevElev = await hgt.getElevation(startLat, startLon);
    double dist     = stepM;

    while (dist <= maxLengthM) {
      final pt      = _destinationPoint(startLat, startLon, downslopeDeg, dist);
      final elev    = await hgt.getElevation(pt.latitude, pt.longitude);
      final elevDiff = elev - prevElev;

      if (elevDiff > 0) {
        final slopeDeg = math.atan(elevDiff / stepM) * 180 / math.pi;
        if (slopeDeg > upslopeBlockDeg) {
          // Remontée significative → tronquer ici
          return math.max(dist - stepM, stepM);
        }
      }
      prevElev = elev;
      dist    += stepM;
    }
    return maxLengthM; // pas de remontée → longueur max BERA
  }

  static LatLng _destinationPoint(
      double lat, double lon, double bearingDeg, double distanceM) {
    final bearing = bearingDeg * math.pi / 180;
    final dlat    = (distanceM / 111000) * math.cos(bearing);
    final dlon    = (distanceM / (111000 * math.cos(lat * math.pi / 180)))
                  * math.sin(bearing);
    return LatLng(lat + dlat, lon + dlon);
  }

  /// Retourne l'ensemble des cellules inondées depuis une zone de départ.
  /// Utilisé pour la fusion par niveau de risque.
  static Set<int> _floodFillCells(
    _AspectedZone aspected,
    _ElevGrid grid,
  ) {
    final zone     = aspected.zone;
    final params   = _beraParams[zone.risque];
    if (params == null) return const {};

    final startLat = zone.point.latitude;
    final startLon = zone.point.longitude;
    final maxDistM = params.coneLengthM;

    // Trouver la cellule de départ dans la grille flood
    final startRow = _nearestIdx(grid.lats, startLat);
    final startCol = _nearestIdx(grid.lons, startLon);
    if (startRow < 0 || startCol < 0) return const {};

    // BFS flood-fill
    // visited[row * nCols + col] = true si cellule visitée
    final visited = List<bool>.filled(grid.nRows * grid.nCols, false);
    final flooded = <int>{}; // indices des cellules inondées
    final queue   = Queue<(int, int)>();

    visited[startRow * grid.nCols + startCol] = true;
    queue.add((startRow, startCol));
    flooded.add(startRow * grid.nCols + startCol);

    // Voisins 8-connectés (y compris diagonales)
    const dRows = [-1, -1, -1, 0, 0, 1, 1, 1];
    const dCols = [-1,  0,  1,-1, 1,-1, 0, 1];

    while (queue.isNotEmpty) {
      final (r, c) = queue.removeFirst();
      final elevCurrent = grid.elev(r, c);

      for (int d = 0; d < 8; d++) {
        final nr = r + dRows[d];
        final nc = c + dCols[d];
        if (nr < 0 || nr >= grid.nRows || nc < 0 || nc >= grid.nCols) continue;
        final idx = nr * grid.nCols + nc;
        if (visited[idx]) continue;
        visited[idx] = true;

        // Distance à la zone de départ
        final nLat = grid.lats[nr];
        final nLon = grid.lons[nc];
        final dist = _distanceM(startLat, startLon, nLat, nLon);
        if (dist > maxDistM) continue;

        // Règle de blocage : pente remontante > _upslopeBlockDeg → crête, stop
        final elevNeighbor = grid.elev(nr, nc);
        final elevDiff     = elevNeighbor - elevCurrent; // positif = remontée

        if (elevDiff > 0) {
          // Calculer l'angle de remontée
          final stepM = _floodResolutionM * (d < 4 || d == 7 ? 1.0 : math.sqrt2);
          final upSlopeDeg = math.atan(elevDiff / stepM) * 180 / math.pi;
          if (upSlopeDeg > _upslopeBlockDeg) continue; // crête → bloqué
        }

        flooded.add(idx);
        queue.add((nr, nc));
      }
    }

    return flooded;
  }

  // ── Contour réel des cellules inondées (border tracing) ─────────────────────
  //
  // On trace le contour exact de l'ensemble des cellules inondées en suivant
  // les bords entre cellules inondées et non-inondées.
  //
  // Algorithme : chaque cellule est un carré. On parcourt les 4 arêtes de
  // chaque cellule de bord. Une arête est "de contour" si elle sépare une
  // cellule inondée d'une cellule non-inondée (ou du bord de la grille).
  //
  // On reconstruit ensuite le polygone en chaînant les arêtes de contour
  // dans l'ordre (chaque arête partage un coin avec la suivante).
  //
  // Résultat : un polygone en escalier (pixelisé à 50m) qui suit exactement
  // la forme de la coulée — couloirs étroits, virages en vallée, tout est
  // respecté. Aucune "complétion" convexe indésirable.

  /// Retourne les contours de toutes les composantes connexes significatives
  /// (taille > 10% de la plus grande ou > 5 cellules).
  static List<List<LatLng>> _buildAllContourRings(
      Set<int> flooded, _ElevGrid grid) {
    if (flooded.isEmpty) return const [];

    final nR = grid.nRows;
    final nC = grid.nCols;
    final stride = nC * 2 + 2;
    final Map<int, int> edgeMap = {};
    void addEdge(int a, int b) { edgeMap[a] = b; }

    for (final idx in flooded) {
      final r  = idx ~/ nC;
      final c  = idx  % nC;
      final tl = (2*r)   * stride + (2*c);
      final tr = (2*r)   * stride + (2*c+2);
      final bl = (2*r+2) * stride + (2*c);
      final br = (2*r+2) * stride + (2*c+2);
      if (r == 0    || !flooded.contains((r-1)*nC + c)) addEdge(tr, tl);
      if (r == nR-1 || !flooded.contains((r+1)*nC + c)) addEdge(bl, br);
      if (c == 0    || !flooded.contains(r*nC + (c-1))) addEdge(tl, bl);
      if (c == nC-1 || !flooded.contains(r*nC + (c+1))) addEdge(br, tr);
    }

    if (edgeMap.isEmpty || grid.lats.length < 2) return const [];

    final stepLat = grid.lats[1] - grid.lats[0];
    final stepLon = grid.lons[1] - grid.lons[0];

    // Extraire toutes les composantes
    final remaining = Map<int, int>.from(edgeMap);
    final components = <List<int>>[];
    while (remaining.isNotEmpty) {
      final start     = remaining.keys.first;
      final component = <int>[start];
      var cur = remaining.remove(start);
      int safety = 0;
      while (cur != null && cur != start && safety < edgeMap.length) {
        component.add(cur);
        cur = remaining.remove(cur);
        safety++;
      }
      if (component.length >= 4) components.add(component);
    }

    if (components.isEmpty) return const [];

    // Garder les composantes significatives (≥10% de la plus grande, min 8 pts)
    final maxLen  = components.map((c) => c.length).reduce(math.max);
    final minSize = math.max(8, (maxLen * 0.10).round());

    final result = <List<LatLng>>[];
    for (final comp in components) {
      if (comp.length < minSize) continue;
      final ring = <LatLng>[];
      for (final key in comp) {
        ring.add(LatLng(
          grid.lats[0] + (key ~/ stride / 2.0) * stepLat,
          grid.lons[0] + (key  % stride / 2.0) * stepLon,
        ));
      }
      ring.add(ring.first);
      final smoothed = _chaikin(ring, 3);
      if (smoothed.length >= 3) result.add(smoothed);
    }

    return result;
  }

  static List<LatLng> _buildContourRing(Set<int> flooded, _ElevGrid grid) {
    if (flooded.isEmpty) return const [];

    // Chaque arête de contour est définie par deux coins (en coordonnées
    // de grille demi-entières : coins = (row±0.5, col±0.5)).
    // On utilise des indices entiers ×2 pour éviter les flottants :
    // coin (r2, c2) → lat = lats[r2/2] + (r2%2==1 ? stepLat/2 : 0)
    // On représente les arêtes comme paires de coins (encodés en int).

    // Pas de grille en indices
    final nR = grid.nRows;
    final nC = grid.nCols;

    // Map : coin_start → coin_end pour chaque arête de contour orientée
    // (orientée : inondé à gauche quand on avance de start vers end)
    final Map<int, int> edgeMap = {};

    final stride = nC * 2 + 2;
    // addEdge prend deux coins déjà encodés (pas r,c séparément)
    void addEdge(int a, int b) { edgeMap[a] = b; }

    for (final idx in flooded) {
      final r = idx ~/ nC;
      final c = idx  % nC;

      // Coins encodés (coordonnées ×2 pour les demi-pas) :
      //   TL = top-left, TR = top-right, BL = bottom-left, BR = bottom-right
      // Orientation : inondé à gauche quand on avance de A→B
      //   Nord libre → TR→TL, Sud libre → BL→BR
      //   Ouest libre→ TL→BL, Est libre → BR→TR
      final tl = (2*r)   * stride + (2*c);
      final tr = (2*r)   * stride + (2*c+2);
      final bl = (2*r+2) * stride + (2*c);
      final br = (2*r+2) * stride + (2*c+2);

      final northFree = r == 0    || !flooded.contains((r-1)*nC + c);
      final southFree = r == nR-1 || !flooded.contains((r+1)*nC + c);
      final westFree  = c == 0    || !flooded.contains(r*nC + (c-1));
      final eastFree  = c == nC-1 || !flooded.contains(r*nC + (c+1));

      if (northFree) addEdge(tr, tl);
      if (southFree) addEdge(bl, br);
      if (westFree)  addEdge(tl, bl);
      if (eastFree)  addEdge(br, tr);
    }

    if (edgeMap.isEmpty) return const [];
    if (grid.lats.length < 2 || grid.lons.length < 2) return const [];

    // ── Extraire TOUTES les composantes de contour ──────────────────────────
    //
    // Le edgeMap peut contenir plusieurs cycles disjoints (un par îlot de
    // cellules non connexes). L'ancien algo ne suivait que le premier cycle
    // → ring vide si la 1ère composante était petite ou non fermée.
    // On extrait toutes les composantes et on garde la plus grande.
    final remaining = Map<int, int>.from(edgeMap);
    List<int>? largest;

    while (remaining.isNotEmpty) {
      final start     = remaining.keys.first;
      final component = <int>[start];
      var cur = remaining.remove(start);
      int safety = 0;
      while (cur != null && cur != start && safety < edgeMap.length) {
        component.add(cur);
        cur = remaining.remove(cur);
        safety++;
      }
      if (largest == null || component.length > largest.length) {
        largest = component;
      }
    }

    if (largest == null || largest.length < 3) return const [];

    final stepLat = grid.lats[1] - grid.lats[0];
    final stepLon = grid.lons[1] - grid.lons[0];

    final ring = <LatLng>[];
    for (final key in largest) {
      final r2 = key ~/ stride;
      final c2 = key  % stride;
      ring.add(LatLng(
        grid.lats[0] + (r2 / 2.0) * stepLat,
        grid.lons[0] + (c2 / 2.0) * stepLon,
      ));
    }
    if (ring.isNotEmpty) ring.add(ring.first);

    // Douglas-Peucker supprimé — créait des segments rectilignes artificiels
    // sur les arêtes et ruptures de pente (terrain montagneux défavorable).
    // Chaikin seul suffit pour lisser les escaliers du border tracing à 50m.
    return _chaikin(ring, 3);
  }

  // ── Douglas-Peucker (désactivé) ───────────────────────────────────────────

  static List<LatLng> _douglasPeucker(List<LatLng> pts, double epsilon) {
    if (pts.length < 3) return pts;

    double dmax = 0;
    int idx = 0;
    final a = pts.first;
    final b = pts.last;

    for (int i = 1; i < pts.length - 1; i++) {
      final d = _perpDistance(pts[i], a, b);
      if (d > dmax) { dmax = d; idx = i; }
    }

    if (dmax > epsilon) {
      final left  = _douglasPeucker(pts.sublist(0, idx + 1), epsilon);
      final right = _douglasPeucker(pts.sublist(idx), epsilon);
      return [...left.sublist(0, left.length - 1), ...right];
    }
    return [a, b];
  }

  static double _perpDistance(LatLng p, LatLng a, LatLng b) {
    final dx = b.longitude - a.longitude;
    final dy = b.latitude  - a.latitude;
    if (dx == 0 && dy == 0) {
      return math.sqrt(
        (p.longitude - a.longitude) * (p.longitude - a.longitude) +
        (p.latitude  - a.latitude)  * (p.latitude  - a.latitude),
      );
    }
    final t = ((p.longitude - a.longitude) * dx +
               (p.latitude  - a.latitude)  * dy) /
              (dx * dx + dy * dy);
    final px = a.longitude + t * dx;
    final py = a.latitude  + t * dy;
    return math.sqrt(
      (p.longitude - px) * (p.longitude - px) +
      (p.latitude  - py) * (p.latitude  - py),
    );
  }

  // ── Lissage Chaikin ────────────────────────────────────────────────────────
  //
  // Chaque passe coupe les coins : chaque segment AB devient deux segments
  // A'B' où A'=0.75A+0.25B et B'=0.25A+0.75B. Après 3 passes le contour
  // est une courbe lisse qui passe à l'intérieur du polygone original.
  // L'ensemble inondé est donc légèrement sous-estimé — acceptable pour
  // la visualisation risque (conservatif à 50m près).

  static List<LatLng> _chaikin(List<LatLng> pts, int iterations) {
    var cur = pts;
    for (int iter = 0; iter < iterations; iter++) {
      final next = <LatLng>[];
      final n = cur.length - 1; // polygone fermé
      for (int i = 0; i < n; i++) {
        final p0 = cur[i];
        final p1 = cur[(i + 1) % n];
        next.add(LatLng(
          0.75 * p0.latitude  + 0.25 * p1.latitude,
          0.75 * p0.longitude + 0.25 * p1.longitude,
        ));
        next.add(LatLng(
          0.25 * p0.latitude  + 0.75 * p1.latitude,
          0.25 * p0.longitude + 0.75 * p1.longitude,
        ));
      }
      next.add(next.first); // fermer
      cur = next;
    }
    return cur;
  }

  // ── Helpers géographiques ─────────────────────────────────────────────────────

  static double _distanceM(
      double lat1, double lon1, double lat2, double lon2) {
    final dlat = (lat2 - lat1) * 111000;
    final dlon = (lon2 - lon1) * 111000 *
                 math.cos(lat1 * math.pi / 180);
    return math.sqrt(dlat * dlat + dlon * dlon);
  }

  static int _nearestIdx(List<double> sorted, double val) {
    if (sorted.isEmpty) return -1;
    int lo = 0, hi = sorted.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (sorted[mid] < val) lo = mid + 1; else hi = mid;
    }
    return lo;
  }

  // ── Helpers BERA ─────────────────────────────────────────────────────────────

  static bool _isAspectDangerous(
    double aspectDeg, Map<String, bool> pd,
  ) {
    const centers = {
      'N': 0.0, 'NE': 45.0, 'E': 90.0, 'SE': 135.0,
      'S': 180.0, 'SW': 225.0, 'W': 270.0, 'NW': 315.0,
    };
    for (final e in pd.entries) {
      if (!e.value) continue;
      final center = centers[e.key] ?? 0;
      final diff   = ((aspectDeg - center + 180) % 360 - 180).abs();
      if (diff <= 25.0) return true;
    }
    return false;
  }

  static String _aspectDegToCode(double deg) {
    const codes = ['N','NE','E','SE','S','SW','W','NW'];
    return codes[((deg + 22.5) / 45).floor() % 8];
  }

  static double _severityForRisk(int risque) => switch (risque) {
    1 => 0.2, 2 => 0.35, 3 => 0.55, 4 => 0.75, 5 => 0.95, _ => 0.5,
  };
}
