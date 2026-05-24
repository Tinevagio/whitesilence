// lib/core/theme/snow_palette.dart
//
// PALETTE UNIFIÉE des types de neige de WhiteSilence.
//
// Source unique de vérité pour les couleurs ET le vocabulaire des types
// de neige, utilisée par :
//   - Le module Conditions (codes physiques du backend : POWDER_COLD,
//     SPRING_SNOW, etc.)
//   - Le module Obs / Community (vocabulaire utilisateur : poudre,
//     moquette, ventée, etc.)
//
// Pourquoi un fichier dédié : avant ce refactor, chaque module définissait
// ses propres couleurs (rouge pour la croûte côté Conditions, ambre côté
// Obs ; bleu poudre côté Conditions, vert poudre côté Obs). Les utilisateurs
// voyaient des couleurs différentes pour la même neige selon le module
// consulté. Maintenant tout est aligné via SnowFamily.
//
// Architecture :
//   1. SnowFamily : enum des 9 familles canoniques
//   2. SnowPalette.colorFor(family) : la couleur de référence
//   3. familyFromConditionCode(code) : mapping backend → famille
//   4. familyFromUserType(type)      : mapping vocabulaire user → famille
//   5. Wrappers de commodité : colorForConditionCode(), colorForUserType()
//
// Pour modifier une couleur, NE PAS toucher aux fichiers consommateurs.
// Modifier la constante dans `_kColors` ci-dessous : tous les modules
// reprennent la nouvelle valeur automatiquement.

import 'package:flutter/material.dart';

/// Les 9 familles canoniques de neige reconnues par WhiteSilence.
///
/// Les modules backend (Conditions) et les modules utilisateur (Obs/Community)
/// mappent leurs propres codes/vocabulaires vers ces familles. C'est CETTE
/// énumération qui pilote la couleur affichée sur la carte.
enum SnowFamily {
  /// Poudre froide, -3°C ou moins. La meilleure neige.
  powderCold,

  /// Poudre légèrement réchauffée, -3°C à +1°C. Reste skiante mais évolue vite.
  powderWarm,

  /// Moquette / neige de printemps / transformée. Soleil + cycles gel/dégel.
  spring,

  /// Croûte de regel ou béton de surface. Difficile à skier sans être dangereux.
  crust,

  /// Neige soufflée / ventée. Surface alvéolée, attention plaques à vent.
  windAffected,

  /// Neige humide lourde. Soggy, fatigante, parfois dangereuse en grosse pente.
  wetHeavy,

  /// Neige ancienne tassée, peu d'information sur sa qualité.
  oldPacked,

  /// Zone de purge. Débris d'avalanche / coulée.
  purge,

  /// Indéterminé ou non reconnu (ex: "autre" dans une observation).
  undefined,
}

/// Palette unifiée WhiteSilence — point d'entrée pour toutes les couleurs
/// et labels relatifs aux types de neige.
class SnowPalette {
  SnowPalette._();

  // ─── La palette canonique ────────────────────────────────────────────────
  //
  // Une seule source de vérité. Si tu veux modifier une couleur, c'est ici
  // et nulle part ailleurs.
  static const Map<SnowFamily, Color> _kColors = {
    SnowFamily.powderCold:   Color(0xFF1F5BA3), // bleu marine
    SnowFamily.powderWarm:   Color(0xFF5CA0DE), // bleu clair
    SnowFamily.spring:       Color(0xFFE5933E), // orange chaud (soleil de printemps)
    SnowFamily.crust:        Color(0xFFB89968), // beige sable (neige transformée naturelle)
    SnowFamily.windAffected: Color(0xFF7A8A92), // gris-bleu vent
    SnowFamily.wetHeavy:     Color(0xFF8B572A), // brun (soggy, eau dans la neige)
    SnowFamily.oldPacked:    Color(0xFFB0C8D8), // bleu très pâle
    SnowFamily.purge:        Color(0xFF564C42), // brun-gris foncé (débris)
    SnowFamily.undefined:    Color(0xFFB4B2A9), // gris neutre
  };

  // ─── Les labels en français ──────────────────────────────────────────────
  static const Map<SnowFamily, String> _kLabels = {
    SnowFamily.powderCold:   'Poudre froide',
    SnowFamily.powderWarm:   'Poudre réchauffée',
    SnowFamily.spring:       'Neige de printemps',
    SnowFamily.crust:        'Croûte de regel',
    SnowFamily.windAffected: 'Neige soufflée',
    SnowFamily.wetHeavy:     'Neige humide lourde',
    SnowFamily.oldPacked:    'Neige ancienne',
    SnowFamily.purge:        'Zone de purge',
    SnowFamily.undefined:    'Indéterminé',
  };

  // ─── Accesseurs publics ──────────────────────────────────────────────────

  /// Couleur de référence pour une famille. Jamais null.
  static Color colorFor(SnowFamily f) => _kColors[f] ?? _kColors[SnowFamily.undefined]!;

  /// Libellé FR pour une famille.
  static String labelFor(SnowFamily f) => _kLabels[f] ?? 'Indéterminé';

  // ─── Mapping depuis le code Conditions (backend) ────────────────────────
  //
  // Reflet exact des constantes de `condition_code.dart`. À synchroniser si
  // le backend ajoute de nouveaux codes.
  static SnowFamily familyFromConditionCode(String? code) {
    switch (code) {
      case 'POWDER_COLD':   return SnowFamily.powderCold;
      case 'POWDER_WARM':   return SnowFamily.powderWarm;
      case 'SPRING_SNOW':   return SnowFamily.spring;
      case 'CRUST_MORNING': return SnowFamily.crust;
      case 'WET_HEAVY':     return SnowFamily.wetHeavy;
      case 'WIND_AFFECTED': return SnowFamily.windAffected;
      case 'OLD_PACKED':    return SnowFamily.oldPacked;
      case 'UNDEFINED':
      case null:
      default:              return SnowFamily.undefined;
    }
  }

  // ─── Mapping depuis le vocabulaire utilisateur (Obs) ────────────────────
  //
  // Reflet du vocabulaire `SnowTypes` du module snow. Plusieurs termes
  // peuvent retomber sur la même famille (ex: 'transfo' et 'moquette' →
  // SPRING). On accepte avec et sans accents pour robustesse face aux
  // transcriptions IA.
  static SnowFamily familyFromUserType(String? type) {
    if (type == null) return SnowFamily.undefined;
    final t = type.toLowerCase().trim();
    switch (t) {
      case 'poudre':                  return SnowFamily.powderCold;
      case 'moquette':
      case 'transfo':                 return SnowFamily.spring;
      case 'béton':
      case 'beton':
      case 'croûte':
      case 'croute':                  return SnowFamily.crust;
      case 'ventée':
      case 'ventee':                  return SnowFamily.windAffected;
      case 'humide':
      case 'lourde':                  return SnowFamily.wetHeavy;
      case 'purge':                   return SnowFamily.purge;
      case 'autre':
      default:                        return SnowFamily.undefined;
    }
  }

  // ─── Wrappers de commodité ──────────────────────────────────────────────
  // Pratique pour les call sites qui ne veulent pas se soucier de SnowFamily.

  /// Couleur pour un code Conditions backend (POWDER_COLD, SPRING_SNOW...).
  static Color colorForConditionCode(String? code) =>
      colorFor(familyFromConditionCode(code));

  /// Couleur pour un vocabulaire utilisateur (poudre, moquette, ventée...).
  static Color colorForUserType(String? userType) =>
      colorFor(familyFromUserType(userType));
}
