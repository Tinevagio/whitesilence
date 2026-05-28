// lib/core/audio/recording_service.dart
//
// Enregistrement audio — partagé entre tous les modules qui en ont besoin.
// Migré depuis Hey Snowy (lib/services/audio_service.dart).
//
// Différences :
//   - ChangeNotifier pour que l'UI suive l'état (idle/recording)
//   - Singleton accessible globalement comme GpsService
//   - Permission micro demandée explicitement au premier tap utilisateur
//     (init() est appelé paresseusement depuis start()) — c'est l'approche
//     correcte côté Android car l'Activity est forcément en foreground.

import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

/// Résultat d'une tentative d'initialisation, pour que l'UI puisse réagir
/// précisément (snackbar info vs proposer "Ouvrir Réglages").
enum RecordingInitResult {
  ok,
  permissionDenied,            // refus simple, on peut redemander plus tard
  permissionPermanentlyDenied, // refus définitif, il faut aller dans Réglages
  recorderError,               // openRecorder() a échoué
}

class RecordingService extends ChangeNotifier {
  static final RecordingService _instance = RecordingService._();
  factory RecordingService() => _instance;
  RecordingService._();

  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _isInitialized = false;
  bool _isRecording = false;
  String? _currentFilePath;
  DateTime? _recordingStart;

  /// Dernier statut connu — exposé pour que l'UI affiche le bon message.
  ph.PermissionStatus? _lastPermissionStatus;
  ph.PermissionStatus? get lastPermissionStatus => _lastPermissionStatus;

  bool get isPermissionPermanentlyDenied =>
      _lastPermissionStatus == ph.PermissionStatus.permanentlyDenied;

  bool   get isRecording      => _isRecording;
  String? get currentFilePath => _currentFilePath;
  Duration get currentDuration => _recordingStart == null
      ? Duration.zero
      : DateTime.now().difference(_recordingStart!);

  /// Initialise le recorder et demande la permission micro.
  /// Retourne le détail de l'issue pour que l'UI puisse afficher le bon
  /// message à l'utilisateur (cf. RecordingInitResult).
  Future<RecordingInitResult> init() async {
    if (_isInitialized) return RecordingInitResult.ok;

    final status = await ph.Permission.microphone.request();
    _lastPermissionStatus = status;
    debugPrint('[recording] permission micro: $status');

    if (status == ph.PermissionStatus.permanentlyDenied) {
      // L'utilisateur a refusé plusieurs fois OU a un état système qui
      // bloque les popups. Il faut le guider vers les Réglages Android.
      return RecordingInitResult.permissionPermanentlyDenied;
    }
    if (status != ph.PermissionStatus.granted) {
      // Refus simple, on pourra redemander à la prochaine tentative.
      return RecordingInitResult.permissionDenied;
    }

    try {
      await _recorder.openRecorder();
      _isInitialized = true;
      return RecordingInitResult.ok;
    } catch (e) {
      debugPrint('[recording] openRecorder failed: $e');
      return RecordingInitResult.recorderError;
    }
  }

  /// Démarre un enregistrement. Retourne le chemin du fichier (ou null si KO).
  /// Pour un feedback UI précis, préférer `initWithResult()` puis `start()`.
  Future<String?> start() async {
    if (!_isInitialized) {
      final res = await init();
      if (res != RecordingInitResult.ok) return null;
    }

    // Si déjà en train d'enregistrer, on stoppe d'abord (sécurité)
    if (_recorder.isRecording) {
      await _recorder.stopRecorder();
    }

    final dir       = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _currentFilePath = '${dir.path}/obs_$timestamp.wav';

    await _recorder.startRecorder(
      toFile: _currentFilePath,
      codec: Codec.pcm16WAV,
    );

    _isRecording    = true;
    _recordingStart = DateTime.now();
    notifyListeners();
    return _currentFilePath;
  }

  /// Stoppe l'enregistrement. Retourne le chemin du fichier.
  Future<String?> stop() async {
    if (!_recorder.isRecording) return null;
    await _recorder.stopRecorder();
    _isRecording    = false;
    _recordingStart = null;
    notifyListeners();
    return _currentFilePath;
  }

  /// Ouvre les réglages d'app Android pour que l'utilisateur puisse
  /// accorder manuellement la permission micro. À appeler depuis un bouton
  /// "Ouvrir les Réglages" quand `isPermissionPermanentlyDenied`.
  Future<void> openAppSettings() async {
    await ph.openAppSettings();
  }

  @override
  Future<void> dispose() async {
    await _recorder.closeRecorder();
    _isInitialized = false;
    super.dispose();
  }
}