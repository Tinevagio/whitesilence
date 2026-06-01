// lib/modules/conditions/models/avalanche_zone.dart
//
// Modèles pour les zones d'avalanche retournées par le backend Névé.
//
// L'endpoint /avalanche retourne un GeoJSON FeatureCollection avec :
//   - Points : zones de départ d'avalanche (centroïdes des pentes dangereuses)
//   - Polygons : cônes de propagation vers l'aval
//
// Notre modèle aplatit ça en deux listes typées plus pratiques à consommer
// côté Flutter.

import 'package:latlong2/latlong.dart';

/// Réponse de /avalanche.
class AvalancheResponse {
  /// Identifiant du massif concerné (ex: "Belledonne")
  final String? massifName;

  /// Niveau de risque BERA bas appliqué (1-5)
  final int risqueBas;

  /// Niveau de risque BERA haut appliqué (1-5), peut être null
  final int? risqueHaut;

  /// Zones de départ (points sur la carte)
  final List<AvalancheStartZone> startZones;

  /// Cônes de propagation (polygones)
  final List<AvalancheCone> cones;

  const AvalancheResponse({
    required this.massifName,
    required this.risqueBas,
    required this.risqueHaut,
    required this.startZones,
    required this.cones,
  });

  factory AvalancheResponse.fromJson(Map<String, dynamic> json) {
    final massif = json['massif'] as Map<String, dynamic>?;
    final features = (json['features'] as List<dynamic>?) ?? [];

    final starts = <AvalancheStartZone>[];
    final cones  = <AvalancheCone>[];

    for (final f in features) {
      final feat = f as Map<String, dynamic>;
      final geom = feat['geometry'] as Map<String, dynamic>?;
      final props = (feat['properties'] as Map<String, dynamic>?) ?? const {};

      if (geom == null) continue;
      final type = geom['type'] as String?;
      final coords = geom['coordinates'];

      if (type == 'Point' && coords is List && coords.length >= 2) {
        starts.add(AvalancheStartZone(
          point: LatLng(
            (coords[1] as num).toDouble(),
            (coords[0] as num).toDouble(),
          ),
          slope:    (props['slope_deg'] as num?)?.toDouble()
                  ?? (props['slope']    as num?)?.toDouble(),
          altitude: (props['elevation'] as num?)?.toDouble()
                  ?? (props['altitude'] as num?)?.toDouble(),
          aspect:    props['aspect']    as String?,
          severity: (props['severity']  as num?)?.toDouble(),
          risque:   (props['risque']    as num?)?.toInt() ?? 3,
        ));
      } else if (type == 'Polygon' && coords is List && coords.isNotEmpty) {
        final rawRing = (coords.first as List)
            .map((c) => LatLng(
                  (c[1] as num).toDouble(),
                  (c[0] as num).toDouble(),
                ))
            .toList();

        // ── Workaround orientation cônes ─────────────────────────────────
        // Si les cônes pointent vers l'amont au lieu de l'aval, passer
        // `_mirrorCones` à true ci-dessous. Inversement, si activé et que
        // les cônes pointent vers l'amont, le repasser à false.
        //
        // L'historique :
        //  - À une époque on appliquait un miroir car les cônes pointaient
        //    vers le haut. On supposait que le backend avait un bug
        //    `downslope = aspect + 180°`.
        //  - Mon hypothèse "ring.first = apex" pour le miroir était
        //    probablement fausse (le polygone est plus probablement fermé
        //    sur l'arc, pas sur l'apex).
        //  - On garde le toggle pour permettre une bascule rapide en cas
        //    d'évolution backend. Par défaut OFF : observation actuelle.
        final ring = _mirrorCones
            ? _mirrorRingAroundApex(rawRing)
            : rawRing;

        cones.add(AvalancheCone(
          ring:      ring,
          startLat:  (props['start_lat'] as num?)?.toDouble(),
          startLon:  (props['start_lon'] as num?)?.toDouble(),
          severity: (props['severity']   as num?)?.toDouble() ?? 0.5,
          risque:   (props['risque']     as num?)?.toInt() ?? 3,
        ));
      }
    }

    return AvalancheResponse(
      massifName: massif?['name'] as String?,
      risqueBas:  (massif?['risque_bas']  as num?)?.toInt() ?? 0,
      risqueHaut: (massif?['risque_haut'] as num?)?.toInt(),
      startZones: starts,
      cones:      cones,
    );
  }

  /// Toggle de débogage pour l'orientation des cônes.
  /// false = on fait confiance au backend (cônes affichés tels quels).
  /// true  = on applique une symétrie centrale autour du premier point du
  ///         polygone (workaround d'un bug supposé côté backend).
  static const bool _mirrorCones = true;

  /// Symétrie centrale du polygone autour de son premier point (l'apex
  /// supposé). Pour chaque point P, on calcule P' = 2*apex - P.
  /// Le premier et le dernier point (qui sont l'apex) restent identiques.
  /// Note : cette logique suppose que le polygone est fermé sur l'apex,
  /// ce qui n'est pas garanti par toutes les conventions de cônes.
  static List<LatLng> _mirrorRingAroundApex(List<LatLng> ring) {
    if (ring.length < 3) return ring;
    final apex = ring.first;
    return ring.map((p) {
      if (p == apex) return p;
      return LatLng(
        2 * apex.latitude  - p.latitude,
        2 * apex.longitude - p.longitude,
      );
    }).toList();
  }
}

/// Zone de départ d'avalanche — un point sur la carte avec ses caractéristiques.
class AvalancheStartZone {
  final LatLng point;
  final double? slope;     // pente en degrés
  final double? altitude;  // mètres
  final String? aspect;    // exposition "N", "NE", etc.
  final double? severity;  // 0-1, intensité du risque
  final int risque;        // niveau BERA 1-5 appliqué à cette zone
  const AvalancheStartZone({
    required this.point,
    this.slope,
    this.altitude,
    this.aspect,
    this.severity,
    required this.risque,
  });
}

/// Cône de propagation d'une avalanche — polygone sur la carte.
class AvalancheCone {
  /// Anneau extérieur du polygone
  final List<LatLng> ring;
  final double? startLat;
  final double? startLon;
  /// Sévérité 0-1 (modulation d'opacité du remplissage)
  final double severity;
  /// Niveau de risque BERA appliqué à ce cône (1-5).
  /// Pilote la couleur via la palette officielle Météo France.
  final int risque;
  const AvalancheCone({
    required this.ring,
    this.startLat,
    this.startLon,
    required this.severity,
    required this.risque,
  });
}
