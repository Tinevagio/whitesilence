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
