// test/ideas_model_test.dart
//
// Tests unitaires pour le parsing JSON des modèles du module Idées.
// Aucune dépendance réseau — tout est construit à partir de JSON synthétique.
// Lancer : flutter test test/ideas_model_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:whitesilence/modules/ideas/models/idea.dart';

// ─── JSON de référence ────────────────────────────────────────────────────────

Map<String, dynamic> _baseIdeaJson({
  String name          = 'Couloir Nord',
  String massif        = 'Belledonne',
  double lat           = 45.1,
  double lon           = 6.0,
  double denivele      = 900,
  String exposition    = 'N',
  String difficulty    = 'BS',
  String? url,
  String? source,
  double score         = 0.78,
  double? aiSnowScore,
  double? aiNote10,
  String? aiQualite,
  String? aiPicto,
  String? aiColor,
  String? aiSaisonMode,
  Map<String, dynamic>? meteoOverride,
  Map<String, dynamic>? beraOverride,
  Map<String, dynamic>? featuresDetail,
}) =>
    {
      'name':             name,
      'massif':           massif,
      'lat':              lat,
      'lon':              lon,
      'denivele_positif': denivele,
      'exposition':       exposition,
      'difficulty_ski':   difficulty,
      'url':              url,
      'source':           source,
      'score':            score,
      'ai_snow_score':    aiSnowScore,
      'ai_note_10':       aiNote10,
      'ai_qualite':       aiQualite,
      'ai_picto':         aiPicto,
      'ai_color':         aiColor,
      'ai_saison_mode':   aiSaisonMode,
      'meteo':            meteoOverride ??
          {
            'icon':          '☀',
            'mean_temp':     -3.0,
            'total_snow':    5.0,
            'max_wind':      15.0,
            'total_precip':  0.0,
          },
      'bera': beraOverride ??
          {
            'risque':       2,
            'risque_color': 'yellow',
          },
      'features_detail': featuresDetail,
    };

