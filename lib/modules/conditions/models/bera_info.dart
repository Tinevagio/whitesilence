// lib/modules/conditions/models/bera_info.dart
//
// Bulletin d'Estimation du Risque d'Avalanche (BERA) Météo France.
// Renvoyé par /conditions/point (champ `bera`) et /debug/bera.

class BeraSnowLevel {
  final int alti;
  final int? nCm;
  final int? sCm;

  const BeraSnowLevel({required this.alti, this.nCm, this.sCm});

  factory BeraSnowLevel.fromJson(Map<String, dynamic> j) => BeraSnowLevel(
        alti: (j['alti'] as num).toInt(),
        nCm:  (j['N_cm'] as num?)?.toInt(),
        sCm:  (j['S_cm'] as num?)?.toInt(),
      );
}

class BeraInfo {
  final String? massifName;
  final String? beraDate;
  final int?    limiteNordM;
  final int?    limiteSudM;
  final double? bera72hCm;
  final double? bera24hCm;
  final List<BeraSnowLevel>? enneigementNiveaux;

  /// Niveau de risque (présent dans /debug/bera mais pas garanti dans /conditions/point).
  /// On le parse en best-effort.
  final int?    risqueBas;
  final int?    risqueHaut;

  const BeraInfo({
    this.massifName,
    this.beraDate,
    this.limiteNordM,
    this.limiteSudM,
    this.bera72hCm,
    this.bera24hCm,
    this.enneigementNiveaux,
    this.risqueBas,
    this.risqueHaut,
  });

  factory BeraInfo.fromJson(Map<String, dynamic> j) {
    final niveaux = (j['enneigement_niveaux'] as List?)
        ?.map((e) => BeraSnowLevel.fromJson(e as Map<String, dynamic>))
        .toList();
    return BeraInfo(
      massifName:   j['massif_name'] as String?,
      beraDate:     j['bera_date'] as String?,
      limiteNordM:  (j['limite_nord_m'] as num?)?.toInt(),
      limiteSudM:   (j['limite_sud_m'] as num?)?.toInt(),
      bera72hCm:    (j['bera_72h_cm'] as num?)?.toDouble(),
      bera24hCm:    (j['bera_24h_cm'] as num?)?.toDouble(),
      enneigementNiveaux: niveaux,
      risqueBas:    (j['risque_bas'] as num?)?.toInt(),
      risqueHaut:   (j['risque_haut'] as num?)?.toInt(),
    );
  }

  /// Niveau de risque "affichable" — préfère haut puis bas, null si rien.
  int? get displayRisk => risqueHaut ?? risqueBas;

  /// Couleur du chip BERA selon le niveau.
  /// Échelle Météo France : 1=vert, 2=jaune, 3=orange, 4=rouge, 5=noir.
  static int riskLevelOrDefault(int? r) => r?.clamp(1, 5) ?? 0;

  // ── Interpolation d'épaisseur de neige ─────────────────────────────────
  //
  // Le BERA fournit la hauteur de neige à 3 paliers d'altitude (typiquement
  // 1500, 2000, 2500 m), séparément pour les versants Nord (N_cm) et Sud
  // (S_cm). On interpole linéairement entre ces paliers pour estimer la
  // hauteur à n'importe quelle altitude/exposition.
  //
  // Logique reprise du frontend Netlify (cf. Front End V7.html).
  //
  // Règles :
  //   - Si elevation < palier le plus bas → on extrapole linéairement vers 0
  //     (la limite skiable est généralement annoncée par le BERA via
  //      limite_nord_m / limite_sud_m, mais on reste cohérent avec le HTML).
  //   - Si elevation > palier le plus haut → on garde la valeur du dernier
  //     palier (on n'extrapole pas vers le haut, ça serait spéculatif).
  //   - Exposition : aspect 270°-90° (NW à NE) → Nord, sinon Sud.
  //     L'Est et l'Ouest sont des cas intermédiaires mais on tranche
  //     binaire comme le HTML pour rester fidèle.

  /// Estime l'épaisseur de neige en cm pour un point GPS donné.
  /// Retourne null si pas assez de données BERA (pas de niveaux).
  double? estimatedDepthCm(double elevationM, double aspectDeg) {
    final niveaux = enneigementNiveaux;
    if (niveaux == null || niveaux.isEmpty) return null;

    // Trier par altitude croissante par précaution (le BERA est normalement
    // déjà ordonné, mais on s'assure).
    final sorted = [...niveaux]..sort((a, b) => a.alti.compareTo(b.alti));

    final isNorthFacing = _isNorthFacing(aspectDeg);
    int? Function(BeraSnowLevel) getValue =
        isNorthFacing ? (n) => n.nCm : (n) => n.sCm;

    // Sous le palier le plus bas : extrapolation linéaire vers 0 à alti=0
    if (elevationM <= sorted.first.alti) {
      final v0 = getValue(sorted.first);
      if (v0 == null) return null;
      // Pente vers (0, 0) — borné à 0 minimum (sécurité)
      final ratio = elevationM / sorted.first.alti.toDouble();
      return (v0 * ratio).clamp(0.0, double.infinity);
    }

    // Au-dessus du palier le plus haut : on garde la valeur du sommet
    if (elevationM >= sorted.last.alti) {
      final v = getValue(sorted.last);
      return v?.toDouble();
    }

    // Cas standard : interpolation linéaire entre deux paliers adjacents
    for (var i = 0; i < sorted.length - 1; i++) {
      final low  = sorted[i];
      final high = sorted[i + 1];
      if (elevationM >= low.alti && elevationM <= high.alti) {
        final vLow  = getValue(low);
        final vHigh = getValue(high);
        if (vLow == null || vHigh == null) return null;
        final span = (high.alti - low.alti).toDouble();
        if (span <= 0) return vLow.toDouble(); // sécurité division par zéro
        final t = (elevationM - low.alti) / span;
        return vLow + (vHigh - vLow) * t;
      }
    }
    return null;
  }

  /// Versant Nord ? aspect en degrés où 0=N, 90=E, 180=S, 270=O.
  /// On considère Nord pour aspect ∈ [270°, 360°] ∪ [0°, 90°].
  static bool _isNorthFacing(double aspectDeg) {
    final a = aspectDeg % 360;
    return a <= 90 || a >= 270;
  }
}