// lib/core/links.dart
//
// URLs externes utilisées dans l'app. Centralisées ici pour faciliter les
// mises à jour (changement de pseudo, ajout d'une plateforme de soutien, etc.).
//
// Convention : les constantes commencent par `k` pour signaler "compile-time
// constant" et faciliter la recherche.

/// Repo GitHub public de WhiteSilence.
const String kGitHubRepoUrl = 'https://github.com/Tinevagio/whitesilence';

/// Page Ko-fi (dons one-shot / récurrents, sans engagement).
const String kKofiUrl = 'https://ko-fi.com/Tinevagio';

/// Page GitHub Sponsors (dons récurrents, intégrés à GitHub).
const String kGitHubSponsorsUrl = 'https://github.com/sponsors/Tinevagio';

/// Politique de confidentialité hébergée sur GitHub Pages.
/// Utilisée par le Play Store (qui exige une URL externe accessible).
const String kPrivacyPolicyUrl =
    'https://tinevagio.github.io/whitesilence/privacy.html';

/// URL des issues GitHub (pour bouton "Reporter un bug" éventuel).
const String kGitHubIssuesUrl =
    'https://github.com/Tinevagio/whitesilence/issues';
