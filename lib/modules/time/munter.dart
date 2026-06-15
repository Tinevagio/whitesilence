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
// ── Corrections v3 ──────────────────────────────────────────────────────────
//
// 1. POIDS DE CALIBRATION rebasé sur le NOMBRE de segments acceptés, plus sur
//    le temps cumulé de la fenêtre.
//
//    Régression v2 : `_calibrationWeight = (totalTime/60 / 50).clamp(0, 0.95)`.
//    Or `totalTime` est la somme des durées des segments DE LA FENÊTRE, et la
//    fenêtre est plafonnée à 20 mesures. Comme un segment se ferme à ~60 s
//    (cf. GpsCalibrator), totalTime était plafonné en dur à ~20×60 = 20 min,
//    soit un poids MAX de 20/50 = 0.40 quelle que soit la durée de sortie.
//    Résultat : isCalibrated (≥0.5) jamais atteint → UI bloquée sur "baseline".
//
//    Correction : poids = (segments acceptés cumulés / 20), plafonné à 0.95.
//    Le compteur est cumulatif (non tronqué par la fenêtre) et persisté, donc
//    la confiance tient sur une longue sortie et survit à un redémarrage.
//      - isCalibrated (0.5) atteint à 10 segments (~10-15 min).
//      - poids plein (0.95) à 20 segments.
//
// 2. Calcul ascent/descent rate corrigé (inchangé depuis v2) : on estime la
//    fraction de temps réellement passée en montée/descente via
//    (elevGain / distM) × durationS plutôt que le temps total du segment.

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

// ── Calibration : nombre de segments acceptés pour atteindre le poids plein ──
const int _kSegmentsForFullWeight = 20;
const double _kMaxCalibrationWeight = 0.95;

// ─── Moteur de calcul ─────────────────────────────────────────────────────────

class MunterEngine {
  final MunterProfile profile;

  MunterParams _params;
  final List<_GpsMeasurement> _measurements = [];
  double _calibrationWeight = 0.0;

  /// Nombre CUMULATIF de segments acceptés depuis le début de la calibration
  /// pour ce profil. N'est PAS tronqué par la fenêtre de 20 mesures : c'est
  /// l'indicateur de confiance, distinct de la fenêtre utilisée pour estimer
  /// les paramètres récents.
  int _acceptedCount = 0;

  // ── Cadenas par paramètre ─────────────────────────────────────────────────
  //
  // Quand un paramètre est cadenassé :
  //   - la valeur forcée (_xxxOverride) est utilisée dans estimateSeconds()
  //     à la place de la valeur calibrée/baseline.
  //   - la calibration GPS continue de tourner normalement en arrière-plan
  //     (les mesures s'accumulent dans _measurements).
  //   - quand on décadenasse, _recalibrate() est appelé immédiatement avec
  //     toutes les mesures accumulées → les données GPS s'appliquent aussitôt.
  bool   _hSpeedLocked  = false;
  bool   _ascentLocked  = false;
  bool   _descentLocked = false;
  double? _hSpeedOverride;
  double? _ascentOverride;
  double? _descentOverride;

  MunterEngine(this.profile) : _params = _resolveBaseParams(profile);

  MunterParams get currentParams     => _params;
  double       get calibrationWeight => _calibrationWeight;
  bool         get isCalibrated      => _calibrationWeight >= 0.5;
  int          get acceptedCount     => _acceptedCount;

  // Getters cadenas
  bool    get hSpeedLocked   => _hSpeedLocked;
  bool    get ascentLocked   => _ascentLocked;
  bool    get descentLocked  => _descentLocked;
  double? get hSpeedOverride => _hSpeedOverride;
  double? get ascentOverride => _ascentOverride;
  double? get descentOverride => _descentOverride;
  bool    get anyLocked      => _hSpeedLocked || _ascentLocked || _descentLocked;

