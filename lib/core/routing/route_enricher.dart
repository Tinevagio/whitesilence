// lib/core/routing/route_enricher.dart
//
// Enrichit un tracé géométrique (RouteResult) avec le dénivelé et le temps,
// en réutilisant les moteurs EXISTANTS de WhiteSilence :
//   - ElevationProvider (HgtElevationProvider en priorité) pour les altitudes
//   - MunterEngine (calibré GPS) pour le temps
//
// Le tracé renvoyé par le routeur peut avoir des segments longs (entre deux
// nœuds OSM éloignés). On le ré-échantillonne tous ~40 m avant d'échantillonner
// l'altitude, pour capturer le relief sans surcharger les lookups HGT.

import 'package:latlong2/latlong.dart';

import '../elevation/elevation_provider.dart';
import '../../modules/time/munter.dart';
import 'route_provider.dart';

class RouteStats {
  final double distanceM;
  final double elevGainM; // D+
  final double elevLossM; // D-
  final double seconds;   // temps estimé (Munter)
  final List<double> elevations; // profil altimétrique (m), aligné sur points

  const RouteStats({
    required this.distanceM,
    required this.elevGainM,
    required this.elevLossM,
    required this.seconds,
    required this.elevations,
  });

  Duration get duration => Duration(seconds: seconds.round());

  String get distanceLabel => distanceM >= 1000
      ? '${(distanceM / 1000).toStringAsFixed(1)} km'
      : '${distanceM.round()} m';

  String get durationLabel {
    final total = seconds.round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}';
    return '${m} min';
  }
}

class RouteEnricher {
  final ElevationProvider dem;
  final MunterEngine munter;

  /// Pas de ré-échantillonnage du tracé pour le profil altimétrique (m).
  final double sampleStepM;

  /// Seuil de bruit altimétrique : on ignore les micro-variations sous ce
  /// seuil cumulé pour ne pas gonfler artificiellement le D+/D- (le HGT 30m
  /// a un bruit de quelques mètres).
  final double noiseThresholdM;

  const RouteEnricher({
    required this.dem,
    required this.munter,
    this.sampleStepM = 40.0,
    this.noiseThresholdM = 3.0,
  });

  static const Distance _distance = Distance();

  Future<RouteStats> enrich(RouteResult route, RouteProfile profile) async {
    // 1. Ré-échantillonnage régulier du tracé.
    final sampled = _resample(route.points, sampleStepM);

    // 2. Altitudes (lookups HGT, séquentiels — le cache de tuiles encaisse).
    final elevations = <double>[];
    for (final p in sampled) {
      elevations.add(await dem.getElevation(p.latitude, p.longitude));
    }

    // 3. D+/D- avec filtre de bruit + temps Munter segment par segment.
    double gain = 0, loss = 0, totalDist = 0, totalSeconds = 0;
    double pendingDelta = 0; // accumulateur pour le filtre de bruit

    for (var i = 1; i < sampled.length; i++) {
      final segDist =
          _distance.as(LengthUnit.Meter, sampled[i - 1], sampled[i]);
      final rawDelta = elevations[i] - elevations[i - 1];

      // Filtre de bruit : on n'enregistre une variation que lorsqu'elle
      // dépasse le seuil cumulé, puis on solde l'accumulateur.
      pendingDelta += rawDelta;
      double segGain = 0, segLoss = 0;
      if (pendingDelta.abs() >= noiseThresholdM) {
        if (pendingDelta > 0) {
          segGain = pendingDelta;
          gain += pendingDelta;
        } else {
          segLoss = -pendingDelta;
          loss += -pendingDelta;
        }
        pendingDelta = 0;
      }

      totalDist += segDist;
      totalSeconds += munter.estimateSeconds(
        distanceM: segDist,
        elevGain: segGain,
        elevLoss: segLoss,
      );
    }

    return RouteStats(
      distanceM: totalDist,
      elevGainM: gain,
      elevLossM: loss,
      seconds: totalSeconds,
      elevations: elevations,
    );
  }

  /// Ré-échantillonne une polyline pour qu'aucun segment ne dépasse [stepM].
  /// Insère des points intermédiaires par interpolation linéaire.
  List<LatLng> _resample(List<LatLng> pts, double stepM) {
    if (pts.length < 2) return pts;
    final out = <LatLng>[pts.first];
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      final d = _distance.as(LengthUnit.Meter, a, b);
      if (d <= stepM) {
        out.add(b);
        continue;
      }
      final n = (d / stepM).ceil();
      for (var k = 1; k <= n; k++) {
        final t = k / n;
        out.add(LatLng(
          a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t,
        ));
      }
    }
    return out;
  }
}
