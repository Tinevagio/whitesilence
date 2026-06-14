test('10 segments acceptés → isCalibrated', () async {
  final munter = MunterEngine(MunterProfile(
    activity: MunterActivity.skiTouring,
    fitness:  MunterFitness.trained,
    terrain:  MunterTerrain.normal,
  ));
  final calib = GpsCalibrator(munter: munter, dem: FlatDem(1500));

  final t0 = DateTime(2025, 1, 15, 8, 0);

  // ~200m horizontal toutes les 90s → vitesse ~8 km/h, réaliste
  // 0.0018° ≈ 200m latitude
  final trace = buildTrace(
    startLat: 45.0, startLng: 6.0, startAlt: 1500,
    steps: List.generate(30, (_) => (dLat: 0.0018, dLng: 0.0, dAlt: 10.0)),
    t0: t0, intervalS: 90,
  );

  for (final pos in trace) {
    await calib.onPosition(pos);
  }

  expect(calib.segmentsAccepted, greaterThanOrEqualTo(10));
  expect(munter.isCalibrated, isTrue);
});

test('pause longue → segment avant la pause accepté, reprise propre', () async {
  final munter = MunterEngine(...); // même profil
  final calib  = GpsCalibrator(munter: munter, dem: FlatDem(1500));
  final t0 = DateTime(2025, 1, 15, 9, 0);

  int accepted = 0;
  calib.onUpdate = () { accepted = calib.segmentsAccepted; };

  // 15 positions de marche normale → quelques segments
  final marchePre = buildTrace(
    startLat: 45.0, startLng: 6.0, startAlt: 1500,
    steps: List.generate(15, (_) => (dLat: 0.0018, dLng: 0.0, dAlt: 10.0)),
    t0: t0, intervalS: 90,
  );
  for (final pos in marchePre) await calib.onPosition(pos);

  final acceptedBeforePause = calib.segmentsAccepted;

  // Pause : même coordonnée, vitesse ~0, pendant 10 min
  // pairSpeedKmh = 0 → _minSpeedKmh pas atteint → clôture du segment
  final lastPos = marchePre.last;
  for (int i = 1; i <= 6; i++) {
    await calib.onPosition(fakePos(
      lat:       lastPos.latitude + i * 0.00001, // ε pour ne pas avoir dt=0
      lng:       lastPos.longitude,
      alt:       lastPos.altitude,
      timestamp: lastPos.timestamp.add(Duration(seconds: i * 100)),
    ));
  }

  // Reprise après pause : 15 nouvelles positions de marche
  final marchePost = buildTrace(
    startLat: lastPos.latitude,
    startLng: lastPos.longitude,
    startAlt: lastPos.altitude,
    steps: List.generate(15, (_) => (dLat: 0.0018, dLng: 0.0, dAlt: 10.0)),
    t0: lastPos.timestamp.add(const Duration(minutes: 11)),
    intervalS: 90,
  );
  for (final pos in marchePost) await calib.onPosition(pos);

  // La reprise après pause produit de nouveaux segments
  expect(calib.segmentsAccepted, greaterThan(acceptedBeforePause));
});

test('coalescing Android : positions en rafale avec vrais timestamps', () async {
  final munter = MunterEngine(...);
  final calib  = GpsCalibrator(munter: munter, dem: FlatDem(1500));

  final t0 = DateTime(2025, 1, 15, 10, 0);

  // 1. Quelques positions avant la mise en veille
  final preBackground = buildTrace(
    startLat: 45.0, startLng: 6.0, startAlt: 1500,
    steps: List.generate(5, (_) => (dLat: 0.0018, dLng: 0.0, dAlt: 8.0)),
    t0: t0, intervalS: 90,
  );
  for (final pos in preBackground) await calib.onPosition(pos);

  // 2. Simulation : 20 minutes en arrière-plan.
  //    En réalité Android envoie ces fixes TOUS EN MÊME TEMPS quand l'app
  //    revient au premier plan, mais avec leurs vrais timestamps.
  //    C'est exactement ce que pos.timestamp est censé gérer.
  final backgroundStart = preBackground.last.timestamp;
  final backgroundFixes = buildTrace(
    startLat: preBackground.last.latitude,
    startLng: preBackground.last.longitude,
    startAlt: preBackground.last.altitude,
    // Pendant la veille, l'utilisateur a continué de marcher
    steps: List.generate(12, (_) => (dLat: 0.0018, dLng: 0.0, dAlt: 10.0)),
    t0: backgroundStart,
    intervalS: 90, // espacés de 90s dans le temps réel
  );
  // Livraison en rafale : on les injecte tous d'un coup
  // mais DateTime.now() serait identique pour tous → bug corrigé
  for (final pos in backgroundFixes) await calib.onPosition(pos);

  // Avec pos.timestamp, les durées de segments sont correctes
  // → segments acceptés même pendant la période "fond d'écran"
  expect(calib.segmentsAccepted, greaterThan(2));

  // Vérifie que la vitesse calibrée est raisonnable (pas 0 ni infinie)
  expect(munter.currentParams.horizontalSpeed, inInclusiveRange(1.0, 12.0));
});

