// lib/modules/conditions/models/condition_code.dart
//
// Codes de conditions de neige retournés par l'API Névé.
// Aligné sur `SnowConditionEnum` côté backend (cf. api/main.py).
//
// On garde tous les codes même si pour l'instant le README en mentionne 5.
// La liste serveur en a 8 — on les supporte tous.

import 'package:flutter/material.dart';
import '../../../core/theme/colors.dart';

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

/// Métadonnées d'affichage : label FR + couleur (palette WhiteSilence).
/// Si l'API renvoie un code inconnu, le getter [meta] retourne UNDEFINED.
class ConditionMeta {
  final String code;
  final String label;
  final Color color;
  const ConditionMeta._(this.code, this.label, this.color);

  static const _table = <String, ConditionMeta>{
    SnowConditionCode.powderCold:
        ConditionMeta._(SnowConditionCode.powderCold,   'Poudre froide',       WSColors.glacierBlue),
    SnowConditionCode.powderWarm:
        ConditionMeta._(SnowConditionCode.powderWarm,   'Poudre réchauffée',   WSColors.glacierBlueLight),
    SnowConditionCode.springSnow:
        ConditionMeta._(SnowConditionCode.springSnow,   'Neige de printemps',  WSColors.sunOrange),
    SnowConditionCode.crustMorning:
        ConditionMeta._(SnowConditionCode.crustMorning, 'Croûte de regel',     WSColors.avalancheRed),
    SnowConditionCode.wetHeavy:
        ConditionMeta._(SnowConditionCode.wetHeavy,     'Neige humide lourde', Color(0xFF8B572A)),
    SnowConditionCode.windAffected:
        ConditionMeta._(SnowConditionCode.windAffected, 'Neige soufflée',      WSColors.stoneGray),
    SnowConditionCode.oldPacked:
        ConditionMeta._(SnowConditionCode.oldPacked,    'Neige ancienne',      Color(0xFFB8D4F0)),
    SnowConditionCode.undefined:
        ConditionMeta._(SnowConditionCode.undefined,    'Indéterminé',         WSColors.glacierMid),
  };

  static ConditionMeta forCode(String? code) {
    if (code == null) return _table[SnowConditionCode.undefined]!;
    return _table[code] ?? _table[SnowConditionCode.undefined]!;
  }
}
