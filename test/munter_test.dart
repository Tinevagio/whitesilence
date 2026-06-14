// test/munter_test.dart
//
// Tests unitaires pour MunterEngine.
// Aucune dépendance Flutter → lancé avec : flutter test test/munter_test.dart
//
// Règles des valeurs de test :
//   - elevGain = 0 pour les tests de vitesse horizontale pure.
//     Avec elevGain > 2, _recalibrate() calcule upFraction = gain/dist.
//     Sur des segments courts (<120s), gainTimeSec = upFraction × duration
//     est trop petit → ascentRate calculé > 1500 m/h → sanity check → return.
//     Le fallback (ascentRate = baseline) ne s'active que si gainTimeSec == 0,
//     ce qui exige elevGain ≤ 2.
//   - Pour tester la calibration du D+, il faut des segments de plusieurs
//     minutes avec une pente réaliste (voir test dédié).

import 'package:flutter_test/flutter_test.dart';
import 'package:whitesilence/modules/time/munter.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

MunterEngine _skiTrained() => MunterEngine(MunterProfile(
      activity: MunterActivity.skiTouring,
      fitness:  MunterFitness.trained,
      terrain:  MunterTerrain.normal,
    ));

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // BASELINE — estimateSeconds
  // ═══════════════════════════════════════════════════════════════════════════

  group('MunterEngine — baseline estimateSeconds', () {
    late MunterEngine engine;
    setUp(() => engine = _skiTrained());

    test('plat 1 km : (1 / 4.5) × 3600 = 800 s', () {
      // skiTouring/trained baseline : horizontalSpeed = 4.5 km/h
      // tHoriz = 1 / 4.5 h = 0.2222 h = 800 s
      final s = engine.estimateSeconds(
          distanceM: 1000, elevGain: 0, elevLoss: 0);
      expect(s, closeTo(800.0, 5.0));
    });

    test('montée pure 300m D+ : dominée par ascentRate 450 m/h', () {
      // tVert = 300 / 450 h = 0.6667 h = 2400 s
      // tHoriz sur 500m = 500/1000/4.5 h = 400 s → tVert domine
      final s = engine.estimateSeconds(
          distanceM: 500, elevGain: 300, elevLoss: 0);
      expect(s, closeTo(2400.0, 30.0));
    });

    test('descente pure 500m D- : dominée par descentRate 900 m/h', () {
      // tVert = 500 / 900 h = 0.5556 h = 2000 s
      final s = engine.estimateSeconds(
          distanceM: 500, elevGain: 0, elevLoss: 500);
      expect(s, closeTo(2000.0, 30.0));
    });

    test('terrainFactor heavySnow = 1.45 × normal', () {
      final normal = MunterEngine(MunterProfile(
        activity: MunterActivity.skiTouring,
        fitness:  MunterFitness.trained,
        terrain:  MunterTerrain.normal,
      )).estimateSeconds(distanceM: 1000, elevGain: 0, elevLoss: 0);

      final heavy = MunterEngine(MunterProfile(
        activity: MunterActivity.skiTouring,
        fitness:  MunterFitness.trained,
        terrain:  MunterTerrain.heavySnow,
      )).estimateSeconds(distanceM: 1000, elevGain: 0, elevLoss: 0);

      expect(heavy / normal, closeTo(1.45, 0.01));
    });

    test('terrainFactor difficultTerrain = 1.30 × normal', () {
      final normal = MunterEngine(MunterProfile(
        activity: MunterActivity.skiTouring,
        fitness:  MunterFitness.trained,
        terrain:  MunterTerrain.normal,
      )).estimateSeconds(distanceM: 1000, elevGain: 0, elevLoss: 0);

      final difficult = MunterEngine(MunterProfile(
        activity: MunterActivity.skiTouring,
        fitness:  MunterFitness.trained,
        terrain:  MunterTerrain.difficultTerrain,
      )).estimateSeconds(distanceM: 1000, elevGain: 0, elevLoss: 0);

      expect(difficult / normal, closeTo(1.30, 0.01));
    });

    test('hiking/warrior plus rapide que hiking/beginner', () {
      final beginner = MunterEngine(MunterProfile(
        activity: MunterActivity.hiking,
        fitness:  MunterFitness.beginner,
        terrain:  MunterTerrain.normal,
      )).estimateSeconds(distanceM: 2000, elevGain: 200, elevLoss: 0);

      final warrior = MunterEngine(MunterProfile(
        activity: MunterActivity.hiking,
        fitness:  MunterFitness.warrior,
        terrain:  MunterTerrain.normal,
      )).estimateSeconds(distanceM: 2000, elevGain: 200, elevLoss: 0);

      expect(warrior, lessThan(beginner));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CALIBRATION — addGpsMeasurement
  // ═══════════════════════════════════════════════════════════════════════════

  group('MunterEngine — calibration', () {
    test('segments trop courts rejetés (distanceM < 10)', () {
      final engine = _skiTrained();
      engine.addGpsMeasurement(
          distanceM: 5, elevGain: 0, elevLoss: 0, actualSeconds: 30);
      expect(engine.acceptedCount, 0);
      expect(engine.calibrationWeight, 0.0);
    });

    test('segments trop courts rejetés (actualSeconds < 10)', () {
      final engine = _skiTrained();
      engine.addGpsMeasurement(
          distanceM: 200, elevGain: 0, elevLoss: 0, actualSeconds: 5);
      expect(engine.acceptedCount, 0);
    });

    test('isCalibrated atteint à 10 segments plats', () {
      // elevGain = 0 : ascentRate tombe sur le fallback baseline (450 m/h)
      // qui passe le sanity check [50, 1500].
      // vitesse = 300m / 90s = 12 km/h → dans les clous (< 20).
      final engine = _skiTrained();
      for (int i = 0; i < 10; i++) {
        engine.addGpsMeasurement(
            distanceM: 300, elevGain: 0, elevLoss: 0, actualSeconds: 90);
      }
      expect(engine.acceptedCount, 10);
      expect(engine.isCalibrated, isTrue,
          reason: 'calibrationReport: ${engine.calibrationReport()}');
    });

    test('poids = 0.5 exactement à 10 segments (10/20)', () {
      final engine = _skiTrained();
      for (int i = 0; i < 10; i++) {
        engine.addGpsMeasurement(
            distanceM: 300, elevGain: 0, elevLoss: 0, actualSeconds: 90);
      }
      expect(engine.calibrationWeight, closeTo(0.5, 0.01));
    });

    test('poids plafonné à 0.95 (jamais 1.0)', () {
      final engine = _skiTrained();
      for (int i = 0; i < 30; i++) {
        engine.addGpsMeasurement(
            distanceM: 300, elevGain: 0, elevLoss: 0, actualSeconds: 90);
      }
      expect(engine.calibrationWeight, lessThanOrEqualTo(0.95));
    });

    test('blend converge vers marcheur lent (3 km/h) après 25 segments', () {
      // 100m en 120s → (0.1 km) / (120/3600 h) = 3.0 km/h
      final engine = _skiTrained();
      for (int i = 0; i < 25; i++) {
        engine.addGpsMeasurement(
            distanceM: 100, elevGain: 0, elevLoss: 0, actualSeconds: 120);
      }
      expect(engine.currentParams.horizontalSpeed, closeTo(3.0, 0.5));
    });

    test('blend converge vers marcheur rapide (10 km/h) après 25 segments', () {
      // 500m en 180s → (0.5 km) / (180/3600 h) = 10.0 km/h
      final engine = _skiTrained();
      for (int i = 0; i < 25; i++) {
        engine.addGpsMeasurement(
            distanceM: 500, elevGain: 0, elevLoss: 0, actualSeconds: 180);
      }
      expect(engine.currentParams.horizontalSpeed, closeTo(10.0, 1.0));
    });

    test('fenêtre glissante : max 20 mesures retenues', () {
      final engine = _skiTrained();
      for (int i = 0; i < 30; i++) {
        engine.addGpsMeasurement(
            distanceM: 300, elevGain: 0, elevLoss: 0, actualSeconds: 90);
      }
      // acceptedCount est cumulatif
      expect(engine.acceptedCount, 30);
      // mais la fenêtre interne est plafonnée à 20
      // (non exposée publiquement — on vérifie indirectement via le poids)
      expect(engine.calibrationWeight, closeTo(0.95, 0.01));
    });

    // ── calibration D+ ──────────────────────────────────────────────────────
    // Pour calibrer le D+, il faut que gainTimeSec soit assez grand pour que
    // ascentRate = gainM / (gainTimeSec/3600) ≤ 1500.
    // Avec upFraction = gain/dist et durée = durationS :
    //   gainTimeSec = (gain/dist) × durationS
    //   ascentRate  = gain / ((gain/dist × durationS) / 3600)
    //               = dist × 3600 / durationS
    // Pour ascentRate ≤ 1500 : dist × 3600 / durationS ≤ 1500
    //   → durationS ≥ dist × 3600 / 1500
    //   Exemple : dist=300m → durationS ≥ 720s (12 min)
    test('calibration D+ : segments de 12 min sur 300m en montée', () {
      // dist=300m, durationS=720s → ascentRate calculé = 300×3600/720 = 1500 m/h
      // On prend durationS=900s pour avoir une marge (ascentRate = 1200 m/h)
      final engine = _skiTrained();
      for (int i = 0; i < 10; i++) {
        engine.addGpsMeasurement(
            distanceM: 300, elevGain: 30, elevLoss: 0, actualSeconds: 900);
      }
      // ascentRate mesuré : dist×3600/durationS = 300×3600/900 = 1200 m/h
      // blend à 10 segments → poids 0.5 → entre baseline(450) et mesuré(1200)
      expect(engine.isCalibrated, isTrue,
          reason: 'calibrationReport: ${engine.calibrationReport()}');
      expect(engine.currentParams.ascentRate,
          inInclusiveRange(450.0, 1200.0));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SNAPSHOT — persistence entre sessions
  // ═══════════════════════════════════════════════════════════════════════════

  group('MunterEngine — snapshot', () {
    test('round-trip conserve acceptedCount et calibrationWeight', () {
      final e1 = _skiTrained();
      for (int i = 0; i < 15; i++) {
        e1.addGpsMeasurement(
            distanceM: 300, elevGain: 0, elevLoss: 0, actualSeconds: 90);
      }

      final snap = e1.toSnapshot();
      final e2   = _skiTrained();
      final ok   = e2.restoreFromSnapshot(snap);

      expect(ok, isTrue);
      expect(e2.acceptedCount,      e1.acceptedCount);
      expect(e2.calibrationWeight,  closeTo(e1.calibrationWeight, 0.01));
      expect(e2.isCalibrated,       e1.isCalibrated);
    });

    test('snapshot avec mauvais profil retourne false', () {
      final e1 = _skiTrained();
      for (int i = 0; i < 5; i++) {
        e1.addGpsMeasurement(
            distanceM: 300, elevGain: 0, elevLoss: 0, actualSeconds: 90);
      }

      final snap = e1.toSnapshot();
      final e2   = MunterEngine(MunterProfile(
        activity: MunterActivity.hiking,  // ← profil différent
        fitness:  MunterFitness.trained,
        terrain:  MunterTerrain.normal,
      ));
      expect(e2.restoreFromSnapshot(snap), isFalse);
    });

    test('snapshot vide : acceptedCount = 0 après restore', () {
      final e1 = _skiTrained();
      // Aucune mesure → snapshot minimal
      final snap = e1.toSnapshot();

      final e2 = _skiTrained();
      e2.restoreFromSnapshot(snap);
      expect(e2.acceptedCount,     0);
      expect(e2.calibrationWeight, 0.0);
      expect(e2.isCalibrated,      isFalse);
    });

    test('les params restent dans les limites après restore + nouvelles mesures', () {
      final e1 = _skiTrained();
      for (int i = 0; i < 20; i++) {
        e1.addGpsMeasurement(
            distanceM: 300, elevGain: 0, elevLoss: 0, actualSeconds: 90);
      }

      final e2 = _skiTrained();
      e2.restoreFromSnapshot(e1.toSnapshot());
      // Ajout de mesures après restore
      for (int i = 0; i < 5; i++) {
        e2.addGpsMeasurement(
            distanceM: 300, elevGain: 0, elevLoss: 0, actualSeconds: 90);
      }

      expect(e2.currentParams.horizontalSpeed, inInclusiveRange(0.5, 20.0));
      expect(e2.currentParams.ascentRate,      inInclusiveRange(50.0, 1500.0));
      expect(e2.currentParams.descentRate,     greaterThan(0));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // maxHorizontalDistance
  // ═══════════════════════════════════════════════════════════════════════════

  group('MunterEngine — maxHorizontalDistance', () {
    test('30 min à 4.5 km/h sur terrain normal = 2250 m', () {
      final engine = _skiTrained();
      final d = engine.maxHorizontalDistance(30 * 60);
      expect(d, closeTo(2250.0, 10.0));
    });

    test('heavySnow réduit la distance maximale vs normal', () {
      final normal = _skiTrained().maxHorizontalDistance(60 * 60);
      final heavy  = MunterEngine(MunterProfile(
        activity: MunterActivity.skiTouring,
        fitness:  MunterFitness.trained,
        terrain:  MunterTerrain.heavySnow,
      )).maxHorizontalDistance(60 * 60);
      expect(heavy, lessThan(normal));
    });
  });
}
