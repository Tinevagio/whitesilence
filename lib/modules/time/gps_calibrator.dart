// lib/modules/time/gps_calibrator.dart
//
// Calibrateur de MunterEngine basé sur les segments GPS réels.
//
// ── Différences vs version précédente ────────────────────────────────────────
//
//  1. S'abonne au *Stream<Position>* du GpsService (fixes réels uniquement),
//     plus au ChangeNotifier. Fini les ré-évaluations sur notify parasite
//     (permission, start/stop) qui cassaient un segment en cours.
//
//  2. Horodatage = pos.timestamp (l'heure du fix), plus DateTime.now().
//     Indispensable en arrière-plan : Android groupe (coalesce) les fixes et
//     les livre en lot ; DateTime.now() écraserait toutes ces durées.
//
//  3. Accumulation sur les points INTERMÉDIAIRES : la distance est la somme
//     des sous-distances (pas la ligne droite départ→arrivée) et le D+/D- est
//     intégré paire par paire depuis le DEM. Sur une montée en lacets, la
//     ligne droite sous-estimait l'effort → isochrones trop optimistes.
//
//  4. Lookups DEM SÉRIALISÉS : les positions sont traitées une par une via une
//     file. onPosition étant async (await getElevation), deux fixes rapprochés
//     pouvaient s'entrelacer autour du await et corrompre l'état du segment.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/elevation/elevation_provider.dart';
import '../../core/gps/gps_service.dart';
import 'munter.dart';

// ── Seuils de filtrage ────────────────────────────────────────────────────────

const _minSegmentDurationS  = 60.0;
const _minSegmentDistanceM  = 50.0;
const _maxSpeedKmh          = 15.0;
const _minSpeedKmh          = 0.3;   // en dessous → pause (par paire de fixes)
const _maxGpsAccuracyM      = 30.0;
const _maxAscentRateM_h     = 1500.0;
const _maxSlopePct          = 80.0;

/// Marge de bruit vertical tolérée par paire de fixes, en plus de la distance
/// horizontale. Si |Δalt| dépasse (distance + cette marge), on considère que
/// c'est un artefact (bruit d'altitude GPS, ou bascule de source DEM↔GPS) et
/// on ignore la contribution verticale de cette paire — sans jeter la distance.
const _maxPairVertNoiseM    = 5.0;

class GpsCalibrator {
  final MunterEngine munter;
  ElevationProvider? _dem;

  // ── État du segment en cours ───────────────────────────────────────────────
  DateTime? _segStart;     // timestamp du 1er fix du segment
  double?   _prevLat;
  double?   _prevLng;
  double?   _prevAlt;      // altitude (DEM si dispo, sinon GPS) du fix précédent
  DateTime? _prevStamp;
  double    _accDistanceM = 0;
  double    _accGain      = 0;
  double    _accLoss      = 0;

  // ── Stats ──────────────────────────────────────────────────────────────────
  int    _segmentsAccepted = 0;
  int    _segmentsRejected = 0;
  String _lastRejectReason = '';

  int    get segmentsAccepted => _segmentsAccepted;
  int    get segmentsRejected => _segmentsRejected;
  String get lastRejectReason => _lastRejectReason;

  /// Callback optionnel : appelé après chaque segment évalué (accepté ou
  /// rejeté). Permet au TimeController de rafraîchir l'UI calibration.
  void Function()? onUpdate;

  // ── Abonnement & file de traitement ────────────────────────────────────────
  StreamSubscription<Position>? _sub;
  final List<Position> _queue = [];
  bool _pumping = false;

  GpsCalibrator({required this.munter, ElevationProvider? dem}) : _dem = dem;

  void updateDem(ElevationProvider dem) => _dem = dem;

  /// Branche le calibrateur sur le Stream<Position> global.
  /// À appeler une fois au démarrage du module Temps.
  void attachToGpsService() {
    _sub ??= GpsService().positions.listen(_enqueue);
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _queue.clear();
  }

