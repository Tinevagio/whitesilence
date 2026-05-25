// lib/modules/time/gps_calibrator.dart
//
// Calibrateur de MunterEngine basé sur les segments GPS réels.
// Migré depuis TimeToGo. Différence : s'abonne au GpsService partagé.

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
const _minSpeedKmh          = 0.3;
const _maxGpsAccuracyM      = 30.0;
const _maxAscentRateM_h     = 1500.0;
const _maxSlopePct          = 80.0;

class _GpsPoint {
  final double lat;
  final double lng;
  final double alt;
  final double accuracy;
  final DateTime time;

  const _GpsPoint({
    required this.lat,
    required this.lng,
    required this.alt,
    required this.accuracy,
    required this.time,
  });
}

class GpsCalibrator {
  final MunterEngine munter;
  ElevationProvider? _dem;

  _GpsPoint? _segmentStart;
  _GpsPoint? _lastPoint;

  int    _segmentsAccepted = 0;
  int    _segmentsRejected = 0;
  String _lastRejectReason = '';

  int    get segmentsAccepted => _segmentsAccepted;
  int    get segmentsRejected => _segmentsRejected;
  String get lastRejectReason => _lastRejectReason;

  /// Callback optionnel : appelé après chaque segment évalué (accepté ou
  /// rejeté). Permet au TimeController d'appeler notifyListeners() pour
  /// rafraîchir l'UI calibration en temps réel.
  void Function()? onUpdate;

  // Abonnement au GpsService partagé
  VoidCallback? _gpsListener;

  GpsCalibrator({required this.munter, ElevationProvider? dem}) : _dem = dem;

  void updateDem(ElevationProvider dem) => _dem = dem;

  /// Branche le calibrateur sur le GpsService global.
  /// À appeler une fois au démarrage du module Temps.
  void attachToGpsService() {
    final gps = GpsService();
    _gpsListener = () {
      final pos = gps.last;
      if (pos != null) onPosition(pos);
    };
    gps.addListener(_gpsListener!);
  }

  void dispose() {
    if (_gpsListener != null) {
      GpsService().removeListener(_gpsListener!);
      _gpsListener = null;
    }
  }

  Future<void> onPosition(Position pos) async {
    if (pos.accuracy > _maxGpsAccuracyM) return;

    final point = _GpsPoint(
      lat:      pos.latitude,
      lng:      pos.longitude,
      alt:      pos.altitude,
      accuracy: pos.accuracy,
      time:     DateTime.now(),
    );

    if (_segmentStart == null) {
      _segmentStart = point;
      _lastPoint    = point;
      return;
    }

    _lastPoint = point;

    final durationS = point.time.difference(_segmentStart!.time).inMilliseconds / 1000.0;
    final distM     = Geolocator.distanceBetween(
      _segmentStart!.lat, _segmentStart!.lng,
      point.lat, point.lng,
    );

    if (durationS < _minSegmentDurationS || distM < _minSegmentDistanceM) {
      return;
    }

    await _evaluateSegment(_segmentStart!, point, distM, durationS);
    _segmentStart = point;
  }

  Future<void> _evaluateSegment(
    _GpsPoint start,
    _GpsPoint end,
    double distM,
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

    double elevGain = 0, elevLoss = 0;
    try {
      final dem = _dem;
      if (dem != null) {
        final altStart = await dem.getElevation(start.lat, start.lng);
        final altEnd   = await dem.getElevation(end.lat, end.lng);
        final diff     = altEnd - altStart;
        elevGain = diff > 0 ? diff : 0;
        elevLoss = diff < 0 ? -diff : 0;
      } else {
        final diff = end.alt - start.alt;
        elevGain = diff > 0 ? diff : 0;
        elevLoss = diff < 0 ? -diff : 0;
      }
    } catch (_) {
      final diff = end.alt - start.alt;
      elevGain = diff > 0 ? diff : 0;
      elevLoss = diff < 0 ? -diff : 0;
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
        '${distM.round()}m en ${durationS.round()}s '
        '(${speedKmh.toStringAsFixed(1)} km/h) '
        '→ poids=${(munter.calibrationWeight*100).toStringAsFixed(0)}%');
    onUpdate?.call();
  }

  void _reject(String reason) {
    _segmentsRejected++;
    _lastRejectReason = reason;
    debugPrint('Calibration ✗ : $reason');
    _segmentStart = _lastPoint;
    onUpdate?.call();
  }

  void reset() {
    _segmentStart     = null;
    _lastPoint        = null;
    _segmentsAccepted = 0;
    _segmentsRejected = 0;
    _lastRejectReason = '';
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