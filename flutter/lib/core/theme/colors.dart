import 'package:flutter/material.dart';

/// Palette WhiteSilence — inspirée de la neige, de la glace et de la pierre.
/// Tons froids, désaturés, contrastes maîtrisés pour la lisibilité en plein soleil.
class WSColors {
  WSColors._();

  // Neutres — la base "neige" de l'app
  static const Color snowWhite     = Color(0xFFFAFCFE); // fond principal
  static const Color glacierLight  = Color(0xFFE8EEF2); // surfaces secondaires
  static const Color glacierMid    = Color(0xFFC9D3DA); // bordures, séparateurs
  static const Color stoneGray     = Color(0xFF5F6B75); // texte secondaire
  static const Color slateDark     = Color(0xFF2C3640); // texte principal
  static const Color obsidian      = Color(0xFF0A0E14); // fonds dark mode

  // Accents — utilisés avec parcimonie
  static const Color glacierBlue   = Color(0xFF185FA5); // accent principal, isochrones, position GPS
  static const Color glacierBlueLight = Color(0xFF378ADD);
  static const Color glacierBlueBg = Color(0xFFE6F1FB);

  // Sémantique
  static const Color avalancheRed  = Color(0xFFA32D2D); // cônes avalanche, danger
  static const Color avalancheRedLight = Color(0xFFE24B4A);
  static const Color avalancheRedBg= Color(0xFFFCEBEB);

  // Palette officielle BERA Météo France pour les niveaux de risque 1-5.
  // Reprise du frontend HTML d'origine (Front End V7.html) pour cohérence
  // visuelle entre les deux clients. À NE PAS modifier : c'est la palette
  // standard que les utilisateurs reconnaissent partout (BERA, MétéoFrance,
  // Skitour, etc.).
  static const Color bera1 = Color(0xFFFFFF00); // 1 — Faible (jaune)
  static const Color bera2 = Color(0xFFFFA500); // 2 — Limité (orange clair)
  static const Color bera3 = Color(0xFFFF6600); // 3 — Marqué (orange foncé)
  static const Color bera4 = Color(0xFFFF0000); // 4 — Fort (rouge)
  static const Color bera5 = Color(0xFF990000); // 5 — Très fort (rouge foncé)

  /// Retourne la couleur BERA pour un niveau de risque 1-5.
  /// Niveaux hors plage → bera3 (marqué) par défaut.
  static Color beraColor(int risque) {
    switch (risque) {
      case 1: return bera1;
      case 2: return bera2;
      case 3: return bera3;
      case 4: return bera4;
      case 5: return bera5;
      default: return bera3;
    }
  }

  /// Libellé textuel officiel pour un niveau BERA.
  static String beraLabel(int risque) {
    switch (risque) {
      case 1: return 'Faible';
      case 2: return 'Limité';
      case 3: return 'Marqué';
      case 4: return 'Fort';
      case 5: return 'Très fort';
      default: return 'Inconnu';
    }
  }

  static const Color powderGreen   = Color(0xFF1D9E75); // bonne neige, conditions OK
  static const Color powderGreenBg = Color(0xFFE1F5EE);

  static const Color sunOrange     = Color(0xFFBA7517); // moquette, soleil, warning soft
  static const Color sunOrangeBg   = Color(0xFFFAEEDA);

  // Couleurs des types de neige (alignées avec le module snow / Hey Snowy)
  // Le marqueur sur la carte prend cette couleur.
  static const Map<String, Color> snowTypeColors = {
    'poudre':   Color(0xFF1D9E75), // vert tendre — la bonne neige fraîche
    'moquette': Color(0xFF4CAF50), // vert printemps — moquette/transfo
    'transfo':  Color(0xFF4CAF50),
    'béton':    Color(0xFFF5A623), // ambre — neige dure/croûtée
    'croûte':   Color(0xFFF5A623),
    'ventée':   Color(0xFFE24B4A), // rouge vif — alerte plaque
    'lourde':   Color(0xFFFF8A65), // orange chaud
    'humide':   Color(0xFF378ADD), // bleu eau
    'purge':    Color(0xFF888780), // gris pierre
    'autre':    Color(0xFFB4B2A9), // gris neutre
  };

  /// Couleur pour un type de neige, avec fallback "autre" si non reconnu.
  static Color snowTypeColor(String? type) =>
      snowTypeColors[type] ?? snowTypeColors['autre']!;
}
