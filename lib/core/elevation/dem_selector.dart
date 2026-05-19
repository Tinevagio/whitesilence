// lib/core/elevation/dem_selector.dart
//
// Sélectionne le bon provider d'altitude selon la position et la disponibilité.
//
// Priorité :
//   1. HGT local installé pour cette tuile (offline, ±30m) → idéal
//   2. Open-Meteo (online, grille préchargée ~400m) → fallback réseau
//   3. Demo synthétique (offline mais inutilisable en vrai) → dernier recours
//
// Cache : on garde le DEM actif tant que la position courante reste à
// moins de 500m du centre du cache. Au-delà, on recharge.

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'demo_provider.dart';
import 'elevation_provider.dart';
import 'hgt_provider.dart';
import 'open_meteo_provider.dart';

/// Type de DEM actuellement sélectionné — utile pour l'UI.
enum DemSource {
  hgt,      // 🗻 HGT SRTM1 (30m)
  openMeteo, // 🛰 Open-Meteo (±400m)
  demo,     // ⚠ Terrain synthétique
}

extension DemSourceLabel on DemSource {
  String get label {
    switch (this) {
      case DemSource.hgt:       return '🗻 HGT SRTM1 (30m)';
      case DemSource.openMeteo: return '🛰 Open-Meteo (±400m)';
      case DemSource.demo:      return '⚠ Terrain synthétique';
    }
  }
}

/// Résultat d'une sélection DEM.
class DemSelection {
  final ElevationProvider provider;
  final DemSource source;
  const DemSelection({required this.provider, required this.source});
}

/// Sélectionne et précharge un DEM autour de [center].
/// [prefetchSw], [prefetchNe] définissent la zone à précharger.
///
/// [previous] et [previousCenter] permettent de réutiliser le DEM précédent
/// si on n'a pas trop bougé (économie de prefetch).
class DemSelector {
  static Future<DemSelection> select({
    required LatLng center,
    required LatLng prefetchSw,
    required LatLng prefetchNe,
    ElevationProvider? previous,
    LatLng? previousCenter,
    DemSource? previousSource,
  }) async {
    // 1. HGT local
    final hgtOk = await HgtElevationProvider.isAvailable(
        center.latitude, center.longitude);
    if (hgtOk) {
      final hgt = HgtElevationProvider();
      await hgt.prefetch(prefetchSw, prefetchNe);
      debugPrint('DEM: HGT local OK');
      return DemSelection(provider: hgt, source: DemSource.hgt);
    }

    // 2. Cache réutilisable (centre dans la même zone)
    if (previous != null && previousCenter != null) {
      final dLat = (previousCenter.latitude  - center.latitude ).abs();
      final dLng = (previousCenter.longitude - center.longitude).abs();
      if (dLat < 0.005 && dLng < 0.005) {
        debugPrint('DEM: cache précédent réutilisé');
        return DemSelection(
          provider: previous,
          source: previousSource ?? DemSource.openMeteo,
        );
      }
    }

    // 3. Open-Meteo
    try {
      final om = OpenMeteoElevationProvider();
      await om.prefetch(prefetchSw, prefetchNe);
      debugPrint('DEM: Open-Meteo OK — ${om.debugInfo}');
      return DemSelection(provider: om, source: DemSource.openMeteo);
    } catch (e) {
      debugPrint('DEM: fallback synthétique ($e)');
    }

    // 4. Demo (dernier recours)
    final demo = DemoElevationProvider(
      originLat: center.latitude,
      originLng: center.longitude,
    );
    return DemSelection(provider: demo, source: DemSource.demo);
  }
}
