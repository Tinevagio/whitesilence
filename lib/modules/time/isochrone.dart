// lib/modules/time/isochrone.dart
//
// Calcul des isochrones par ray-casting adaptatif.
// Migré depuis TimeToGo (lib/isochrone.dart).
//
// Différence majeure : on utilise `latlong2.LatLng` partagé au lieu de la
// classe LatLng locale. Plus de wrapping/unwrapping dans les widgets.

import 'dart:math';
import 'package:latlong2/latlong.dart';

import '../../core/elevation/elevation_provider.dart';
import 'munter.dart';

// ─── Types légers internes ────────────────────────────────────────────────────

class _LatLngWithAlt {
  final double lat;
  final double lng;
  final double altM;
  const _LatLngWithAlt(this.lat, this.lng, this.altM);
}

// ─── Paramètres de calcul ─────────────────────────────────────────────────────

class IsochroneConfig {
  final List<int> timeBudgetsMinutes;
  final int rayCount;
  final double baseStepM;
  final double minStepM;
  final double maxStepM;
  final double maxRayDistanceM;

  const IsochroneConfig({
    this.timeBudgetsMinutes = const [15, 30, 45, 60],
    this.rayCount            = 72,
    this.baseStepM           = 50.0,
    this.minStepM            = 15.0,
    this.maxStepM            = 200.0,
    this.maxRayDistanceM     = 8000.0,
  });
}

// ─── Résultat ─────────────────────────────────────────────────────────────────

class IsochroneResult {
  final Map<int, List<LatLng>> contours;
  final Duration computeDuration;
  const IsochroneResult({
    required this.contours,
    required this.computeDuration,
  });
}

// ─── Moteur principal ─────────────────────────────────────────────────────────

class IsochroneEngine {
  final MunterEngine munter;
  final ElevationProvider dem;
  final IsochroneConfig config;

  IsochroneEngine({
    required this.munter,
    required this.dem,
    IsochroneConfig? config,
  }) : config = config ?? const IsochroneConfig();

  Future<IsochroneResult> compute(LatLng origin) async {
    final sw = Stopwatch()..start();

    final originAlt = await dem.getElevation(origin.latitude, origin.longitude);
    final originFull = _LatLngWithAlt(origin.latitude, origin.longitude, originAlt);

    final budgets = List<int>.from(config.timeBudgetsMinutes)..sort();
    final Map<int, List<LatLng>> contours = {for (final b in budgets) b: []};
    final angleStep = 2 * pi / config.rayCount;

    for (int i = 0; i < config.rayCount; i++) {
      final angle = i * angleStep;
      final rayPoints = await _traceRay(originFull, angle, budgets);
      for (final b in budgets) {
        final pt = rayPoints[b];
        if (pt != null) contours[b]!.add(pt);
      }
    }

    sw.stop();
    return IsochroneResult(contours: contours, computeDuration: sw.elapsed);
  }

