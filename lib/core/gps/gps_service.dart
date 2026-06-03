import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

/// Service GPS unifié pour WhiteSilence.
///
/// Un seul stream de positions, partagé entre tous les modules.
///
/// ── GPS en arrière-plan ──────────────────────────────────────────────────────
///
/// Android 8+ suspend les streams GPS quand l'app n'est plus en foreground
/// (écran verrouillé, autre app au premier plan). Pour la calibration Munter,
/// il faut que les positions continuent d'arriver même en veille.
///
/// Solution : un Foreground Service Android (GpsForegroundService.kt) qui
/// maintient le processus Flutter en vie. Ce service affiche une notification
/// persistante "GPS actif" pendant qu'il tourne.
///
/// Cycle de vie du service :
///   - Démarre quand l'app passe en arrière-plan (AppLifecycleState.paused)
///   - S'arrête quand l'app revient au premier plan (AppLifecycleState.resumed)
///   - S'arrête aussi si l'utilisateur tape "Arrêter" dans la notification
///   - S'arrête si l'utilisateur swipe l'app hors du recents
///
/// On N'utilise PAS ACCESS_BACKGROUND_LOCATION (review Google Play complexe).
/// La permission "En cours d'utilisation seulement" suffit avec un Foreground
/// Service déclaré avec foregroundServiceType="location".
///
/// ── Permissions ──────────────────────────────────────────────────────────────
///
/// permission_handler gère toutes les permissions (GPS + micro) pour éviter
/// le conflit de callback Android avec geolocator (même éditeur Baseflow).
class GpsService extends ChangeNotifier {
  static final GpsService _instance = GpsService._();
  factory GpsService() => _instance;
  GpsService._() {
    _lifecycleObserver = _LifecycleObserver(this);
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
  }

  static const _channel = MethodChannel('gps_foreground_service/control');

  StreamSubscription<Position>? _sub;
  Position? _last;
  bool _isActive = false;
  bool _foregroundServiceRunning = false;
  late final _LifecycleObserver _lifecycleObserver;

  ph.PermissionStatus? _lastPermissionStatus;
  ph.PermissionStatus? get lastPermissionStatus => _lastPermissionStatus;

  bool _serviceDisabled = false;
  bool get serviceDisabled => _serviceDisabled;

  Position? get last => _last;
  LatLng? get lastLatLng =>
      _last == null ? null : LatLng(_last!.latitude, _last!.longitude);
  bool get isActive => _isActive;

  bool get isPermissionDeniedForever =>
      _lastPermissionStatus == ph.PermissionStatus.permanentlyDenied;

  Future<void> start({
    int distanceFilterMeters = 10,
    LocationAccuracy accuracy = LocationAccuracy.best,
  }) async {
    if (_isActive) return;

    final ok = await _ensurePermission();
    if (!ok) {
      notifyListeners();
      return;
    }

    try {
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
          debugPrint('[GPS] erreur stream: $e');
        },
      );

      _isActive = true;
      _last = await Geolocator.getLastKnownPosition();
      notifyListeners();
    } catch (e) {
      debugPrint('[GPS] erreur start: $e');
      _isActive = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _isActive = false;
    await _stopForegroundService();
    notifyListeners();
  }

  // ── Foreground Service ────────────────────────────────────────────────────

  /// Démarre le Foreground Service Android pour maintenir le GPS en veille.
  /// Appelé quand l'app passe en arrière-plan (AppLifecycleState.paused).
  /// Sans danger si le service est déjà lancé.
  Future<void> startForegroundService() async {
    if (_foregroundServiceRunning || !_isActive) return;

    // Android 14+ (targetSDK ≥ 34) : le Foreground Service de type "location"
    // ne peut démarrer que si la permission GPS est déjà granted au moment
    // de l'appel. Sinon → SecurityException fatale.
    // On vérifie avant d'appeler le service natif.
    final status = await ph.Permission.locationWhenInUse.status;
    if (!status.isGranted && !status.isLimited) {
      debugPrint('[GPS] Foreground service ignoré — permission non accordée ($status)');
      return;
    }

    try {
      await _channel.invokeMethod('start');
      _foregroundServiceRunning = true;
      debugPrint('[GPS] Foreground service démarré');
    } catch (e) {
      debugPrint('[GPS] Foreground service non disponible: $e');
    }
  }

  /// Arrête le Foreground Service. Appelé quand l'app revient au premier plan.
  Future<void> _stopForegroundService() async {
    if (!_foregroundServiceRunning) return;
    try {
      await _channel.invokeMethod('stop');
      _foregroundServiceRunning = false;
      debugPrint('[GPS] Foreground service arrêté');
    } catch (e) {
      debugPrint('[GPS] Erreur arrêt foreground service: $e');
    }
  }

  // ── Permissions ───────────────────────────────────────────────────────────

  Future<bool> _ensurePermission() async {
    _serviceDisabled = !(await Geolocator.isLocationServiceEnabled());
    if (_serviceDisabled) {
      debugPrint('[GPS] Service de localisation désactivé sur le téléphone');
      return false;
    }

    var status = await ph.Permission.locationWhenInUse.status;
    debugPrint('[GPS] permission initiale: $status');

    if (status.isDenied) {
      status = await ph.Permission.locationWhenInUse.request();
      debugPrint('[GPS] permission après request: $status');
    }

    _lastPermissionStatus = status;

    if (status.isPermanentlyDenied) {
      debugPrint('[GPS] permanentlyDenied — l\'utilisateur doit aller dans '
          'les Réglages Android > Apps > WhiteSilence > Autorisations');
    }

    return status.isGranted || status.isLimited;
  }

  Future<void> openAppSettings() async => ph.openAppSettings();
  Future<void> openLocationSettings() async =>
      Geolocator.openLocationSettings();
}

// ── Lifecycle Observer ────────────────────────────────────────────────────────

/// Gère le cycle de vie GPS.
///
/// Sur Android 14, startForegroundService() de type "location" exige que
/// l'Activity soit encore dans un état éligible (visible ou en train de
/// passer en arrière-plan via onStop()). Appeler depuis AppLifecycleState.paused
/// est trop tardif — l'Activity est déjà non-éligible.
///
/// Solution : Dart envoie juste "start" / "stop" au channel Kotlin.
/// MainActivity.kt démarre effectivement le service depuis onStop() et
/// l'arrête depuis onStart() — ces callbacks Android sont au bon moment.
class _LifecycleObserver with WidgetsBindingObserver {
  final GpsService service;
  _LifecycleObserver(this.service);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        // Signaler l'intention à Kotlin — le démarrage effectif se fait
        // dans MainActivity.onStop() qui est appelé juste après.
        service.startForegroundService();
        break;
      case AppLifecycleState.resumed:
        // Signaler l'arrêt à Kotlin + retenter start() si GPS inactif.
        service._stopForegroundService();
        if (!service.isActive) {
          debugPrint('[GPS] App resumed, retry start()');
          service.start();
        }
        break;
      default:
        break;
    }
  }
}
