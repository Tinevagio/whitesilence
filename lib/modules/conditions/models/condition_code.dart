// lib/modules/conditions/models/condition_code.dart
//
// Codes de conditions de neige retournés par l'API Névé.
// Aligné sur `SnowConditionEnum` côté backend (cf. api/main.py).
//
// REFACTOR : les couleurs et labels ne sont plus stockés ici. Ils sont
// délégués à `SnowPalette` (cf. lib/core/theme/snow_palette.dart) pour
// que le module Conditions et le module Obs partagent une seule palette.

import 'package:flutter/material.dart';
import '../../../core/theme/snow_palette.dart';

/// Tous les codes possibles tels que retournés par l'API.
class SnowConditionCode {
  SnowConditionCode._();

  static const powderCold   = 'POWDER_COLD';
  static const powderWarm   = 'POWDER_WARM';
  static const springSnow   = 'SPRING_SNOW';
  static const crustMorning = 'CRUST_MORNING';
  static const wetHeavy     = 'WET_HEAVY';
  static const windAffected = 'WIND_AFFECTED';
  static const oldPacked    = 'OLD_PACKED';
  static const undefined    = 'UNDEFINED';

  static const all = [
    powderCold, powderWarm, springSnow, crustMorning,
    wetHeavy, windAffected, oldPacked, undefined,
  ];
}

/// Métadonnées d'affichage : label FR + couleur, dérivés de SnowPalette.
/// Garde l'API publique précédente (`ConditionMeta.forCode(code)`) pour
/// minimiser les changements dans les call sites.
class ConditionMeta {
  final String code;
  final String label;
  final Color color;
  const ConditionMeta._(this.code, this.label, this.color);

  /// Construit la meta à partir d'un code, en utilisant la palette unifiée.
  static ConditionMeta forCode(String? code) {
    final family = SnowPalette.familyFromConditionCode(code);
    return ConditionMeta._(
      code ?? SnowConditionCode.undefined,
      SnowPalette.labelFor(family),
      SnowPalette.colorFor(family),
    );
  }
}
