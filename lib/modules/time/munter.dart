// lib/modules/time/munter.dart
//
// Modèle de vitesse Munter adaptatif.
//
// Munter classique :
//   UM = dist_km / vitesse_kmh + d_plus / 300 + d_minus / 500
//
// Ici on calcule le TEMPS pour un segment (distance horizontale + dénivelé),
// et on calibre les dénominateurs selon le profil utilisateur + le rythme
// mesuré sur le terrain.
//
// ── Corrections v2 ──────────────────────────────────────────────────────────
//
// 1. Plafond calibration : 80% → 95%.
//    L'ancien plafond à 80% bloquait définitivement à "80%" dans l'UI,
//    peu importe la durée de sortie. On monte à 95% (garder 5% du baseline
//    suffit pour éviter les dérives sur des mesures aberrantes).
//
// 2. Calcul ascent rate corrigé dans _recalibrate().
//    Avant : gainTime = temps total des segments qui montaient, y compris
//    le temps passé en plat/descente sur ces segments → taux systématiquement
//    sous-estimé → estimations de montée trop longues.
//    Après : on estime la fraction de temps vraiment passée en montée via
//    le ratio (elevGain / distM) × durationS, ce qui donne un taux réaliste.
//
// 3. Calcul descent rate corrigé de la même façon.

enum MunterActivity { hiking, skiTouring, trail }
enum MunterFitness { beginner, trained, warrior }
enum MunterTerrain { normal, difficultTerrain, heavySnow }

class MunterProfile {
  final MunterActivity activity;
  final MunterFitness fitness;
  final MunterTerrain terrain;

  const MunterProfile({
    required this.activity,
    required this.fitness,
    required this.terrain,
  });

  String get signature => '${activity.name}/${fitness.name}/${terrain.name}';
}

class MunterParams {
  final double horizontalSpeed; // km/h
  final double ascentRate;      // m/h (D+)
  final double descentRate;     // m/h (D-)

  const MunterParams({
    required this.horizontalSpeed,
    required this.ascentRate,
    required this.descentRate,
  });

  MunterParams blend(MunterParams measured, double weight) {
    final w = weight.clamp(0.0, 1.0);
    return MunterParams(
      horizontalSpeed: horizontalSpeed * (1 - w) + measured.horizontalSpeed * w,
      ascentRate:      ascentRate      * (1 - w) + measured.ascentRate      * w,
      descentRate:     descentRate     * (1 - w) + measured.descentRate     * w,
    );
  }

  @override
  String toString() =>
      'MunterParams(h=${horizontalSpeed.toStringAsFixed(1)} km/h, '
      'D+=${ascentRate.toStringAsFixed(0)} m/h, '
      'D-=${descentRate.toStringAsFixed(0)} m/h)';
}

// ─── Table de référence ───────────────────────────────────────────────────────

const Map<MunterActivity, Map<MunterFitness, MunterParams>> _baseTable = {
  MunterActivity.hiking: {
    MunterFitness.beginner: MunterParams(horizontalSpeed: 3.0, ascentRate: 250, descentRate: 400),
    MunterFitness.trained:  MunterParams(horizontalSpeed: 4.0, ascentRate: 350, descentRate: 500),
    MunterFitness.warrior:  MunterParams(horizontalSpeed: 5.0, ascentRate: 500, descentRate: 700),
  },
  MunterActivity.skiTouring: {
    MunterFitness.beginner: MunterParams(horizontalSpeed: 3.5, ascentRate: 300, descentRate: 600),
    MunterFitness.trained:  MunterParams(horizontalSpeed: 4.5, ascentRate: 450, descentRate: 900),
    MunterFitness.warrior:  MunterParams(horizontalSpeed: 5.5, ascentRate: 600, descentRate: 1200),
  },
  MunterActivity.trail: {
    MunterFitness.beginner: MunterParams(horizontalSpeed: 5.0, ascentRate: 400, descentRate: 600),
    MunterFitness.trained:  MunterParams(horizontalSpeed: 7.0, ascentRate: 600, descentRate: 900),
    MunterFitness.warrior:  MunterParams(horizontalSpeed: 9.0, ascentRate: 900, descentRate: 1200),
  },
};