  // ── File : garantit un traitement strictement séquentiel ───────────────────

  void _enqueue(Position pos) {
    _queue.add(pos);
    // Garde-fou : si le DEM était très lent, on borne la file pour ne pas
    // gonfler indéfiniment. En pratique un lookup HGT prend ~ms.
    if (_queue.length > 200) {
      debugPrint('[calib] file saturée (${_queue.length}), purge des plus vieux');
      _queue.removeRange(0, _queue.length - 200);
    }
    _pump();
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (_queue.isNotEmpty) {
        final pos = _queue.removeAt(0);
        await _ingest(pos);
      }
    } finally {
      _pumping = false;
    }
  }

  /// Point d'entrée public conservé (tests, appels externes éventuels).
  /// Passe par la même file que le stream.
  Future<void> onPosition(Position pos) async {
    _enqueue(pos);
  }

  // ── Cœur : ingestion d'un fix ──────────────────────────────────────────────

  /// Heure du fix. Certains appareils renvoient un timestamp epoch 0 ;
  /// on retombe alors sur l'heure courante (au moins cohérente entre appels).
  DateTime _stampOf(Position pos) {
    final t = pos.timestamp;
    return t.millisecondsSinceEpoch <= 0 ? DateTime.now() : t;
  }

  Future<double> _elevation(double lat, double lng, double gpsAlt) async {
    final dem = _dem;
    if (dem == null) return gpsAlt;
    try {
      return await dem.getElevation(lat, lng);
    } catch (_) {
      return gpsAlt; // hors-ligne / tuile absente → altitude GPS (bruitée)
    }
  }

  void _startSegment(Position pos, DateTime stamp, double alt) {
    _segStart      = stamp;
    _prevStamp     = stamp;
    _prevLat       = pos.latitude;
    _prevLng       = pos.longitude;
    _prevAlt       = alt;
    _accDistanceM  = 0;
    _accGain       = 0;
    _accLoss       = 0;
  }

  Future<void> _ingest(Position pos) async {
    if (pos.accuracy > _maxGpsAccuracyM) return;

    final stamp = _stampOf(pos);
    final alt   = await _elevation(pos.latitude, pos.longitude, pos.altitude);

    if (_prevLat == null) {
      _startSegment(pos, stamp, alt);
      return;
    }

    final dt = stamp.difference(_prevStamp!).inMilliseconds / 1000.0;
    if (dt <= 0) {
      // Fix hors-ordre ou horodatage dupliqué (coalescing) : on garde le plus
      // récent comme référence mais on n'accumule rien (durée non valide).
      _prevLat   = pos.latitude;
      _prevLng   = pos.longitude;
      _prevAlt   = alt;
      _prevStamp = stamp;
      return;
    }

    final segDist = Geolocator.distanceBetween(
      _prevLat!, _prevLng!, pos.latitude, pos.longitude,
    );
    final pairSpeedKmh = (segDist / 1000.0) / (dt / 3600.0);

    // ── Pause détectée sur cette paire ────────────────────────────────────────
    // On ne contamine pas le segment avec du temps à l'arrêt. Si le segment
    // courant atteint déjà les seuils, on le clôt (c'est un vrai segment de
    // mouvement qui se termine à une pause) ; sinon on le jette. Dans les deux
    // cas on redémarre un segment propre au point courant.
    if (pairSpeedKmh < _minSpeedKmh) {
      final duration = stamp.difference(_segStart!).inMilliseconds / 1000.0;
      if (duration >= _minSegmentDurationS && _accDistanceM >= _minSegmentDistanceM) {
        await _evaluateSegment(_accDistanceM, _accGain, _accLoss, duration);
      }
      _startSegment(pos, stamp, alt);
      return;
    }

    // ── Accumulation ──────────────────────────────────────────────────────────
    final dAlt = alt - _prevAlt!;
    if (dAlt.abs() <= segDist + _maxPairVertNoiseM) {
      if (dAlt > 0) _accGain += dAlt; else _accLoss += -dAlt;
    }
    _accDistanceM += segDist;
    _prevLat   = pos.latitude;
    _prevLng   = pos.longitude;
    _prevAlt   = alt;
    _prevStamp = stamp;

    final duration = stamp.difference(_segStart!).inMilliseconds / 1000.0;
    if (duration >= _minSegmentDurationS && _accDistanceM >= _minSegmentDistanceM) {
      await _evaluateSegment(_accDistanceM, _accGain, _accLoss, duration);
      // Nouveau segment qui démarre exactement où finit le précédent.
      _startSegment(pos, stamp, alt);
    }
  }

  // ── Évaluation d'un segment accumulé ───────────────────────────────────────

  Future<void> _evaluateSegment(
    double distM,
    double elevGain,
    double elevLoss,
    double durationS,
  ) async {
    final speedKmh = (distM / 1000.0) / (durationS / 3600.0);
    if (speedKmh > _maxSpeedKmh) {
      _reject('vitesse ${speedKmh.toStringAsFixed(1)} km/h > $_maxSpeedKmh');
      return;
    }
    if (speedKmh < _minSpeedKmh) {
      _reject('vitesse ${speedKmh.toStringAsFixed(1)} km/h < $_minSpeedKmh (pause)');
      return;
    }

    final elevTotal = elevGain + elevLoss;
    final double slopePct = distM > 0 ? elevTotal / distM * 100 : 0.0;
    if (slopePct > _maxSlopePct) {
      _reject('pente ${slopePct.toStringAsFixed(0)}% > $_maxSlopePct');
      return;
    }

    if (elevGain > 0) {
      final ascentRate = elevGain / (durationS / 3600.0);
      if (ascentRate > _maxAscentRateM_h) {
        _reject('D+ ${ascentRate.toStringAsFixed(0)} m/h irréaliste');
        return;
      }
    }

    munter.addGpsMeasurement(
      distanceM:     distM,
      elevGain:      elevGain,
      elevLoss:      elevLoss,
      actualSeconds: durationS,
    );
    _segmentsAccepted++;

    debugPrint('Calibration ✓ #$_segmentsAccepted : '
        '${distM.round()}m (D+${elevGain.round()} D-${elevLoss.round()}) '
        'en ${durationS.round()}s (${speedKmh.toStringAsFixed(1)} km/h) '
        '→ poids=${(munter.calibrationWeight * 100).toStringAsFixed(0)}%');
    onUpdate?.call();
  }

  void _reject(String reason) {
    _segmentsRejected++;
    _lastRejectReason = reason;
    debugPrint('Calibration ✗ : $reason');
    onUpdate?.call();
  }

  void reset() {
    _segStart      = null;
    _prevLat       = null;
    _prevLng       = null;
    _prevAlt       = null;
    _prevStamp     = null;
    _accDistanceM  = 0;
    _accGain       = 0;
    _accLoss       = 0;
    _segmentsAccepted = 0;
    _segmentsRejected = 0;
    _lastRejectReason = '';
    _queue.clear();
  }

  Map<String, String> get report => {
    'segments':    '$_segmentsAccepted acceptés, $_segmentsRejected rejetés',
    'poids':       '${(munter.calibrationWeight * 100).toStringAsFixed(0)}%',
    'calibré':     munter.isCalibrated
        ? 'Oui'
        : 'Non (${_segmentsAccepted < 3 ? "pas assez" : "en cours…"})',
    'hSpeed':      '${munter.currentParams.horizontalSpeed.toStringAsFixed(2)} km/h',
    'ascentRate':  '${munter.currentParams.ascentRate.toStringAsFixed(0)} m/h',
    'descentRate': '${munter.currentParams.descentRate.toStringAsFixed(0)} m/h',
  };
}
