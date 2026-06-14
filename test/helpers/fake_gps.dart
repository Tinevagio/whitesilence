// test/helpers/fake_gps.dart
//
// Utilitaires pour construire des traces GPS synthétiques dans les tests.
// Utilise Position.fromMap() pour éviter les incompatibilités de constructeur
// entre versions de geolocator.

import 'package:geolocator/geolocator.dart';

/// Construit une Position geolocator à partir de paramètres nommés.
/// accuracy par défaut = 5m (bon fix).
Position fakePos({
  required double lat,
  required double lng,
  double alt = 1500.0,
  double accuracy = 5.0,
  required DateTime timestamp,
}) {
  return Position(
    latitude:          lat,
    longitude:         lng,
    altitude:          alt,
    accuracy:          accuracy,
    speed:             0.0,
    speedAccuracy:     0.0,
    heading:           0.0,
    headingAccuracy:   0.0,
    altitudeAccuracy:  0.0,
    timestamp:         timestamp,
  );
}

/// Simule une trace GPS linéaire.
///
/// [steps] : liste de deltas (dLat, dLng, dAlt) appliqués séquentiellement.
/// [intervalS] : durée en secondes entre deux fixes consécutifs.
///
/// Retourne N+1 positions (le point de départ + N steps).
List<Position> buildTrace({
  required double startLat,
  required double startLng,
  required double startAlt,
  required List<({double dLat, double dLng, double dAlt})> steps,
  required DateTime t0,
  required int intervalS,
  double accuracy = 5.0,
}) {
  final result = <Position>[];
  double lat = startLat, lng = startLng, alt = startAlt;
  DateTime t = t0;

  result.add(fakePos(lat: lat, lng: lng, alt: alt,
      accuracy: accuracy, timestamp: t));

  for (final step in steps) {
    t   = t.add(Duration(seconds: intervalS));
    lat += step.dLat;
    lng += step.dLng;
    alt += step.dAlt;
    result.add(fakePos(lat: lat, lng: lng, alt: alt,
        accuracy: accuracy, timestamp: t));
  }
  return result;
}

/// Trace simple : N pas identiques.
List<Position> buildUniformTrace({
  required double startLat,
  required double startLng,
  required double startAlt,
  required int count,
  required double dLat,
  required double dLng,
  required double dAlt,
  required DateTime t0,
  required int intervalS,
  double accuracy = 5.0,
}) {
  return buildTrace(
    startLat:  startLat,
    startLng:  startLng,
    startAlt:  startAlt,
    steps:     List.generate(count,
        (_) => (dLat: dLat, dLng: dLng, dAlt: dAlt)),
    t0:        t0,
    intervalS: intervalS,
    accuracy:  accuracy,
  );
}
