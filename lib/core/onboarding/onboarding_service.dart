// lib/core/onboarding/onboarding_service.dart
//
// Gestion de l'état "onboarding vu / pas vu" en SharedPreferences.
// L'onboarding s'affiche à la 1ère exécution (clean install) et après un
// "Réinitialiser l'onboarding" depuis les Réglages.
//
// On versionne via `kCurrentVersion` : si on enrichit l'onboarding plus tard
// (nouveau module à présenter, etc.), bump le numéro pour que les anciens
// utilisateurs le revoient une fois.

import 'package:shared_preferences/shared_preferences.dart';

class OnboardingService {
  static final OnboardingService _i = OnboardingService._();
  factory OnboardingService() => _i;
  OnboardingService._();

  /// Version courante de l'onboarding. Bump cette constante quand le contenu
  /// change suffisamment pour mériter une re-présentation aux utilisateurs
  /// existants. Optionnel — ne pas bumper si c'est juste cosmétique.
  static const int kCurrentVersion = 1;

  static const _kSeenVersionKey = 'onboarding.seen_version';

  /// L'utilisateur a-t-il déjà vu la version courante de l'onboarding ?
  Future<bool> hasSeenCurrent() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getInt(_kSeenVersionKey) ?? 0;
    return seen >= kCurrentVersion;
  }

  /// Marque l'onboarding comme vu pour la version courante.
  Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSeenVersionKey, kCurrentVersion);
  }

  /// Réinitialise — utile pour le bouton "Revoir l'onboarding" dans Réglages.
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSeenVersionKey);
  }
}
