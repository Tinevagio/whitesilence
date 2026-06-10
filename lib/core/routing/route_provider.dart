// lib/core/routing/route_provider.dart
//
// Contrat des fournisseurs de routage pour WhiteSilence.
//
// Même philosophie que `ElevationProvider` : une abstraction, des
// implémentations interchangeables. Pour l'instant une seule —
// `OfflineRouteProvider` (graphe OSM préprocessé, tuiles .wsr locales).
//
// Le provider ne renvoie QUE le tracé géométrique + sa distance. Le calcul
// du dénivelé (HgtElevationProvider) et du temps (MunterEngine) se fait
// ensuite dans `RouteEnricher`, pour réutiliser les moteurs existants.

import 'package:latlong2/latlong.dart';

import '../../shared/settings/user_profile.dart';

// ─── Catégories de chemin ─────────────────────────────────────────────────────
//
// Encodées sur 1 octet dans les tuiles .wsr (cf. build_graph.py). L'ordre
// DOIT rester synchronisé avec le préprocesseur Python.

enum WayCategory {
  path,    // 0 — sentier / footway / path / bridleway
  track,   // 1 — piste large / chemin carrossable
  skitour, // 2 — itinéraire ski de rando (piste:type=skitour)
  road,    // 3 — route ouverte (résidentielle, service…)
  steps,   // 4 — escaliers
  other,   // 5 — autre franchissable
}

WayCategory wayCategoryFromByte(int b) {
  if (b < 0 || b >= WayCategory.values.length) return WayCategory.other;
  return WayCategory.values[b];
}

// ─── Profil de routage ────────────────────────────────────────────────────────
//
// Un multiplicateur de coût par catégorie. `null` = catégorie interdite
// (l'arête est ignorée par l'A*). Plus le multiplicateur est bas, plus la
// catégorie est privilégiée.

class RouteProfile {
  final String name;
  final Map<WayCategory, double?> weights;

  const RouteProfile({required this.name, required this.weights});

  /// Multiplicateur d'une catégorie, ou `null` si interdite.
  double? weightOf(WayCategory c) => weights[c];

  /// Plus petit multiplicateur autorisé — sert d'heuristique admissible
  /// pour l'A* (on ne peut jamais aller plus vite que la meilleure catégorie).
  double get minWeight {
    double m = double.infinity;
    for (final w in weights.values) {
      if (w != null && w < m) m = w;
    }
    return m.isFinite ? m : 1.0;
  }

  // ── Profils prédéfinis ─────────────────────────────────────────────────────

  /// Randonnée / GR : on suit les sentiers, on tolère les pistes, on évite
  /// les routes. Les escaliers passent, les itinéraires ski sont marchables
  /// mais non prioritaires.
  static const RouteProfile hiking = RouteProfile(
    name: 'hiking',
    weights: {
      WayCategory.path:    1.0,
      WayCategory.track:   1.1,
      WayCategory.skitour: 1.3,
      WayCategory.road:    2.5,
      WayCategory.steps:   1.2,
      WayCategory.other:   1.6,
    },
  );

  /// Ski de rando : on privilégie les itinéraires balisés ski, puis les
  /// pistes larges. Les escaliers sont interdits (skis aux pieds…), les
  /// routes très pénalisées.
  static const RouteProfile skiTouring = RouteProfile(
    name: 'skiTouring',
    weights: {
      WayCategory.skitour: 1.0,
      WayCategory.track:   1.2,
      WayCategory.path:    1.4,
      WayCategory.road:    3.0,
      WayCategory.steps:   null, // interdit
      WayCategory.other:   2.0,
    },
  );

  /// Trail : proche de hiking mais on accepte un peu plus la route (liaisons).
  static const RouteProfile trail = RouteProfile(
    name: 'trail',
    weights: {
      WayCategory.path:    1.0,
      WayCategory.track:   1.05,
      WayCategory.skitour: 1.4,
      WayCategory.road:    1.8,
      WayCategory.steps:   1.1,
      WayCategory.other:   1.5,
    },
  );
}

/// Dérive le profil de routage depuis le profil utilisateur global.
RouteProfile routeProfileFrom(UserProfile profile) {
  switch (profile.activity) {
    case Activity.hiking:       return RouteProfile.hiking;
    case Activity.skiTouring:   return RouteProfile.skiTouring;
    case Activity.trailRunning: return RouteProfile.trail;
  }
}

// ─── Résultat ─────────────────────────────────────────────────────────────────

class RouteResult {
  /// Tracé complet, du point de départ snappé au point d'arrivée snappé.
  final List<LatLng> points;

  /// Distance le long du tracé, en mètres (somme des arêtes du graphe).
  final double distanceM;

  /// Distance de raccord entre le point tapé et le nœud du graphe le plus
  /// proche (départ + arrivée cumulés). Si élevé (> ~150 m), le tracé part
  /// de loin → l'UI peut prévenir l'utilisateur.
  final double snapDistanceM;

  const RouteResult({
    required this.points,
    required this.distanceM,
    required this.snapDistanceM,
  });
}

// ─── Contrat ──────────────────────────────────────────────────────────────────

abstract class RouteProvider {
  /// Calcule un tracé suivant le réseau de chemins entre [start] et [end]
  /// selon [profile]. Renvoie `null` si aucun chemin n'est trouvé (ou si la
  /// zone n'est pas couverte par des tuiles).
  Future<RouteResult?> route(LatLng start, LatLng end, RouteProfile profile);

  /// Indique si la zone autour de [point] dispose de données de routage.
  Future<bool> covers(LatLng point);
}
