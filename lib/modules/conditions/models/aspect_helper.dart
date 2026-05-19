// lib/modules/conditions/models/aspect_helper.dart
//
// Conversion aspect_deg → libellé d'exposition en français.
//
// PROBLÈME RÉSOLU :
// Le backend Névé calcule l'aspect avec `atan2(dz_dx, -dz_dy)` qui INVERSE
// l'axe Est/Ouest. Du coup, le champ `aspect_label` retourné par l'API est
// faux sur les expositions diagonales : ce qui est étiqueté "NE" est en
// réalité "NO", "E" est "O", etc.
//
// Le frontend Netlify corrige côté JS en redéfinissant la table.
// On fait pareil ici en Dart.
//
// Quand le backend sera corrigé proprement (signe dans le calcul d'aspect
// + regénération des .npz), il suffira de remplacer le contenu de
// `labelForAspectDeg` par `j['aspect_label']` direct. C'est documenté
// comme tâche dans le README backend.

/// Table corrigée : degrés (multiples de 45°) → libellé FR.
/// Identique à la table du frontend V7 ligne 1335.
const Map<int, String> _aspectLabels = {
  0:   'Nord',
  45:  'Nord-Ouest',
  90:  'Ouest',
  135: 'Sud-Ouest',
  180: 'Sud',
  225: 'Sud-Est',
  270: 'Est',
  315: 'Nord-Est',
  360: 'Nord', // boucle
};

/// Convertit un angle d'aspect (degrés, 0-360) en libellé d'exposition FR
/// avec la convention CORRIGÉE Est/Ouest.
///
/// Exemple : `labelForAspectDeg(280)` → "Est" (et non "Ouest").
String labelForAspectDeg(double? aspectDeg) {
  if (aspectDeg == null) return '—';
  // Arrondi au multiple de 45° le plus proche
  final rounded = (aspectDeg / 45).round() * 45;
  final normalized = rounded % 360;
  return _aspectLabels[normalized] ?? '—';
}

/// Version courte (1-2 lettres) pour les chips compacts.
/// Toujours selon la convention CORRIGÉE.
String shortLabelForAspectDeg(double? aspectDeg) {
  if (aspectDeg == null) return '—';
  final rounded = (aspectDeg / 45).round() * 45;
  final normalized = rounded % 360;
  switch (normalized) {
    case 0:   return 'N';
    case 45:  return 'NO';
    case 90:  return 'O';
    case 135: return 'SO';
    case 180: return 'S';
    case 225: return 'SE';
    case 270: return 'E';
    case 315: return 'NE';
    default:  return '—';
  }
}
