// lib/core/module_navigator.dart
//
// Permet à un module d'en demander un autre (switch). Utile pour le module
// Idées qui propose "Calculer le temps" ou "Voir conditions" depuis une card
// d'itinéraire — derrière, on bascule vers le module concerné en pré-paramé-
// trant son controller.
//
// Pattern : singleton avec un ValueNotifier que le shell WSShell écoute. Les
// "intentions de switch" (avec payload optionnel) sont propagées via methods.

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'module_registry.dart';

class ModuleNavigator {
  static final ModuleNavigator _instance = ModuleNavigator._();
  factory ModuleNavigator() => _instance;
  ModuleNavigator._();

  /// Le shell écoute ce notifier pour switcher la bottom bar. Un nouveau
  /// événement = nouvelle intention de switch (même module = re-set).
  final ValueNotifier<ModuleId?> requestedModule = ValueNotifier(null);

  /// Quand on demande à passer au module Temps avec une destination
  /// pré-remplie, on stocke ici la cible. Le TimeController la lira à son
  /// prochain rebuild via `pendingTimeTarget` et reset.
  LatLng? _pendingTimeTarget;
  LatLng? get pendingTimeTarget {
    final t = _pendingTimeTarget;
    _pendingTimeTarget = null;
    return t;
  }

  /// Pareil pour Conditions : bbox pré-remplie à fetcher au switch.
  ({LatLng sw, LatLng ne})? _pendingConditionsBbox;
  ({LatLng sw, LatLng ne})? get pendingConditionsBbox {
    final b = _pendingConditionsBbox;
    _pendingConditionsBbox = null;
    return b;
  }

  /// Demande de bascule vers le module Temps avec calcul vers `target`.
  void switchToTimeWithTarget(LatLng target) {
    _pendingTimeTarget = target;
    requestedModule.value = ModuleId.time;
  }

  /// Demande de bascule vers Conditions avec fetch sur la bbox.
  /// Typiquement appelée avec une bbox de quelques km autour d'un sommet.
  void switchToConditionsWithBbox(LatLng sw, LatLng ne) {
    _pendingConditionsBbox = (sw: sw, ne: ne);
    requestedModule.value = ModuleId.conditions;
  }

  /// Switch simple sans payload.
  void switchTo(ModuleId id) {
    requestedModule.value = id;
  }
}