const Map<MunterTerrain, double> _terrainFactor = {
  MunterTerrain.normal:           1.0,
  MunterTerrain.difficultTerrain: 1.30,
  MunterTerrain.heavySnow:        1.45,
};

// ─── Moteur de calcul ─────────────────────────────────────────────────────────

class MunterEngine {
  final MunterProfile profile;

  MunterParams _params;
  final List<_GpsMeasurement> _measurements = [];
  double _calibrationWeight = 0.0;

  MunterEngine(this.profile) : _params = _resolveBaseParams(profile);

  MunterParams get currentParams     => _params;
  double       get calibrationWeight => _calibrationWeight;
  bool         get isCalibrated      => _calibrationWeight >= 0.5;

  double estimateSeconds({
    required double distanceM,
    required double elevGain,
    required double elevLoss,
  }) {
    final distKm = distanceM / 1000.0;
    final tHoriz = distKm / _params.horizontalSpeed;
    final tVert  = (elevGain / _params.ascentRate)
                 + (elevLoss / _params.descentRate);
    final tBase  = tHoriz > tVert ? tHoriz : tVert;
    final factor = _terrainFactor[profile.terrain]!;
    return tBase * factor * 3600;
  }

  double maxHorizontalDistance(double budgetSeconds) {
    final budgetH = budgetSeconds / 3600.0;
    final factor  = _terrainFactor[profile.terrain]!;
    return (_params.horizontalSpeed * budgetH / factor) * 1000.0;
  }

  // ── Calibration ────────────────────────────────────────────────────────────

  void addGpsMeasurement({
    required double distanceM,
    required double elevGain,
    required double elevLoss,
    required double actualSeconds,
  }) {
    if (distanceM < 10 || actualSeconds < 10) return;
    _measurements.add(_GpsMeasurement(
      distanceM:     distanceM,
      elevGain:      elevGain,
      elevLoss:      elevLoss,
      actualSeconds: actualSeconds,
    ));
    if (_measurements.length > 20) {
      _measurements.removeRange(0, _measurements.length - 20);
    }
    _recalibrate();
  }

