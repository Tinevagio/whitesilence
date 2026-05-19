// lib/core/elevation/elevation_provider.dart
//
// Contrat des fournisseurs d'altitude pour WhiteSilence.
//
// Trois implémentations partagées entre tous les modules :
//   - HgtElevationProvider     (offline, ±30m de précision, fichiers .hgt SRTM1)
//   - OpenMeteoElevationProvider (online, ~400m, gratuit, sans clé)
//   - DemoElevationProvider    (synthétique, pour démo et tests sans réseau)
//
// La sélection se fait dans `dem_selector.dart`.

import 'package:latlong2/latlong.dart';

abstract class ElevationProvider {
  /// Altitude en mètres pour un point.
  Future<double> getElevation(double lat, double lng);

  /// Précharge une zone rectangulaire (optimisation batch).
  /// Optionnel — l'implémentation peut être un no-op.
  Future<void> prefetch(LatLng sw, LatLng ne) async {}
}
