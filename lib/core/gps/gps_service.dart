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
/// ── Deux canaux de diffusion ─────────────────────────────────────────────────
///
///  1. ChangeNotifier (notifyListeners) — pour l'UI (recentrage carte, badges
///     de permission…). Émet sur TOUT changement d'état observable : nouvelle
///     position, mais aussi start/stop, changement de permission, service
///     désactivé. C'est volontaire : l'UI veut se repeindre dans tous ces cas.
///
///  2. `positions` (Stream<Position>) — pour les consommateurs qui ont besoin
///     du *flux de fixes réels uniquement* (typiquement le GpsCalibrator).
///     Ce stream n'émet QUE des positions GPS live. Il n'émet jamais la
///     dernière position connue (getLastKnownPosition), ni les événements de
///     permission/cycle de vie. C'est ce qui évite que le calibrateur traite
///     deux fois le même point ou casse un segment sur un notify parasite.
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

  /// Diffuseur des fixes GPS réels. Broadcast : plusieurs abonnés possibles.
  ///
  /// Ce singleton vit toute la durée de l'app : on ne ferme jamais ce
  /// controller (un broadcast fermé est définitif et casserait un start()
  /// ultérieur).
  final StreamController<Position> _positions =
      StreamController<Position>.broadcast();

  /// Flux des fixes GPS live uniquement. Voir la doc de classe.
  Stream<Position> get positions => _positions.stream;

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
          // Canal "fixes réels" → calibrateur. On ne pousse ICI que les
          // vrais fixes du stream Geolocator, jamais last-known.
          if (!_positions.isClosed) _positions.add(pos);
          // Canal UI.
          notifyListeners();
        },
        onError: (e) {
          debugPrint('[GPS] erreur stream: $e');
        },
      );

      _isActive = true;
      // On garde la dernière position connue pour l'UI (recentrage immédiat),
      // MAIS on ne la pousse pas dans `positions` : un point potentiellement
      // très ancien fausserait le départ de segment du calibrateur.
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
/// l'Activity soit encore dans un état éligible. Dart envoie juste
/// "start" / "stop" au channel ; MainActivity.kt démarre/arrête réellement le
/// service depuis onStop()/onStart(), qui sont au bon moment.
class _LifecycleObserver with WidgetsBindingObserver {
  final GpsService service;
  _LifecycleObserver(this.service);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        service.startForegroundService();
        break;
      case AppLifecycleState.resumed:
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
