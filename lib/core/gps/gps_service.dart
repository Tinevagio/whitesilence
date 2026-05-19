import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Service GPS unifié pour WhiteSilence.
///
/// Un seul stream de positions, partagé entre tous les modules (time, snow,
/// avalanche, tour). Évite les batteries vidées par plusieurs subscribers.
///
/// Philosophie WhiteSilence : pas de tracking, position en mémoire uniquement
/// sauf si l'utilisateur enregistre explicitement une sortie ou une observation.
class GpsService extends ChangeNotifier {
  static final GpsService _instance = GpsService._();
  factory GpsService() => _instance;
  GpsService._();

  StreamSubscription<Position>? _sub;
  Position? _last;
  bool _isActive = false;

  Position? get last => _last;
  LatLng? get lastLatLng =>
      _last == null ? null : LatLng(_last!.latitude, _last!.longitude);
  bool get isActive => _isActive;

  /// Démarre le tracking GPS. À appeler au lancement de l'app.
  Future<void> start({
    int distanceFilterMeters = 10,
    LocationAccuracy accuracy = LocationAccuracy.best,
  }) async {
    if (_isActive) return;

    final permission = await _ensurePermission();
    if (!permission) return;

    _sub = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilterMeters,
      ),
    ).listen(
      (pos) {
        _last = pos;
        notifyListeners();
      },
      onError: (e) {
        debugPrint('[GPS] erreur: $e');
      },
    );

    _isActive = true;

    // Position initiale (sans attendre le premier tick du stream)
    try {
      _last = await Geolocator.getLastKnownPosition();
      if (_last != null) notifyListeners();
    } catch (_) {}
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _isActive = false;
  }

  Future<bool> _ensurePermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    return p == LocationPermission.whileInUse || p == LocationPermission.always;
  }
}
