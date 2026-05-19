// lib/modules/ideas/models/idea.dart
//
// Modèle d'une idée d'itinéraire retournée par /ideas du backend FastAPI.
// Reflète directement le schéma Pydantic `Idea` côté Python.

import 'package:latlong2/latlong.dart';

class MeteoSummary {
  final String icon;
  final double meanTemp;
  final double totalSnow;
  final double maxWind;
  final double totalPrecip;

  const MeteoSummary({
    required this.icon,
    required this.meanTemp,
    required this.totalSnow,
    required this.maxWind,
    required this.totalPrecip,
  });

  factory MeteoSummary.fromJson(Map<String, dynamic> j) => MeteoSummary(
        icon: (j['icon'] as String?) ?? '⛅',
        meanTemp:    (j['mean_temp']    as num).toDouble(),
        totalSnow:   (j['total_snow']   as num).toDouble(),
        maxWind:     (j['max_wind']     as num).toDouble(),
        totalPrecip: (j['total_precip'] as num).toDouble(),
      );
}

class BeraSummary {
  final int? risque;
  final String? risqueColor;
  const BeraSummary({this.risque, this.risqueColor});

  factory BeraSummary.fromJson(Map<String, dynamic> j) => BeraSummary(
        risque:      (j['risque']        as num?)?.toInt(),
        risqueColor:  j['risque_color']  as String?,
      );
}

/// Détails du scoring IA (visible dans l'expander de la card).
class FeaturesDetail {
  final double tempMin7d;
  final double tempMax7d;
  final double tempAmp7d;
  final double snowfall7d;
  final double windMax7d;
  final int    freezeThawCycles7d;
  final double springScore;
  final double baseScore;

  const FeaturesDetail({
    required this.tempMin7d,
    required this.tempMax7d,
    required this.tempAmp7d,
    required this.snowfall7d,
    required this.windMax7d,
    required this.freezeThawCycles7d,
    required this.springScore,
    required this.baseScore,
  });

  factory FeaturesDetail.fromJson(Map<String, dynamic> j) => FeaturesDetail(
        tempMin7d:    (j['temp_min_7d_avg'] as num).toDouble(),
        tempMax7d:    (j['temp_max_7d_avg'] as num).toDouble(),
        tempAmp7d:    (j['temp_amp_7d_avg'] as num).toDouble(),
        snowfall7d:   (j['snowfall_7d_sum'] as num).toDouble(),
        windMax7d:    (j['wind_max_7d']      as num).toDouble(),
        freezeThawCycles7d: (j['freeze_thaw_cycles_7d'] as num).toInt(),
        springScore:  (j['spring_score']    as num).toDouble(),
        baseScore:    (j['base_score']      as num).toDouble(),
      );
}

/// Une idée d'itinéraire.
class Idea {
  final String name;
  final String massif;
  final double lat;
  final double lon;
  final double denivelePositif;
  final String exposition;
  final String difficulty;
  final String? url;
  final String? source;
  final double score;

  // Score IA (optionnel selon include_ai)
  final double? aiSnowScore;
  final double? aiNote10;
  final String? aiQualite;
  final String? aiPicto;
  final String? aiColor;
  final String? aiSaisonMode;

  final MeteoSummary meteo;
  final BeraSummary  bera;
  final FeaturesDetail? featuresDetail;

  const Idea({
    required this.name,
    required this.massif,
    required this.lat,
    required this.lon,
    required this.denivelePositif,
    required this.exposition,
    required this.difficulty,
    this.url,
    this.source,
    required this.score,
    this.aiSnowScore,
    this.aiNote10,
    this.aiQualite,
    this.aiPicto,
    this.aiColor,
    this.aiSaisonMode,
    required this.meteo,
    required this.bera,
    this.featuresDetail,
  });

  LatLng get latLng => LatLng(lat, lon);

  factory Idea.fromJson(Map<String, dynamic> j) => Idea(
        name:       j['name']   as String,
        massif:     j['massif'] as String,
        lat:        (j['lat'] as num).toDouble(),
        lon:        (j['lon'] as num).toDouble(),
        denivelePositif: (j['denivele_positif'] as num).toDouble(),
        exposition: j['exposition']      as String,
        difficulty: j['difficulty_ski']  as String,
        url:        j['url']    as String?,
        source:     j['source'] as String?,
        score:      (j['score'] as num).toDouble(),
        aiSnowScore: (j['ai_snow_score'] as num?)?.toDouble(),
        aiNote10:    (j['ai_note_10']    as num?)?.toDouble(),
        aiQualite:   j['ai_qualite']     as String?,
        aiPicto:     j['ai_picto']       as String?,
        aiColor:     j['ai_color']       as String?,
        aiSaisonMode:j['ai_saison_mode'] as String?,
        meteo: MeteoSummary.fromJson(j['meteo'] as Map<String, dynamic>),
        bera:  BeraSummary .fromJson(j['bera']  as Map<String, dynamic>),
        featuresDetail: j['features_detail'] == null
            ? null
            : FeaturesDetail.fromJson(j['features_detail'] as Map<String, dynamic>),
      );
}
