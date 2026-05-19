import 'package:flutter/material.dart';
import 'colors.dart';

/// Typographie WhiteSilence — épurée, lisible en montagne (luminosité, vibrations).
/// Une seule famille (système), deux poids (regular 400, medium 500).
class WSText {
  WSText._();

  // Display — utilisé pour le manifeste et l'onboarding
  static const TextStyle display = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w500,
    height: 1.25,
    color: WSColors.slateDark,
    letterSpacing: -0.5,
  );

  static const TextStyle title = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: WSColors.slateDark,
  );

  static const TextStyle heading = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: WSColors.slateDark,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: WSColors.slateDark,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: WSColors.stoneGray,
  );

  static const TextStyle micro = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    height: 1.2,
    color: WSColors.stoneGray,
    letterSpacing: 0.3,
  );

  // Chiffres mis en avant (temps, altitudes, distances)
  static const TextStyle numeric = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w500,
    height: 1.0,
    color: WSColors.slateDark,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle numericLarge = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.w500,
    height: 1.0,
    color: WSColors.slateDark,
    fontFeatures: [FontFeature.tabularFigures()],
    letterSpacing: -0.5,
  );
}
