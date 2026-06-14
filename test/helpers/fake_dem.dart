// test/helpers/fake_dem.dart
//
// Faux ElevationProviders pour les tests unitaires.
// Aucune dépendance réseau / fichier HGT.

import 'package:latlong2/latlong.dart';
import 'package:whitesilence/core/elevation/elevation_provider.dart';

/// Terrain entièrement plat à [alt] mètres.
class FlatDem implements ElevationProvider {
  final double alt;
  const FlatDem([this.alt = 1500.0]);

  @override
  Future<double> getElevation(double lat, double lng) async => alt;

  @override
  Future<void> prefetch(LatLng sw, LatLng ne) async {}
}

/// Terrain en pente régulière vers le nord.
/// Altitude = [baseAlt] + (lat - [refLat]) * [mPerDeg].
///
/// Exemple par défaut : +1000m par degré de latitude ≈ +9m/100m vers le nord.
class SlopedDem implements ElevationProvider {
  final double baseAlt;
  final double refLat;
  final double mPerDeg;

  const SlopedDem({
    this.baseAlt = 1500.0,
    this.refLat  = 45.0,
    this.mPerDeg = 1000.0,
  });

  @override
  Future<double> getElevation(double lat, double lng) async =>
      baseAlt + (lat - refLat) * mPerDeg;

  @override
  Future<void> prefetch(LatLng sw, LatLng ne) async {}
}

/// DEM qui échoue toujours (simule une tuile absente / hors-ligne).
/// Le GpsCalibrator doit retomber sur l'altitude GPS dans ce cas.
class FailingDem implements ElevationProvider {
  @override
  Future<double> getElevation(double lat, double lng) async =>
      throw Exception('DEM indisponible (simulé)');

  @override
  Future<void> prefetch(LatLng sw, LatLng ne) async {}
}

/// DEM avec un "palier" : altitude [lowAlt] en dessous de [stepLat],
/// [highAlt] au-dessus. Simule une falaise ou une rupture de pente franche.
class StepDem implements ElevationProvider {
  final double stepLat;
  final double lowAlt;
  final double highAlt;

  const StepDem({
    required this.stepLat,
    this.lowAlt  = 1500.0,
    this.highAlt = 1800.0,
  });

  @override
  Future<double> getElevation(double lat, double lng) async =>
      lat >= stepLat ? highAlt : lowAlt;

  @override
  Future<void> prefetch(LatLng sw, LatLng ne) async {}
}