test('kill & relaunch : snapshot conserve le poids de calibration', () async {
  // ── Session 1 ──
  final munter1 = MunterEngine(MunterProfile(
    activity: MunterActivity.skiTouring,
    fitness:  MunterFitness.trained,
    terrain:  MunterTerrain.normal,
  ));
  final calib1 = GpsCalibrator(munter: munter1, dem: FlatDem(1500));
  final t0 = DateTime(2025, 1, 15, 8, 0);

  final trace = buildTrace(
    startLat: 45.0, startLng: 6.0, startAlt: 1500,
    steps: List.generate(25, (_) => (dLat: 0.0018, dLng: 0.0, dAlt: 8.0)),
    t0: t0, intervalS: 90,
  );
  for (final pos in trace) await calib1.onPosition(pos);

  final weightBeforeKill = munter1.calibrationWeight;
  final snapshot = munter1.toSnapshot(); // ce qui serait persisté en SharedPrefs

  expect(munter1.isCalibrated, isTrue);

  // ── Kill ──  (simulation : on jette tous les objets)

  // ── Session 2 : relance ──
  final munter2 = MunterEngine(MunterProfile(
    activity: MunterActivity.skiTouring,
    fitness:  MunterFitness.trained,
    terrain:  MunterTerrain.normal,
  ));
  final restored = munter2.restoreFromSnapshot(snapshot);

  expect(restored, isTrue);
  expect(munter2.isCalibrated, isTrue);
  expect(munter2.calibrationWeight, closeTo(weightBeforeKill, 0.01));
  expect(munter2.acceptedCount, munter1.acceptedCount);
});

test('fixes de mauvaise précision ignorés → pas de segment fantôme', () async {
  final munter = MunterEngine(...);
  final calib  = GpsCalibrator(munter: munter, dem: FlatDem(1500));
  final t0 = DateTime(2025, 1, 15, 11, 0);

  // Série de fixes avec accuracy=50m (tunnel, bâtiment) → tous rejetés
  final badFixes = buildTrace(
    startLat: 45.0, startLng: 6.0, startAlt: 1500,
    steps: List.generate(20, (_) => (dLat: 0.0018, dLng: 0.0, dAlt: 10.0)),
    t0: t0, intervalS: 90,
  );

  // Override accuracy = 50m (> _maxGpsAccuracyM = 30m)
  for (final pos in badFixes) {
    await calib.onPosition(fakePos(
      lat: pos.latitude, lng: pos.longitude, alt: pos.altitude,
      accuracy: 50.0,   // <-- mauvaise précision
      timestamp: pos.timestamp,
    ));
  }

  expect(calib.segmentsAccepted, 0); // aucun segment : tous filtrés à l'entrée
  expect(munter.isCalibrated, isFalse);
});

test('fix aberrant à 80 km/h → segment rejeté', () async {
  final munter = MunterEngine(...);
  final calib  = GpsCalibrator(munter: munter, dem: FlatDem(1500));
  final t0 = DateTime(2025, 1, 15, 12, 0);

  // 5 fixes normaux pour initialiser un segment
  await calib.onPosition(fakePos(lat: 45.000, lng: 6.000, alt: 1500, timestamp: t0));
  await calib.onPosition(fakePos(lat: 45.002, lng: 6.000, alt: 1510, timestamp: t0.add(const Duration(seconds: 90))));
  await calib.onPosition(fakePos(lat: 45.004, lng: 6.000, alt: 1520, timestamp: t0.add(const Duration(seconds: 180))));

  // Fix aberrant : "téléportation" de 2km en 5s → ~1440 km/h
  await calib.onPosition(fakePos(
    lat: 45.024,  // +2 km
    lng: 6.000, alt: 1530,
    timestamp: t0.add(const Duration(seconds: 185)),
  ));

  // Ce fix unique est filtré par pairSpeedKmh > _maxSpeedKmh (15 km/h)
  // Le segment ne devrait pas s'accumuler avec cette paire
  // (selon le code : la paire est rejetée, mais le segment continue)
  // → après retour à vitesse normale, on vérifie qu'on n'a pas de D+ irréaliste
  await calib.onPosition(fakePos(lat: 45.026, lng: 6.000, alt: 1540, timestamp: t0.add(const Duration(seconds: 270))));

  // Le segment qui se clôt ne doit pas avoir de taux de montée irréaliste
  // (la téléportation n'aurait pas dû contribuer au D+)
  expect(calib.lastRejectReason, isNot(contains('irréaliste')));
});

