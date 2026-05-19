// lib/core/audio/recording_service.dart
//
// Enregistrement audio — partagé entre tous les modules qui en ont besoin.
// Migré depuis Hey Snowy (lib/services/audio_service.dart).
//
// Différences :
//   - ChangeNotifier pour que l'UI suive l'état (idle/recording)
//   - Singleton accessible globalement comme GpsService
//   - Permission micro demandée explicitement à l'init

import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class RecordingService extends ChangeNotifier {
  static final RecordingService _instance = RecordingService._();
  factory RecordingService() => _instance;
  RecordingService._();

  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _isInitialized = false;
  bool _isRecording = false;
  String? _currentFilePath;
  DateTime? _recordingStart;

  bool   get isRecording      => _isRecording;
  String? get currentFilePath => _currentFilePath;
  Duration get currentDuration => _recordingStart == null
      ? Duration.zero
      : DateTime.now().difference(_recordingStart!);

  /// Initialise le recorder et demande la permission micro.
  /// Retourne false si la permission est refusée.
  Future<bool> init() async {
    if (_isInitialized) return true;
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      debugPrint('[recording] permission micro refusée');
      return false;
    }
    await _recorder.openRecorder();
    _isInitialized = true;
    return true;
  }

  /// Démarre un enregistrement. Retourne le chemin du fichier (ou null si KO).
  Future<String?> start() async {
    if (!_isInitialized && !await init()) return null;

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

  @override
  Future<void> dispose() async {
    await _recorder.closeRecorder();
    _isInitialized = false;
    super.dispose();
  }
}