  /// Paramètres effectivement utilisés pour les calculs (override si cadenassé,
  /// sinon calibré/baseline).
  MunterParams get effectiveParams => MunterParams(
    horizontalSpeed: _hSpeedLocked  && _hSpeedOverride  != null ? _hSpeedOverride!  : _params.horizontalSpeed,
    ascentRate:      _ascentLocked  && _ascentOverride  != null ? _ascentOverride!  : _params.ascentRate,
    descentRate:     _descentLocked && _descentOverride != null ? _descentOverride! : _params.descentRate,
  );

  double estimateSeconds({
    required double distanceM,
    required double elevGain,
    required double elevLoss,
  }) {
    // Utilise effectiveParams : override si cadenassé, calibré/baseline sinon.
    final p      = effectiveParams;
    final distKm = distanceM / 1000.0;
    final tHoriz = distKm / p.horizontalSpeed;
    final tVert  = (elevGain / p.ascentRate)
                 + (elevLoss / p.descentRate);
    final tBase  = tHoriz > tVert ? tHoriz : tVert;
    final factor = _terrainFactor[profile.terrain]!;
    return tBase * factor * 3600;
  }

  double maxHorizontalDistance(double budgetSeconds) {
    final budgetH = budgetSeconds / 3600.0;
    final factor  = _terrainFactor[profile.terrain]!;
    return (effectiveParams.horizontalSpeed * budgetH / factor) * 1000.0;
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
    // Compteur de confiance : cumulatif, indépendant de la troncature fenêtre.
    _acceptedCount++;
    if (_measurements.length > 20) {
      _measurements.removeRange(0, _measurements.length - 20);
    }
    _recalibrate();
  }

  // ── API cadenas ────────────────────────────────────────────────────────────

  /// Cadenas la vitesse horizontale à la valeur [value].
  /// La calibration GPS continue en arrière-plan.
  void lockHSpeed(double value) {
    _hSpeedLocked   = true;
    _hSpeedOverride = value;
  }

  void lockAscent(double value) {
    _ascentLocked   = true;
    _ascentOverride = value;
  }

  void lockDescent(double value) {
    _descentLocked   = true;
    _descentOverride = value;
  }

  /// Décadenasse et applique immédiatement les mesures GPS accumulées.
  void unlockHSpeed() {
    _hSpeedLocked   = false;
    _hSpeedOverride = null;
    if (_measurements.isNotEmpty) _recalibrate();
  }

  void unlockAscent() {
    _ascentLocked   = false;
    _ascentOverride = null;
    if (_measurements.isNotEmpty) _recalibrate();
  }

  void unlockDescent() {
    _descentLocked   = false;
    _descentOverride = null;
    if (_measurements.isNotEmpty) _recalibrate();
  }

  /// Mise à jour d'une valeur cadenassée (slider déplacé).
  void updateHSpeedOverride(double value)  => _hSpeedOverride  = value;
  void updateAscentOverride(double value)  => _ascentOverride  = value;
  void updateDescentOverride(double value) => _descentOverride = value;

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
    // On n'accumule plus le temps TOTAL des segments qui montent. Sur un
    // segment de 60s qui monte 20m sur 200m de distance horizontale, le
    // randonneur a passé ~20/200 = 10% du temps en montée pure, soit ~6s.
    // Accumuler 60s gonflait artificiellement gainTime et sous-estimait le
    // taux de montée. On estime donc le temps de montée par proportionnalité
    // (elevGain / distM) × durationS.
    double gainTimeSec = 0, gainM = 0;
    for (final m in window) {
      if (m.elevGain > 2 && m.distanceM > 0) {
        final upFraction = (m.elevGain / m.distanceM).clamp(0.0, 1.0);
        gainTimeSec += m.actualSeconds * upFraction;
        gainM       += m.elevGain;
      }
    }
    final measuredAscentRate = gainTimeSec > 0
        ? gainM / (gainTimeSec / 3600.0)
        : _params.ascentRate;