  void _recalibrate() {
    if (_measurements.length < 3) return;

    final window = _measurements.length > 20
        ? _measurements.sublist(_measurements.length - 20)
        : _measurements;

    // ── Vitesse horizontale ─────────────────────────────────────────────────
    double totalDist = 0, totalTime = 0;
    for (final m in window) {
      totalDist += m.distanceM;
      totalTime += m.actualSeconds;
    }
    if (totalDist < 50 || totalTime < 30) return;
    final measuredHSpeed = (totalDist / 1000.0) / (totalTime / 3600.0);

    // ── Taux de montée ───────────────────────────────────────────────────────
    //
    // Correction v2 : on n'accumule plus le temps TOTAL des segments qui
    // montent. Sur un segment de 60s qui monte 20m sur 200m de distance
    // horizontale, le randonneur a passé ~20/200 = 10% du temps en montée
    // pure, soit ~6s. Accumuler 60s gonflait artificiellement gainTime et
    // sous-estimait le taux de montée.
    //
    // Nouvelle approche : on estime le temps de montée par proportionnalité
    // (elevGain / distM) × durationS. Hypothèse : la vitesse est constante
    // sur le segment — bonne approximation pour des segments courts (60s).
    double gainTimeSec = 0, gainM = 0;
    for (final m in window) {
      if (m.elevGain > 2 && m.distanceM > 0) {
        // Fraction du segment passée en montée
        final upFraction = (m.elevGain / m.distanceM).clamp(0.0, 1.0);
        gainTimeSec += m.actualSeconds * upFraction;
        gainM       += m.elevGain;
      }
    }
    final measuredAscentRate = gainTimeSec > 0
        ? gainM / (gainTimeSec / 3600.0)
        : _params.ascentRate;

    // ── Taux de descente ─────────────────────────────────────────────────────
    // Même correction que pour la montée.
    double lossTimeSec = 0, lossM = 0;
    for (final m in window) {
      if (m.elevLoss > 2 && m.distanceM > 0) {
        final downFraction = (m.elevLoss / m.distanceM).clamp(0.0, 1.0);
        lossTimeSec += m.actualSeconds * downFraction;
        lossM       += m.elevLoss;
      }
    }
    final measuredDescentRate = lossTimeSec > 0
        ? lossM / (lossTimeSec / 3600.0)
        : _params.descentRate;

    // ── Sanity checks ────────────────────────────────────────────────────────
    if (measuredHSpeed     < 0.5 || measuredHSpeed     > 20)   return;
    if (measuredAscentRate < 50  || measuredAscentRate > 1500) return;

    final measured = MunterParams(
      horizontalSpeed: measuredHSpeed,
      ascentRate:      measuredAscentRate,
      descentRate:     measuredDescentRate,
    );

    // ── Poids progressif ─────────────────────────────────────────────────────
    //
    // Correction v2 : plafond relevé de 80% à 95%.
    // L'ancien plafond bloquait l'UI à "80%" en permanence après ~40 min
    // de sortie, ce qui était frustrant et trompeur.
    // On garde 5% du baseline pour amortir les mesures aberrantes.
    final totalMinutes = totalTime / 60.0;
    _calibrationWeight = (totalMinutes / 50.0).clamp(0.0, 0.95);

    final baseline = _resolveBaseParams(profile);
    _params = baseline.blend(measured, _calibrationWeight);
  }

  static MunterParams _resolveBaseParams(MunterProfile profile) {
    return _baseTable[profile.activity]![profile.fitness]!;
  }

  Map<String, dynamic> calibrationReport() => {
    'weight':          '${(_calibrationWeight * 100).toStringAsFixed(0)}%',
    'isCalibrated':    isCalibrated,
    'measurements':    _measurements.length,
    'horizontalSpeed': _params.horizontalSpeed.toStringAsFixed(2),
    'ascentRate':      _params.ascentRate.toStringAsFixed(0),
    'descentRate':     _params.descentRate.toStringAsFixed(0),
  };

  // ── Persistance ────────────────────────────────────────────────────────────

  Map<String, dynamic> toSnapshot() => {
    'profile':      profile.signature,
    'measurements': _measurements.map((m) => {
      'd': m.distanceM,
      'g': m.elevGain,
      'l': m.elevLoss,
      's': m.actualSeconds,
    }).toList(),
  };

  bool restoreFromSnapshot(Map<String, dynamic> snapshot) {
    final sig = snapshot['profile'] as String?;
    if (sig == null || sig != profile.signature) return false;

    final raw = snapshot['measurements'];
    if (raw is! List) return false;

    _measurements.clear();
    for (final item in raw) {
      if (item is! Map) continue;
      final d = (item['d'] as num?)?.toDouble();
      final g = (item['g'] as num?)?.toDouble();
      final l = (item['l'] as num?)?.toDouble();
      final s = (item['s'] as num?)?.toDouble();
      if (d == null || g == null || l == null || s == null) continue;
      _measurements.add(_GpsMeasurement(
        distanceM:     d,
        elevGain:      g,
        elevLoss:      l,
        actualSeconds: s,
      ));
    }

    if (_measurements.isNotEmpty) _recalibrate();
    return true;
  }
}

class _GpsMeasurement {
  final double distanceM;
  final double elevGain;
  final double elevLoss;
  final double actualSeconds;

  const _GpsMeasurement({
    required this.distanceM,
    required this.elevGain,
    required this.elevLoss,
    required this.actualSeconds,
  });
}
