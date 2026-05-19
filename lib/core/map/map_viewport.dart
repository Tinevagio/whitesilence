// lib/core/map/map_viewport.dart
//
// Singleton qui expose les bounds visibles de la WSMapScreen.
// La WSMapScreen le met à jour à chaque event de mouvement de carte.
// Les overlays/layers qui ont besoin de connaître la zone visible (pour
// fetcher de la donnée, afficher une couverture, etc.) s'y abonnent via le
// ValueListenable.
//
// Pourquoi : flutter_map ne permet pas facilement à un layer enfant de
// connaître les bounds courants. Un singleton observable contourne ça
// proprement.

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';

class MapViewport {
  static final MapViewport _instance = MapViewport._();
  factory MapViewport() => _instance;
  MapViewport._();

  /// Bounds visibles courants. Null avant que la carte n'ait été rendue.
  final ValueNotifier<LatLngBounds?> bounds = ValueNotifier(null);

  /// Zoom courant. Utile pour décider si on affiche une couche fine ou non.
  final ValueNotifier<double?> zoom = ValueNotifier(null);

  void update({required LatLngBounds bounds, required double zoom}) {
    this.bounds.value = bounds;
    this.zoom.value = zoom;
  }
}