  Future<Map<int, LatLng?>> _traceRay(
    _LatLngWithAlt origin,
    double angleRad,
    List<int> budgetsSorted,
  ) async {
    final result = <int, LatLng?>{for (final b in budgetsSorted) b: null};

    double accumulatedSeconds = 0.0;
    double currentLat = origin.lat;
    double currentLng = origin.lng;
    double currentAlt = origin.altM;
    double totalDist  = 0.0;

    int budgetIdx = 0;
    final maxBudgetS = budgetsSorted.last * 60.0;

    while (accumulatedSeconds < maxBudgetS &&
           totalDist < config.maxRayDistanceM) {

      // Pas adaptatif : sonde courte pour mesurer la pente locale
      final probeStep = config.minStepM;
      final probeLat  = _destinationLat(currentLat, currentLng, angleRad, probeStep);
      final probeLng  = _destinationLng(currentLat, currentLng, angleRad, probeStep);
      final probeAlt  = await dem.getElevation(probeLat, probeLng);
      final probeSlopePct = _slopePct(probeAlt - currentAlt, probeStep);
      final stepM = _adaptiveStep(probeSlopePct);

      final nextLat = _destinationLat(currentLat, currentLng, angleRad, stepM);
      final nextLng = _destinationLng(currentLat, currentLng, angleRad, stepM);
      final nextAlt = (stepM == probeStep)
          ? probeAlt
          : await dem.getElevation(nextLat, nextLng);

      final elevDiff = nextAlt - currentAlt;
      final elevGain = elevDiff > 0 ? elevDiff : 0.0;
      final elevLoss = elevDiff < 0 ? -elevDiff : 0.0;

      final stepSeconds = munter.estimateSeconds(
        distanceM: stepM,
        elevGain:  elevGain,
        elevLoss:  elevLoss,
      );

      accumulatedSeconds += stepSeconds;
      totalDist += stepM;

      while (budgetIdx < budgetsSorted.length &&
             accumulatedSeconds >= budgetsSorted[budgetIdx] * 60.0) {
        final budgetS   = budgetsSorted[budgetIdx] * 60.0;
        final overshoot = accumulatedSeconds - budgetS;
        final ratio     = 1.0 - (overshoot / stepSeconds).clamp(0.0, 1.0);

        final interpLat = currentLat + (nextLat - currentLat) * ratio;
        final interpLng = currentLng + (nextLng - currentLng) * ratio;
        result[budgetsSorted[budgetIdx]] = LatLng(interpLat, interpLng);

        budgetIdx++;
      }

      if (budgetIdx >= budgetsSorted.length) break;

      currentLat = nextLat;
      currentLng = nextLng;
      currentAlt = nextAlt;
    }

    for (int b = budgetIdx; b < budgetsSorted.length; b++) {
      result[budgetsSorted[b]] ??= LatLng(currentLat, currentLng);
    }

    return result;
  }

  // Pas adaptatif selon la pente
  double _adaptiveStep(double slopePct) {
    final abs = slopePct.abs();
    if (abs < 5)  return config.maxStepM;
    if (abs < 15) return config.baseStepM;
    if (abs < 30) return config.baseStepM * 0.6;
    return config.minStepM;
  }

  // ─── Géodésie ────────────────────────────────────────────────────────────

  static const _earthRadiusM = 6371000.0;

  static double _slopePct(double elevDiff, double distM) =>
      distM > 0 ? (elevDiff / distM) * 100.0 : 0.0;

  static double _destinationLat(
      double lat, double lng, double bearingRad, double distM) {
    final latR    = _deg2rad(lat);
    final angDist = distM / _earthRadiusM;
    final newLat = asin(sin(latR) * cos(angDist) +
                        cos(latR) * sin(angDist) * cos(bearingRad));
    return _rad2deg(newLat);
  }

  static double _destinationLng(
      double lat, double lng, double bearingRad, double distM) {
    final latR    = _deg2rad(lat);
    final lngR    = _deg2rad(lng);
    final angDist = distM / _earthRadiusM;
    final newLng = lngR + atan2(
      sin(bearingRad) * sin(angDist) * cos(latR),
      cos(angDist) - sin(latR) * sin(asin(sin(latR) * cos(angDist) +
                                          cos(latR) * sin(angDist) * cos(bearingRad))),
    );
    return _rad2deg(newLng);
  }

  static double _deg2rad(double d) => d * pi / 180.0;
  static double _rad2deg(double r) => r * 180.0 / pi;
}

// ─── Lissage du contour ──────────────────────────────────────────────────────

/// Lissage de Chaikin (2-3 itérations donne un résultat fluide).
List<LatLng> chaikinSmooth(List<LatLng> pts, {int iterations = 2}) {
  if (pts.length < 3) return pts;
  var current = pts;
  for (int i = 0; i < iterations; i++) {
    current = _chaikinStep(current);
  }
  return current;
}

List<LatLng> _chaikinStep(List<LatLng> pts) {
  final result = <LatLng>[];
  final n = pts.length;
  for (int i = 0; i < n; i++) {
    final p0 = pts[i];
    final p1 = pts[(i + 1) % n];
    result.add(LatLng(
      0.75 * p0.latitude  + 0.25 * p1.latitude,
      0.75 * p0.longitude + 0.25 * p1.longitude,
    ));
    result.add(LatLng(
      0.25 * p0.latitude  + 0.75 * p1.latitude,
      0.25 * p0.longitude + 0.75 * p1.longitude,
    ));
  }
  return result;
}
