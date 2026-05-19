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
}
