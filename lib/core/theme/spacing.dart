/// Tokens d'espacement WhiteSilence
/// Échelle basée sur 4px pour une rythmique propre.
class WSSpacing {
  WSSpacing._();

  static const double xs   = 4.0;
  static const double sm   = 8.0;
  static const double md   = 12.0;
  static const double lg   = 16.0;
  static const double xl   = 24.0;
  static const double xxl  = 32.0;
  static const double xxxl = 48.0;
}

class WSRadius {
  WSRadius._();

  static const double sm = 6.0;
  static const double md = 10.0;
  static const double lg = 14.0;
  static const double xl = 20.0;
  static const double pill = 999.0;
}

/// Tailles tactiles pensées pour l'utilisation avec gants.
///
/// Material Design recommande 48dp minimum pour un tap doigt nu ; on monte
/// significativement au-dessus parce que la précision tactile avec gants
/// (même tactiles) est dégradée. Mieux vaut un bouton trop gros qu'un tap
/// qui rate en condition réelle au sommet.
///
/// Référence : tous ces tokens sont en dp (logical pixels Flutter). On ne
/// les exprime PAS en proportion d'écran pour garder une cible tactile
/// physique constante quel que soit le format du téléphone.
class WSTouch {
  WSTouch._();

  /// Bouton "principal" d'une vue (CTA majeur : "Calculer", "Activer",
  /// "Ouvrir"). Plein largeur de l'action panel, hauteur généreuse.
  static const double primaryHeight = 56.0;

  /// IconButton standard (refresh, settings, supprimer, etc.).
  /// Bien plus grand que les 40dp Material par défaut.
  static const double iconButton = 56.0;

  /// Bouton micro / FAB principal — gros, central, impossible à rater.
  static const double bigAction = 80.0;

  /// Taille d'une icône dans un IconButton (proportion ~40% du conteneur).
  static const double iconSize = 24.0;

  /// Bottom bar : hauteur totale (sans le safe area du bas).
  /// Chaque cellule mesure largeur_écran / N modules, hauteur = bottomBarHeight.
  static const double bottomBarHeight = 76.0;

  /// Icône dans la bottom bar.
  static const double bottomBarIcon = 26.0;

  /// Chip de filtre (multi-select dans Obs, par exemple). Hauteur cliquable.
  static const double chip = 44.0;

  /// Cible interactive minimale absolue (jamais en dessous).
  /// Utilisée par les widgets qui veulent vérifier qu'ils respectent
  /// l'accessibilité gants.
  static const double minTarget = 48.0;

  /// Espacement minimum entre deux cibles tactiles voisines.
  /// Évite les taps fantômes sur le mauvais bouton.
  static const double gap = 12.0;
}

