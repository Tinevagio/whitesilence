// lib/modules/conditions/models/bera_full.dart
//
// Modèle BERA enrichi, parsé depuis le JSON public de Tinevagio/Ski-touring-live :
// https://raw.githubusercontent.com/Tinevagio/Ski-touring-live/main/data/bera_enneigement.json
//
// Contient TOUT ce qui est utile pour afficher un détail BERA complet :
// - identité (massif, département, zone, date du bulletin)
// - risque par tranche d'altitude (bas/haut + seuil)
// - pentes dangereuses par exposition
// - limites skiables N/S
// - hauteur de neige par altitude (N et S)
// - neige fraîche des 6 derniers jours
// - texte de qualité du manteau (paragraphe libre)
//
// À ne pas confondre avec `BeraInfo` (modèle léger renvoyé par le backend
// Render pour le détail point GPS).

import 'package:flutter/foundation.dart';

/// Hauteur de neige observée pour une altitude donnée, par exposition.
@immutable
class BeraSnowDepth {
  final int alti;
  final int? nCm;
  final int? sCm;

  const BeraSnowDepth({required this.alti, this.nCm, this.sCm});

  factory BeraSnowDepth.fromJson(Map<String, dynamic> j) => BeraSnowDepth(
        alti: (j['alti'] as num).toInt(),
        nCm:  (j['N_cm'] as num?)?.toInt(),
        sCm:  (j['S_cm'] as num?)?.toInt(),
      );
}

/// Neige fraîche tombée un jour donné (intervalle min-max cm).
@immutable
class BeraFreshSnow {
  final String date;  // "2026-05-24"
  final int? minCm;
  final int? maxCm;

  const BeraFreshSnow({required this.date, this.minCm, this.maxCm});

  factory BeraFreshSnow.fromJson(Map<String, dynamic> j) => BeraFreshSnow(
        date:  j['date'] as String,
        minCm: (j['min_cm'] as num?)?.toInt(),
        maxCm: (j['max_cm'] as num?)?.toInt(),
      );

  /// Valeur centrale "lisible" — moyenne min/max si les deux dispos.
  /// Renvoie 0 si rien (et pas null) pour faciliter l'affichage.
  int get centralCm {
    if (minCm == null && maxCm == null) return 0;
    if (minCm == null) return maxCm!;
    if (maxCm == null) return minCm!;
    return ((minCm! + maxCm!) / 2).round();
  }
}

/// Carte des expositions dangereuses (8 secteurs).
/// Source : bulletin Météo France, "pentes raides dangereuses" du jour.
@immutable
class DangerousAspects {
  final bool n;
  final bool ne;
  final bool e;
  final bool se;
  final bool s;
  final bool sw;
  final bool w;
  final bool nw;

  const DangerousAspects({
    required this.n,
    required this.ne,
    required this.e,
    required this.se,
    required this.s,
    required this.sw,
    required this.w,
    required this.nw,
  });

  factory DangerousAspects.fromJson(Map<String, dynamic> j) => DangerousAspects(
        n:  j['N']  as bool? ?? false,
        ne: j['NE'] as bool? ?? false,
        e:  j['E']  as bool? ?? false,
        se: j['SE'] as bool? ?? false,
        s:  j['S']  as bool? ?? false,
        sw: j['SW'] as bool? ?? false,
        w:  j['W']  as bool? ?? false,
        nw: j['NW'] as bool? ?? false,
      );

  bool get hasAny => n || ne || e || se || s || sw || w || nw;

  /// Liste des secteurs dangereux dans l'ordre cardinal, pour affichage.
  List<String> get dangerousList {
    final out = <String>[];
    if (n)  out.add('N');
    if (ne) out.add('NE');
    if (e)  out.add('E');
    if (se) out.add('SE');
    if (s)  out.add('S');
    if (sw) out.add('SO');
    if (w)  out.add('O');
    if (nw) out.add('NO');
    return out;
  }
}

/// Bulletin BERA complet d'un massif pour une date donnée.
@immutable
class BeraFull {
  final int       id;
  final String    massif;
  final String?   departement;
  final String?   zone;
  final String?   dateEnneigement;    // "2026-05-24"
  final int?      limiteNordM;
  final int?      limiteSudM;         // peut être -1 si "n/a"
  final List<BeraSnowDepth> enneigement;
  final int?      altiMesureFraicheM;
  final List<BeraFreshSnow> neigeFraiche;
  final String?   qualiteTexte;
  final int?      risqueAltitudeM;
  final int?      risqueBas;
  final int?      risqueHaut;
  final DangerousAspects pentesDangereuses;

  const BeraFull({
    required this.id,
    required this.massif,
    required this.enneigement,
    required this.neigeFraiche,
    required this.pentesDangereuses,
    this.departement,
    this.zone,
    this.dateEnneigement,
    this.limiteNordM,
    this.limiteSudM,
    this.altiMesureFraicheM,
    this.qualiteTexte,
    this.risqueAltitudeM,
    this.risqueBas,
    this.risqueHaut,
  });

  factory BeraFull.fromJson(Map<String, dynamic> j) {
    final enn = (j['enneigement'] as List?)
            ?.map((e) => BeraSnowDepth.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];
    final fresh = (j['neige_fraiche'] as List?)
            ?.map((e) => BeraFreshSnow.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];
    final pentes = j['pentes_dangereuses'] is Map
        ? DangerousAspects.fromJson(
            (j['pentes_dangereuses'] as Map).cast<String, dynamic>())
        : const DangerousAspects(
            n: false, ne: false, e: false, se: false,
            s: false, sw: false, w: false, nw: false);

    return BeraFull(
      id:                 (j['id'] as num).toInt(),
      massif:             j['massif'] as String,
      departement:        j['departement'] as String?,
      zone:               j['zone'] as String?,
      dateEnneigement:    j['date_enneigement'] as String?,
      limiteNordM:        (j['limite_nord_m'] as num?)?.toInt(),
      limiteSudM:         (j['limite_sud_m'] as num?)?.toInt(),
      enneigement:        enn,
      altiMesureFraicheM: (j['alti_mesure_fraiche'] as num?)?.toInt(),
      neigeFraiche:       fresh,
      qualiteTexte:       j['qualite_texte'] as String?,
      risqueAltitudeM:    (j['risque_altitude_m'] as num?)?.toInt(),
      risqueBas:          (j['risque_bas'] as num?)?.toInt(),
      risqueHaut:         (j['risque_haut'] as num?)?.toInt(),
      pentesDangereuses:  pentes,
    );
  }

  /// Vrai s'il y a deux niveaux de risque distincts (bas/haut avec seuil).
  bool get hasAltitudeSplit =>
      risqueHaut != null && risqueAltitudeM != null;

  /// Niveau "principal" — haut si dispo, sinon bas.
  int? get primaryRisk => risqueHaut ?? risqueBas;
}