    // ── Taux de descente ─────────────────────────────────────────────────────
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
    //
    // Seule la vitesse horizontale peut invalider toute la mesure : si on
    // marche à 0.3 km/h ou 25 km/h, le segment entier est suspect.
    //
    // Pour le D+ et D-, on ne rejette PAS la mesure entière si le taux est
    // irréaliste — on retombe sur le baseline du profil. Raison : sur des
    // segments courts avec peu de dénivelé (ex: 1m D+ sur 83m en 65s),
    // upFraction × duration = 0.78s → ascentRate = 4600 m/h → irréaliste,
    // mais la vitesse horizontale mesurée est valide. Rejeter le segment
    // entier bloque _calibrationWeight à 0 indéfiniment.
    if (measuredHSpeed < 0.5 || measuredHSpeed > 20) return;

    final safeAscentRate  = (measuredAscentRate  >= 50 && measuredAscentRate  <= 1500)
        ? measuredAscentRate
        : _params.ascentRate;   // fallback baseline si irréaliste
    final safeDescentRate = (measuredDescentRate >= 50 && measuredDescentRate <= 2000)
        ? measuredDescentRate
        : _params.descentRate;  // fallback baseline si irréaliste

    final measured = MunterParams(
      horizontalSpeed: measuredHSpeed,
      ascentRate:      safeAscentRate,
      descentRate:     safeDescentRate,
    );

    // ── Poids progressif ─────────────────────────────────────────────────────
    //
    // Correction v3 : basé sur le nombre CUMULATIF de segments acceptés, plus
    // sur le temps cumulé de la fenêtre (qui était plafonné en dur à ~20 min
    // par la fenêtre de 20 mesures × ~60s/segment, bloquant le poids à 0.40).
    //   - isCalibrated (0.5) à 10 segments.
    //   - poids plein (0.95) à 20 segments.
    // On garde 5% du baseline pour amortir les mesures aberrantes.
    _calibrationWeight =
        (_acceptedCount / _kSegmentsForFullWeight).clamp(0.0, _kMaxCalibrationWeight);

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
    'accepted':        _acceptedCount,
    'horizontalSpeed': _params.horizontalSpeed.toStringAsFixed(2),
    'ascentRate':      _params.ascentRate.toStringAsFixed(0),
    'descentRate':     _params.descentRate.toStringAsFixed(0),
  };

  // ── Persistance ────────────────────────────────────────────────────────────

  Map<String, dynamic> toSnapshot() => {
    'profile':      profile.signature,
    'accepted':     _acceptedCount,
    'measurements': _measurements.map((m) => {
      'd': m.distanceM,
      'g': m.elevGain,
      'l': m.elevLoss,
      's': m.actualSeconds,
    }).toList(),
    // Cadenas — persistés pour survivre à un kill
    'hSpeedLocked':    _hSpeedLocked,
    'ascentLocked':    _ascentLocked,
    'descentLocked':   _descentLocked,
    'hSpeedOverride':  _hSpeedOverride,
    'ascentOverride':  _ascentOverride,
    'descentOverride': _descentOverride,
  };

  bool restoreFromSnapshot(Map<String, dynamic> snapshot) {
    final sig = snapshot['profile'] as String?;
    if (sig == null || sig != profile.signature) return false;

    final raw = snapshot['measurements'];
    if (raw is! List) return false;

    _measurements.clear();
    _acceptedCount = 0;
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

    // Restaure le compteur cumulatif. Rétro-compat : les anciens snapshots
    // (sans 'accepted') retombent sur le nombre de mesures restaurées.
    final savedAccepted = (snapshot['accepted'] as num?)?.toInt();
    _acceptedCount = savedAccepted ?? _measurements.length;

    if (_measurements.isNotEmpty) _recalibrate();

    // Restaure les cadenas
    _hSpeedLocked    = snapshot['hSpeedLocked']  as bool? ?? false;
    _ascentLocked    = snapshot['ascentLocked']  as bool? ?? false;
    _descentLocked   = snapshot['descentLocked'] as bool? ?? false;
    _hSpeedOverride  = (snapshot['hSpeedOverride']  as num?)?.toDouble();
    _ascentOverride  = (snapshot['ascentOverride']  as num?)?.toDouble();
    _descentOverride = (snapshot['descentOverride'] as num?)?.toDouble();

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
