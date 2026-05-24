// lib/modules/time/munter.dart
//
// Modèle de vitesse Munter adaptatif.
// Migré depuis TimeToGo (lib/munter.dart) sans modification du modèle métier.
//
// Différences :
//   - Les enums Activity/Level locaux sont ré-exposés par compatibilité,
//     mais l'app expose un seul UserProfile global dans shared/settings/.
//     Voir `profile_adapter.dart` pour la conversion.
//
// Munter classique (à pied, conditions normales) :
//   UM = dist_km / vitesse_kmh + d_plus / 300 + d_minus / 500
//
// Ici on calcule le TEMPS pour un segment (distance horizontale + dénivelé),
// et on calibre les dénominateurs selon le profil utilisateur + le rythme
// mesuré sur le terrain.

// ─── Profil utilisateur (local au module Munter) ──────────────────────────────

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

  /// Signature compacte du profil — utilisée pour invalider la persistance
  /// quand le profil change (les mesures précédentes ne sont plus pertinentes
  /// pour un nouveau baseline).
  String get signature => '${activity.name}/${fitness.name}/${terrain.name}';
}

// ─── Paramètres Munter ────────────────────────────────────────────────────────

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

  MunterParams get currentParams      => _params;
  double       get calibrationWeight  => _calibrationWeight;
  bool         get isCalibrated       => _calibrationWeight >= 0.5;

  /// Estime le temps en secondes pour un segment.
  ///
  /// Formule : t = MAX( dist_km / v_horiz,  D+/ascentRate + D-/descentRate )
  ///
  /// La contrainte dominante dicte le temps. D+ et D- s'additionnent entre
  /// eux (montée + descente sur le même pas coûtent les deux) mais on prend
  /// le MAX avec l'horizontal. Sur terrain plat → la vitesse horiz dicte.
  /// Sur pente raide → le dénivelé dicte.
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

  /// Distance horizontale max dans [budgetSeconds] sur terrain plat.
  double maxHorizontalDistance(double budgetSeconds) {
    final budgetH = budgetSeconds / 3600.0;
    final factor  = _terrainFactor[profile.terrain]!;
    return (_params.horizontalSpeed * budgetH / factor) * 1000.0;
  }

  // ── Calibration ──────────────────────────────────────────────────────────

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
    // Garder uniquement les 20 dernières mesures (sliding window = fenêtre
    // de calibration). Évite l'accumulation infinie en RAM et garde la
    // calibration "fraîche" (n'inclut pas des mesures vieilles de plusieurs
    // sorties qui ne sont plus représentatives).
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

    double totalDist = 0, totalGain = 0, totalLoss = 0, totalTime = 0;
    for (final m in window) {
      totalDist += m.distanceM;
      totalGain += m.elevGain;
      totalLoss += m.elevLoss;
      totalTime += m.actualSeconds;
    }

    if (totalDist < 50 || totalTime < 30) return;

    final measuredHSpeed = (totalDist / 1000.0) / (totalTime / 3600.0);

    double gainTime = 0, gainDist = 0;
    for (final m in window) {
      if (m.elevGain > 2) {
        gainTime += m.actualSeconds;
        gainDist += m.elevGain;
      }
    }
    final measuredAscentRate = gainTime > 0
        ? gainDist / (gainTime / 3600.0)
        : _params.ascentRate;

    double lossTime = 0, lossDist = 0;
    for (final m in window) {
      if (m.elevLoss > 2) {
        lossTime += m.actualSeconds;
        lossDist += m.elevLoss;
      }
    }
    final measuredDescentRate = lossTime > 0
        ? lossDist / (lossTime / 3600.0)
        : _params.descentRate;

    if (measuredHSpeed     < 0.5 || measuredHSpeed     > 20)   return;
    if (measuredAscentRate < 50  || measuredAscentRate > 1500) return;

    final measured = MunterParams(
      horizontalSpeed: measuredHSpeed,
      ascentRate:      measuredAscentRate,
      descentRate:     measuredDescentRate,
    );

    // Poids progressif : 0 à 0 min → 50% à 25 min → 80% à 40 min (plafond)
    final totalMinutes = totalTime / 60.0;
    _calibrationWeight = (totalMinutes / 50.0).clamp(0.0, 0.80);

    final baseline = _resolveBaseParams(profile);
    _params = baseline.blend(measured, _calibrationWeight);
  }

  static MunterParams _resolveBaseParams(MunterProfile profile) {
    return _baseTable[profile.activity]![profile.fitness]!;
  }

  Map<String, dynamic> calibrationReport() => {
    'weight':           '${(_calibrationWeight * 100).toStringAsFixed(0)}%',
    'isCalibrated':     isCalibrated,
    'measurements':     _measurements.length,
    'horizontalSpeed':  _params.horizontalSpeed.toStringAsFixed(2),
    'ascentRate':       _params.ascentRate.toStringAsFixed(0),
    'descentRate':      _params.descentRate.toStringAsFixed(0),
  };

  // ── Persistance ─────────────────────────────────────────────────────────
  //
  // Snapshot = signature profil + mesures GPS récentes. La signature permet
  // de jeter la persistance quand l'utilisateur change de profil (différents
  // baselines → mesures non comparables).
  //
  // Les params calibrés (`_params`) ne sont PAS sauvés directement : ils sont
  // recalculés depuis les mesures + baseline. Ça évite les incohérences entre
  // params stockés et baseline courante.

  /// Snapshot pour persistance. Inclut la signature du profil.
  Map<String, dynamic> toSnapshot() => {
    'profile':     profile.signature,
    'measurements': _measurements.map((m) => {
      'd':  m.distanceM,
      'g':  m.elevGain,
      'l':  m.elevLoss,
      's':  m.actualSeconds,
    }).toList(),
  };

  /// Recharge les mesures depuis un snapshot précédent et recalibre.
  /// Retourne `true` si la restauration a eu lieu (profil compatible),
  /// `false` sinon (signature différente → snapshot ignoré).
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
