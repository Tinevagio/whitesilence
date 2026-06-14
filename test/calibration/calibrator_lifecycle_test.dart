// test/calibration/calibrator_lifecycle_test.dart
//
// Tests de cycle de vie du GpsCalibrator.
// Simule : sortie normale, pause, arrière-plan (coalescing), kill/relaunch,
//          mauvaise précision GPS, fix aberrant (téléportation).
//
// Lancer : flutter test test/calibration/calibrator_lifecycle_test.dart
//
// Note async : GpsCalibrator._ingest() est async (await getElevation).
// Après le dernier onPosition(), attendre un micro-tick pour vider la file :
//   await Future.delayed(Duration.zero);

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:whitesilence/modules/time/gps_calibrator.dart';
import 'package:whitesilence/modules/time/munter.dart';

import '../helpers/fake_dem.dart';
import '../helpers/fake_gps.dart';

// ─── Helpers locaux ───────────────────────────────────────────────────────────

MunterEngine _skiTrained() => MunterEngine(MunterProfile(
      activity: MunterActivity.skiTouring,
      fitness:  MunterFitness.trained,
      terrain:  MunterTerrain.normal,
    ));

/// Injecte une liste de positions dans le calibrateur et attend le flush.
Future<void> injectAll(GpsCalibrator calib, List<Position> trace) async {
  for (final pos in trace) {
    await calib.onPosition(pos);
  }
  await Future.delayed(Duration.zero);
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // 1. Sortie normale continue
  // ═══════════════════════════════════════════════════════════════════════════

  group('Scénario 1 — sortie normale continue', () {
    test('30 positions → plusieurs segments acceptés', () async {
      final munter = _skiTrained();
      final calib  = GpsCalibrator(munter: munter, dem: const FlatDem(1500));
      final t0     = DateTime(2025, 1, 15, 8, 0);

      // 0.0018° lat ≈ 200m. intervalS=90s → vitesse ≈ 8 km/h (< 15, valide).
      final trace = buildUniformTrace(
        startLat: 45.0, startLng: 6.0, startAlt: 1500,
        count: 30, dLat: 0.0018, dLng: 0.0, dAlt: 0.0,
        t0: t0, intervalS: 90,
      );
      await injectAll(calib, trace);

      expect(calib.segmentsAccepted, greaterThanOrEqualTo(3),
          reason: calib.report.toString());
    });

    test('vitesse calibrée reste dans les limites physiques', () async {
      final munter = _skiTrained();
      final calib  = GpsCalibrator(munter: munter, dem: const FlatDem(1500));
      final t0     = DateTime(2025, 1, 15, 8, 0);

      final trace = buildUniformTrace(
        startLat: 45.0, startLng: 6.0, startAlt: 1500,
        count: 25, dLat: 0.0018, dLng: 0.0, dAlt: 0.0,
        t0: t0, intervalS: 90,
      );
      await injectAll(calib, trace);

      expect(munter.currentParams.horizontalSpeed,
          inInclusiveRange(0.5, 15.0));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. Pause au milieu (l'utilisateur s'arrête)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Scénario 2 — pause au milieu', () {
    test('la pause est détectée et le segment en cours est clôturé proprement', () async {
      // _minSpeedKmh = 0.3 km/h. Pour déclencher la détection de pause,
      // il faut que la vitesse PAIRE soit < 0.3 km/h.
      // 0.3 km/h = 0.3/3.6 m/s = 0.0833 m/s → en 120s : 10m max.
      // On déplace de 0.00001° ≈ 1.1m entre deux fixes espacés de 120s
      // → pairSpeedKmh ≈ (1.1/1000) / (120/3600) = 0.033 km/h << 0.3 ✓
      final munter = _skiTrained();
      final calib  = GpsCalibrator(munter: munter, dem: const FlatDem(1500));
      final t0     = DateTime(2025, 1, 15, 9, 0);

      // Phase 1 : marche normale (15 pas)
      final phase1 = buildUniformTrace(
        startLat: 45.0, startLng: 6.0, startAlt: 1500,
        count: 15, dLat: 0.0018, dLng: 0.0, dAlt: 0.0,
        t0: t0, intervalS: 90,
      );
      await injectAll(calib, phase1);
      final acceptedBeforePause = calib.segmentsAccepted;
      expect(acceptedBeforePause, greaterThan(0),
          reason: 'Pré-condition : phase 1 doit avoir des segments acceptés');

      // Phase 2 : pause réelle.
      // dLat = 0.00001° ≈ 1.1m / 120s → vitesse 0.033 km/h < _minSpeedKmh(0.3)
      final pauseStart = phase1.last.timestamp;
      for (int i = 1; i <= 5; i++) {
        await calib.onPosition(fakePos(
          lat:       phase1.last.latitude  + i * 0.00001,  // ~1.1m par pas
          lng:       phase1.last.longitude,
          alt:       phase1.last.altitude,
          timestamp: pauseStart.add(Duration(seconds: i * 120)),
        ));
      }
      await Future.delayed(Duration.zero);

      // Pendant la pause, aucun nouveau segment ne doit être accepté
      // (les paires à vitesse < 0.3 km/h déclenchent _startSegment, pas _evaluateSegment)
      expect(calib.segmentsAccepted, acceptedBeforePause,
          reason: 'Aucun segment ne doit être accepté pendant la pause');

      // Phase 3 : reprise après 10 min
      final resumeT0 = pauseStart.add(const Duration(minutes: 11));
      final phase3 = buildUniformTrace(
        startLat: phase1.last.latitude,
        startLng: phase1.last.longitude,
        startAlt: phase1.last.altitude,
        count: 15, dLat: 0.0018, dLng: 0.0, dAlt: 0.0,
        t0: resumeT0, intervalS: 90,
      );
      await injectAll(calib, phase3);

      expect(calib.segmentsAccepted, greaterThan(acceptedBeforePause),
          reason: 'La reprise après pause doit produire de nouveaux segments');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. App en arrière-plan — coalescing Android
  // ═══════════════════════════════════════════════════════════════════════════

  group('Scénario 3 — coalescing Android (arrière-plan)', () {
    test('positions livrées en rafale avec vrais timestamps → segments valides', () async {
      // Android groupe les fixes GPS pendant la veille et les livre en lot
      // quand l'app revient au premier plan. pos.timestamp contient l'heure
      // réelle du fix ; sans lui (DateTime.now()), toutes les durées seraient ~0.
      final munter = _skiTrained();
      final calib  = GpsCalibrator(munter: munter, dem: const FlatDem(1500));
      final t0     = DateTime(2025, 1, 15, 10, 0);

      // 5 fixes avant la mise en veille
      final preVeille = buildUniformTrace(
        startLat: 45.0, startLng: 6.0, startAlt: 1500,
        count: 5, dLat: 0.0018, dLng: 0.0, dAlt: 0.0,
        t0: t0, intervalS: 90,
      );
      await injectAll(calib, preVeille);

      // Simulation arrière-plan : 20 min de marche, fixes espacés de 90s
      // mais livrés INSTANTANÉMENT (en rafale). Grâce à pos.timestamp,
      // le calibrateur reconstitue les durées correctement.
      final bgT0    = preVeille.last.timestamp;
      final bgTrace = buildUniformTrace(
        startLat: preVeille.last.latitude,
        startLng: preVeille.last.longitude,
        startAlt: preVeille.last.altitude,
        count: 14, dLat: 0.0018, dLng: 0.0, dAlt: 0.0,
        t0: bgT0, intervalS: 90,
      );
      // Injection en rafale (pas de délai entre appels)
      for (final pos in bgTrace) {
        await calib.onPosition(pos);
      }
      await Future.delayed(Duration.zero);

      // Des segments doivent avoir été acceptés malgré la "rafale"
      expect(calib.segmentsAccepted, greaterThan(2),
          reason: 'Le coalescing ne doit pas bloquer la calibration');

      // La vitesse calibrée doit rester physiquement plausible
      expect(munter.currentParams.horizontalSpeed,
          inInclusiveRange(1.0, 15.0));
    });

    test('timestamps dupliqués (dt=0) ignorés sans crash', () async {
      final munter = _skiTrained();
      final calib  = GpsCalibrator(munter: munter, dem: const FlatDem(1500));
      final t0     = DateTime(2025, 1, 15, 10, 0);

      // Fix initial
      await calib.onPosition(
          fakePos(lat: 45.0, lng: 6.0, alt: 1500, timestamp: t0));

      // Même timestamp → dt = 0 → doit être ignoré (pas de crash)
      await calib.onPosition(
          fakePos(lat: 45.001, lng: 6.0, alt: 1500, timestamp: t0));
      await calib.onPosition(
          fakePos(lat: 45.002, lng: 6.0, alt: 1500, timestamp: t0));

      await Future.delayed(Duration.zero);
      // Pas d'exception ; état cohérent
      expect(calib.segmentsAccepted, 0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. Kill & relaunch (persistence snapshot)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Scénario 4 — kill et relaunch', () {
    test('snapshot conserve le poids de calibration après relance', () async {
      // ── Session 1 ──
      final munter1 = _skiTrained();
      final calib1  = GpsCalibrator(munter: munter1, dem: const FlatDem(1500));
      final t0      = DateTime(2025, 1, 15, 8, 0);

      final trace = buildUniformTrace(
        startLat: 45.0, startLng: 6.0, startAlt: 1500,
        count: 25, dLat: 0.0018, dLng: 0.0, dAlt: 0.0,
        t0: t0, intervalS: 90,
      );
      await injectAll(calib1, trace);

      expect(munter1.isCalibrated, isTrue,
          reason: 'Pré-condition : session 1 doit être calibrée');

      // Persistence : ce snapshot serait sauvegardé en SharedPreferences
      final snapshot         = munter1.toSnapshot();
      final weightBeforeKill = munter1.calibrationWeight;

      // ── Kill (simulation : on jette tous les objets) ──

      // ── Session 2 : relance ──
      final munter2 = _skiTrained();
      final ok      = munter2.restoreFromSnapshot(snapshot);

      expect(ok,             isTrue);
      expect(munter2.isCalibrated,      isTrue);
      expect(munter2.calibrationWeight, closeTo(weightBeforeKill, 0.01));
      expect(munter2.acceptedCount,     munter1.acceptedCount);
    });

    test('après restore, nouvelles mesures affinent le profil', () async {
      // ── Session 1 : calibration initiale ──
      final munter1 = _skiTrained();
      final calib1  = GpsCalibrator(munter: munter1, dem: const FlatDem(1500));
      final t0      = DateTime(2025, 1, 15, 8, 0);

      await injectAll(calib1, buildUniformTrace(
        startLat: 45.0, startLng: 6.0, startAlt: 1500,
        count: 20, dLat: 0.0018, dLng: 0.0, dAlt: 0.0,
        t0: t0, intervalS: 90,
      ));

      // ── Session 2 : on repart avec snapshot ──
      final munter2 = _skiTrained();
      munter2.restoreFromSnapshot(munter1.toSnapshot());

      final speedAfterRestore = munter2.currentParams.horizontalSpeed;

      // Nouvelles mesures : marcheur plus lent (3 km/h)
      for (int i = 0; i < 10; i++) {
        munter2.addGpsMeasurement(
            distanceM: 100, elevGain: 0, elevLoss: 0, actualSeconds: 120);
      }

      // La vitesse doit avoir bougé vers 3 km/h (pas rester identique)
      expect(munter2.currentParams.horizontalSpeed,
          isNot(closeTo(speedAfterRestore, 0.01)));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. Mauvaise précision GPS (tunnel, bâtiment)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Scénario 5 — mauvaise précision GPS', () {
    test('fixes avec accuracy > 30m ignorés', () async {
      final munter = _skiTrained();
      final calib  = GpsCalibrator(munter: munter, dem: const FlatDem(1500));
      final t0     = DateTime(2025, 1, 15, 11, 0);

      // Tous les fixes ont accuracy=50m (> _maxGpsAccuracyM=30)
      final badTrace = buildUniformTrace(
        startLat: 45.0, startLng: 6.0, startAlt: 1500,
        count: 20, dLat: 0.0018, dLng: 0.0, dAlt: 0.0,
        t0: t0, intervalS: 90,
        accuracy: 50.0,
      );
      await injectAll(calib, badTrace);

      expect(calib.segmentsAccepted, 0,
          reason: 'Tous les fixes ont été rejetés par le filtre précision');
      expect(munter.isCalibrated, isFalse);
    });

    test('retour à bonne précision après tunnel → calibration reprend', () async {
      final munter = _skiTrained();
      final calib  = GpsCalibrator(munter: munter, dem: const FlatDem(1500));
      final t0     = DateTime(2025, 1, 15, 11, 0);

      // Phase 1 : bonne précision (marche normale)
      await injectAll(calib, buildUniformTrace(
        startLat: 45.0, startLng: 6.0, startAlt: 1500,
        count: 10, dLat: 0.0018, dLng: 0.0, dAlt: 0.0,
        t0: t0, intervalS: 90,
      ));
      final acceptedAfterPhase1 = calib.segmentsAccepted;

      // Phase 2 : mauvaise précision (tunnel)
      await injectAll(calib, buildUniformTrace(
        startLat: 45.018, startLng: 6.0, startAlt: 1500,
        count: 5, dLat: 0.0018, dLng: 0.0, dAlt: 0.0,
        t0: t0.add(const Duration(minutes: 16)),
        intervalS: 90, accuracy: 50.0,
      ));

      // Phase 3 : retour bonne précision
      await injectAll(calib, buildUniformTrace(
        startLat: 45.027, startLng: 6.0, startAlt: 1500,
        count: 10, dLat: 0.0018, dLng: 0.0, dAlt: 0.0,
        t0: t0.add(const Duration(minutes: 24)),
        intervalS: 90,
      ));

      // Note : le calibrateur produit un segment "tunnel" en phase 3 qui
      // enjambe la zone sans GPS. Le dernier fix valide avant le tunnel et
      // le premier fix valide après sont reliés → segment plus long que la normale
      // (visible dans les logs : "1002m en 540s"). C'est le comportement attendu :
      // le segment est accepté s'il reste dans les limites de vitesse [0.3, 15 km/h].
      expect(calib.segmentsAccepted, greaterThan(acceptedAfterPhase1),
          reason: 'La calibration doit reprendre après le tunnel');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 6. Fix aberrant (téléportation)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Scénario 6 — fix aberrant (téléportation)', () {
    test('fix à vitesse irréaliste ne corrompt pas le D+ accumulé', () async {
      final munter = _skiTrained();
      final calib  = GpsCalibrator(munter: munter, dem: const FlatDem(1500));
      final t0     = DateTime(2025, 1, 15, 12, 0);

      // 3 fixes normaux pour démarrer un segment
      await calib.onPosition(fakePos(
          lat: 45.000, lng: 6.000, alt: 1500,
          timestamp: t0));
      await calib.onPosition(fakePos(
          lat: 45.002, lng: 6.000, alt: 1510,
          timestamp: t0.add(const Duration(seconds: 90))));
      await calib.onPosition(fakePos(
          lat: 45.004, lng: 6.000, alt: 1520,
          timestamp: t0.add(const Duration(seconds: 180))));

      // Fix aberrant : +2km en 5s → pairSpeedKmh ≈ 1440 km/h >> 15 km/h
      // Le calibrateur doit fermer ou ignorer cette paire, pas crasher
      await calib.onPosition(fakePos(
          lat: 45.024, lng: 6.000, alt: 1530,
          timestamp: t0.add(const Duration(seconds: 185))));

      // Reprise normale
      await calib.onPosition(fakePos(
          lat: 45.026, lng: 6.000, alt: 1540,
          timestamp: t0.add(const Duration(seconds: 275))));
      await calib.onPosition(fakePos(
          lat: 45.028, lng: 6.000, alt: 1550,
          timestamp: t0.add(const Duration(seconds: 365))));

      await Future.delayed(Duration.zero);

      // Pas de crash ; les params restent dans des bornes physiques
      expect(munter.currentParams.horizontalSpeed,
          inInclusiveRange(0.5, 20.0));
      expect(munter.currentParams.ascentRate,
          inInclusiveRange(50.0, 1500.0));
    });

    test('plusieurs fixes aberrants consécutifs : pas de segment accepté', () async {
      final munter = _skiTrained();
      final calib  = GpsCalibrator(munter: munter, dem: const FlatDem(1500));
      final t0     = DateTime(2025, 1, 15, 12, 0);

      // Fix initial valide
      await calib.onPosition(
          fakePos(lat: 45.0, lng: 6.0, alt: 1500, timestamp: t0));

      // Série de "téléportations" toutes les 2s
      for (int i = 1; i <= 10; i++) {
        await calib.onPosition(fakePos(
          lat: 45.0 + i * 0.1,  // +11km par saut
          lng: 6.0,
          alt: 1500,
          timestamp: t0.add(Duration(seconds: i * 2)),
        ));
      }
      await Future.delayed(Duration.zero);

      // Vitesse aberrante → aucun segment ne passe le sanity check de vitesse
      expect(calib.segmentsAccepted, 0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 7. DEM indisponible (hors-ligne, tuile absente)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Scénario 7 — DEM indisponible', () {
    test('FailingDem : fallback altitude GPS, calibration non bloquée', () async {
      final munter = _skiTrained();
      // FailingDem lève une exception → le calibrateur doit retomber sur
      // l'altitude GPS brute (pos.altitude)
      final calib  = GpsCalibrator(munter: munter, dem: FailingDem());
      final t0     = DateTime(2025, 1, 15, 13, 0);

      final trace = buildUniformTrace(
        startLat: 45.0, startLng: 6.0, startAlt: 1500,
        count: 20, dLat: 0.0018, dLng: 0.0, dAlt: 0.0,
        t0: t0, intervalS: 90,
      );
      await injectAll(calib, trace);

      // Avec altitude GPS constante (dAlt=0), elevGain=0 → fallback ascentRate
      // La calibration doit quand même progresser (vitesse horizontale)
      expect(calib.segmentsAccepted, greaterThan(0));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 8. Reset
  // ═══════════════════════════════════════════════════════════════════════════

  group('Scénario 8 — reset', () {
    test('reset remet tout à zéro, les nouvelles mesures repartent de zéro', () async {
      final munter = _skiTrained();
      final calib  = GpsCalibrator(munter: munter, dem: const FlatDem(1500));
      final t0     = DateTime(2025, 1, 15, 8, 0);

      await injectAll(calib, buildUniformTrace(
        startLat: 45.0, startLng: 6.0, startAlt: 1500,
        count: 15, dLat: 0.0018, dLng: 0.0, dAlt: 0.0,
        t0: t0, intervalS: 90,
      ));
      expect(calib.segmentsAccepted, greaterThan(0));

      calib.reset();
      expect(calib.segmentsAccepted, 0);
      expect(calib.segmentsRejected, 0);

      // Après reset, les nouvelles positions repartent proprement
      await injectAll(calib, buildUniformTrace(
        startLat: 45.0, startLng: 6.0, startAlt: 1500,
        count: 10, dLat: 0.0018, dLng: 0.0, dAlt: 0.0,
        t0: t0.add(const Duration(hours: 1)),
        intervalS: 90,
      ));
      expect(calib.segmentsAccepted, greaterThanOrEqualTo(1));
    });
  });
}
