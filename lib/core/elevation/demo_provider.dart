// lib/core/elevation/demo_provider.dart
//
// Terrain synthétique pour démo / tests sans réseau ni fichiers HGT.
// Migré depuis TimeToGo.

import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'elevation_provider.dart';

class DemoElevationProvider implements ElevationProvider {
  final double originLat;
  final double originLng;
  final double baseAltitude;

  const DemoElevationProvider({
    required this.originLat,
    required this.originLng,
    this.baseAltitude = 1200.0,
  });

  @override
  Future<double> getElevation(double lat, double lng) async {
    final dx = (lng - originLng) * 111320 * cos(originLat * pi / 180);
    final dy = (lat - originLat) * 110540;

    final hill1  = 400 * sin(dy / 1500 + 0.5) * sin(dx / 1800 + 0.3);
    final valley = -200 * exp(-pow((dx + 1200) / 800, 2).toDouble()) *
                          exp(-pow(dy / 1500, 2).toDouble());
    final noise  = 80 * sin(dx / 600) * cos(dy / 700 + 1.2)
                 + 40 * cos(dx / 300 + 0.8) * sin(dy / 350);
    final trend  = dy / 20;

    return baseAltitude + hill1 + valley + noise + trend;
  }

  @override
  Future<void> prefetch(LatLng sw, LatLng ne) async {}
}