Map<String, dynamic> _featuresDetailJson() => {
      'temp_min_7d_avg':        -5.0,
      'temp_max_7d_avg':         8.0,
      'temp_amp_7d_avg':        13.0,
      'snowfall_7d_sum':        30.0,
      'wind_max_7d':            20.0,
      'freeze_thaw_cycles_7d':   5,
      'spring_score':            0.85,
      'base_score':              0.72,
    };

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // Idea.fromJson
  // ═══════════════════════════════════════════════════════════════════════════

  group('Idea.fromJson — champs de base', () {
    test('round-trip : score conservé', () {
      final idea = Idea.fromJson(_baseIdeaJson(score: 0.78));
      expect(idea.score, closeTo(0.78, 0.001));
    });

    test('round-trip : coordonnées conservées', () {
      final idea = Idea.fromJson(_baseIdeaJson(lat: 45.123, lon: 6.456));
      expect(idea.lat, closeTo(45.123, 0.0001));
      expect(idea.lon, closeTo(6.456,  0.0001));
    });

    test('latLng getter cohérent avec lat/lon', () {
      final idea = Idea.fromJson(_baseIdeaJson(lat: 45.1, lon: 6.0));
      expect(idea.latLng.latitude,  idea.lat);
      expect(idea.latLng.longitude, idea.lon);
    });

    test('url null toléré', () {
      final idea = Idea.fromJson(_baseIdeaJson(url: null));
      expect(idea.url, isNull);
    });

    test('source null toléré', () {
      final idea = Idea.fromJson(_baseIdeaJson(source: null));
      expect(idea.source, isNull);
    });
  });

  group('Idea.fromJson — champs AI (optionnels)', () {
    test('sans AI : tous les champs AI sont null', () {
      final idea = Idea.fromJson(_baseIdeaJson());
      expect(idea.aiSnowScore,  isNull);
      expect(idea.aiNote10,     isNull);
      expect(idea.aiQualite,    isNull);
      expect(idea.aiPicto,      isNull);
      expect(idea.aiColor,      isNull);
      expect(idea.aiSaisonMode, isNull);
    });

    test('avec AI : aiNote10 conservé', () {
      final idea = Idea.fromJson(_baseIdeaJson(
        aiSnowScore:  0.82,
        aiNote10:     8.2,
        aiQualite:    'Très bonne',
        aiPicto:      '⭐',
        aiColor:      '#4CAF50',
        aiSaisonMode: 'spring',
      ));
      expect(idea.aiNote10,     closeTo(8.2, 0.001));
      expect(idea.aiSnowScore,  closeTo(0.82, 0.001));
      expect(idea.aiQualite,    'Très bonne');
      expect(idea.aiPicto,      '⭐');
      expect(idea.aiColor,      '#4CAF50');
      expect(idea.aiSaisonMode, 'spring');
    });
  });

  group('Idea.fromJson — MeteoSummary', () {
    test('valeurs météo conservées', () {
      final idea = Idea.fromJson(_baseIdeaJson(meteoOverride: {
        'icon':         '🌨',
        'mean_temp':    -8.5,
        'total_snow':   45.0,
        'max_wind':     60.0,
        'total_precip': 12.0,
      }));
      expect(idea.meteo.icon,        '🌨');
      expect(idea.meteo.meanTemp,    closeTo(-8.5, 0.01));
      expect(idea.meteo.totalSnow,   closeTo(45.0, 0.01));
      expect(idea.meteo.maxWind,     closeTo(60.0, 0.01));
      expect(idea.meteo.totalPrecip, closeTo(12.0, 0.01));
    });

    test('icon manquant → fallback ⛅', () {
      final idea = Idea.fromJson(_baseIdeaJson(meteoOverride: {
        'mean_temp': 0.0, 'total_snow': 0.0,
        'max_wind': 0.0, 'total_precip': 0.0,
        // 'icon' absent
      }));
      expect(idea.meteo.icon, '⛅');
    });
  });

  group('Idea.fromJson — BeraSummary', () {
    test('risque et couleur conservés', () {
      final idea = Idea.fromJson(_baseIdeaJson(beraOverride: {
        'risque': 3, 'risque_color': 'orange',
      }));
      expect(idea.bera.risque,      3);
      expect(idea.bera.risqueColor, 'orange');
    });

    test('risque null toléré (pas de données BERA)', () {
      final idea = Idea.fromJson(_baseIdeaJson(beraOverride: {
        'risque': null, 'risque_color': null,
      }));
      expect(idea.bera.risque,      isNull);
      expect(idea.bera.risqueColor, isNull);
    });
  });

  group('Idea.fromJson — FeaturesDetail', () {
    test('null quand absent', () {
      final idea = Idea.fromJson(_baseIdeaJson());
      expect(idea.featuresDetail, isNull);
    });

    test('parsé correctement quand présent', () {
      final idea = Idea.fromJson(
          _baseIdeaJson(featuresDetail: _featuresDetailJson()));

      expect(idea.featuresDetail, isNotNull);
      expect(idea.featuresDetail!.tempMin7d,         closeTo(-5.0, 0.01));
      expect(idea.featuresDetail!.tempMax7d,         closeTo( 8.0, 0.01));
      expect(idea.featuresDetail!.snowfall7d,        closeTo(30.0, 0.01));
      expect(idea.featuresDetail!.freezeThawCycles7d, 5);
      expect(idea.featuresDetail!.springScore,       closeTo(0.85, 0.001));
      expect(idea.featuresDetail!.baseScore,         closeTo(0.72, 0.001));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Cohérence du scoring
  // ═══════════════════════════════════════════════════════════════════════════

  group('Idea — cohérence du scoring', () {
    test('score dans [0, 1]', () {
      for (final s in [0.0, 0.5, 0.78, 1.0]) {
        final idea = Idea.fromJson(_baseIdeaJson(score: s));
        expect(idea.score, inInclusiveRange(0.0, 1.0));
      }
    });

    test('aiNote10 dans [0, 10] quand présent', () {
      for (final n in [0.0, 5.0, 8.2, 10.0]) {
        final idea = Idea.fromJson(_baseIdeaJson(aiNote10: n));
        expect(idea.aiNote10!, inInclusiveRange(0.0, 10.0));
      }
    });

    test('risque BERA dans [1, 5] quand présent', () {
      for (final r in [1, 2, 3, 4, 5]) {
        final idea = Idea.fromJson(_baseIdeaJson(
            beraOverride: {'risque': r, 'risque_color': 'x'}));
        expect(idea.bera.risque!, inInclusiveRange(1, 5));
      }
    });
  });
}
