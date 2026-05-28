import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Service GPS unifié pour WhiteSilence.
///
/// Un seul stream de positions, partagé entre tous les modules (time, snow,
/// avalanche, tour). Évite les batteries vidées par plusieurs subscribers.
///
/// Philosophie WhiteSilence : pas de tracking, position en mémoire uniquement
/// sauf si l'utilisateur enregistre explicitement une sortie ou une observation.
///
/// ── Gestion du cycle de vie permission ─────────────────────────────────────
///
/// Cas classique : l'utilisateur refuse la permission deux fois → Android la
/// passe en `deniedForever`. Plus aucun popup système ne s'affiche. L'utilisateur
/// doit alors aller manuellement dans les Réglages Android pour l'accorder.
///
/// Quand il revient dans l'app après avoir accordé manuellement, on doit
/// retenter `start()` — sinon l'app reste sans GPS jusqu'au prochain kill.
/// C'est ce que fait `_LifecycleObserver` : il écoute les retours au premier
/// plan et relance `start()` si on n'a pas encore de position.
///
/// `lastPermissionStatus` expose le dernier état connu pour permettre à l'UI
/// d'afficher un message clair ("Aller dans les Réglages") quand
/// `deniedForever`.
class GpsService extends ChangeNotifier {
  static final GpsService _instance = GpsService._();
  factory GpsService() => _instance;
  GpsService._() {
    _lifecycleObserver = _LifecycleObserver(this);
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
  }

  StreamSubscription<Position>? _sub;
  Position? _last;
  bool _isActive = false;
  late final _LifecycleObserver _lifecycleObserver;

  /// Dernier statut de permission connu. `null` tant que `start()` n'a pas
  /// été appelé une première fois. Utile pour afficher un bandeau d'aide
  /// quand `deniedForever`.
  LocationPermission? _lastPermissionStatus;
  LocationPermission? get lastPermissionStatus => _lastPermissionStatus;

  /// Vrai si le service de localisation système (GPS du téléphone) est
  /// désactivé — distinct du refus de permission.
  bool _serviceDisabled = false;
  bool get serviceDisabled => _serviceDisabled;

  Position? get last => _last;
  LatLng? get lastLatLng =>
      _last == null ? null : LatLng(_last!.latitude, _last!.longitude);
  bool get isActive => _isActive;

  /// L'utilisateur a refusé deux fois → Android bloque les popups. Il faut
  /// l'orienter vers les Réglages système.
  bool get isPermissionDeniedForever =>
      _lastPermissionStatus == LocationPermission.deniedForever;

  /// Démarre le tracking GPS. Idempotent : sans danger d'appel multiple.
  /// Peut être rappelé manuellement (par exemple depuis un écran "Réglages
  /// GPS" après que l'utilisateur a accordé la permission).
  Future<void> start({
    int distanceFilterMeters = 10,
    LocationAccuracy accuracy = LocationAccuracy.best,
  }) async {
    if (_isActive) return;

    final ok = await _ensurePermission();
    if (!ok) {
      // On notifie quand même pour que l'UI puisse réagir (afficher un
      // bandeau "Activer GPS", "Aller dans les Réglages", etc.).
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

      // Position initiale (sans attendre le premier tick du stream)
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
    notifyListeners();
  }

  /// Vérifie et demande la permission. Met à jour `_lastPermissionStatus`
  /// et `_serviceDisabled` pour que l'UI puisse réagir précisément.
  Future<bool> _ensurePermission() async {
    _serviceDisabled = !(await Geolocator.isLocationServiceEnabled());
    if (_serviceDisabled) {
      debugPrint('[GPS] Service de localisation désactivé sur le téléphone');
      return false;
    }

    var p = await Geolocator.checkPermission();
    debugPrint('[GPS] permission initiale: $p');

    if (p == LocationPermission.denied) {
      // Premier ou deuxième prompt : Android affichera le popup système.
      // Si refus déjà deux fois, on récupère deniedForever sans popup.
      p = await Geolocator.requestPermission();
      debugPrint('[GPS] permission après request: $p');
    }

    _lastPermissionStatus = p;

    if (p == LocationPermission.deniedForever) {
      debugPrint('[GPS] deniedForever — l\'utilisateur doit aller dans '
          'les Réglages Android > Apps > WhiteSilence > Autorisations');
    }

    return p == LocationPermission.whileInUse ||
           p == LocationPermission.always;
  }

  /// Ouvre les réglages d'app Android pour que l'utilisateur puisse
  /// accorder manuellement la permission. À appeler depuis un bouton
  /// "Ouvrir les Réglages" dans l'UI quand `isPermissionDeniedForever`.
  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  /// Ouvre les réglages système de localisation (pour activer le GPS global).
  /// Utile quand `serviceDisabled == true`.
  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }
}

/// Observe le cycle de vie de l'app pour relancer le GPS quand l'utilisateur
/// revient au premier plan après avoir potentiellement accordé la permission
/// dans les Réglages Android.
class _LifecycleObserver with WidgetsBindingObserver {
  final GpsService service;
  _LifecycleObserver(this.service);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !service.isActive) {
      // L'app revient au premier plan et le GPS n'est toujours pas actif.
      // L'utilisateur a peut-être accordé la permission dans les Réglages
      // entre-temps — on retente.
      debugPrint('[GPS] App resumed, retry start()');
      service.start();
    }
  }
}