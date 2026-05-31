// lib/modules/snow/snow_controller.dart
//
// Contrôleur du module Neige.
//
// Orchestre :
//   - l'enregistrement d'observations vocales (bouton micro)
//   - la persistance immédiate (audio + GPS, AVANT le traitement IA)
//   - le pipeline batch (transcription + IA + upload Supabase)
//   - l'upload direct des obs rapides (sans pipeline IA)
//   - le chargement des obs existantes pour les afficher sur la carte
//   - le partage communautaire opt-in/out
//
// Le wake word n'est PAS démarré ici (cf. Phase 5).
//
// ── Deux chemins d'upload ────────────────────────────────────────────────────
//
// processPending() : pour les obs VOCALES uniquement.
//   → charge les obs pending, lance Whisper+IA sur celles qui ont un audioPath,
//     puis upload Supabase. Ne doit pas être appelé depuis une obs rapide.
//
// uploadQuickObservation(obs) : pour les obs RAPIDES uniquement.
//   → upload Supabase direct si shareWithCommunity et obs.isEnriched.
//     Pas de Whisper, pas d'IA. Ne touche pas aux obs vocales en attente.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/audio/recording_service.dart';
import '../../core/audio/sound_service.dart';
import '../../core/gps/gps_service.dart';
import 'models/observation.dart';
import 'services/processing_service.dart';
import 'services/supabase_service.dart';
import 'services/wake_word_service.dart';
import 'snow_dao.dart';

/// État global du module Neige.
enum SnowStatus {
  idle,        // rien en cours
  recording,   // micro actif
  processing,  // pipeline batch (Whisper + IA + Supabase)
}

class SnowController extends ChangeNotifier {
  static final SnowController _instance = SnowController._();
  factory SnowController() => _instance;
  SnowController._();

  final RecordingService  _recording   = RecordingService();
  final SoundService      _sound       = SoundService();
  final GpsService        _gps         = GpsService();
  final SnowDao           _dao         = SnowDao();
  final ProcessingService _processing  = ProcessingService();
  final SupabaseService   _supabase    = SupabaseService();

  // ── État ──────────────────────────────────────────────────────────────────
  SnowStatus _status = SnowStatus.idle;
  SnowStatus get status => _status;

  bool get isRecording  => _status == SnowStatus.recording;
  bool get isProcessing => _status == SnowStatus.processing;

  List<Observation> _observations = [];
  List<Observation> get observations => List.unmodifiable(_observations);

  String _statusMessage = '';
  String get statusMessage => _statusMessage;

  int _progressCurrent = 0;
  int _progressTotal = 0;
  int get progressCurrent => _progressCurrent;
  int get progressTotal   => _progressTotal;

  // ── Préférence partage communautaire ──────────────────────────────────────
  bool _shareWithCommunity = true;
  bool get shareWithCommunity => _shareWithCommunity;

  Future<void> setShareWithCommunity(bool v) async {
    _shareWithCommunity = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('snow.shareWithCommunity', v);
    notifyListeners();
  }

  // ── Mode mains-libres (wake word) ─────────────────────────────────────────
  final WakeWordService _wakeWord = WakeWordService();
  bool _handsFreeEnabled = false;
  bool _wakeWordReady = false;

  bool get handsFreeEnabled => _handsFreeEnabled;
  bool get wakeWordReady => _wakeWordReady;

  Future<bool> enableHandsFree() async {
    if (_handsFreeEnabled) return true;

    final micResult = await _recording.init();
    if (micResult != RecordingInitResult.ok) {
      _statusMessage = micResult ==
              RecordingInitResult.permissionPermanentlyDenied
          ? 'Permission micro refusée — ouvre les Réglages Android'
          : 'Permission micro refusée';
      notifyListeners();
      return false;
    }

    if (!_wakeWordReady) {
      _wakeWordReady = await _wakeWord.init();
      if (!_wakeWordReady) {
        _statusMessage = 'Wake word indisponible (code natif manquant ?)';
        notifyListeners();
        return false;
      }
    }

    _wakeWord.onWakeWord = _onWakeWordDetected;
    _wakeWord.onStopWord = _onStopWordDetected;

    await _wakeWord.startListening();
    _handsFreeEnabled = true;
    _statusMessage = 'Mains libres actif — dis "hey snowy" pour enregistrer';
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('snow.handsFreeEnabled', true);
    return true;
  }

  Future<void> disableHandsFree() async {
    if (!_handsFreeEnabled) return;
    await _wakeWord.stopListening();
    _handsFreeEnabled = false;
    _statusMessage = '';
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('snow.handsFreeEnabled', false);
  }

  void _onWakeWordDetected() {
    debugPrint('[snow] wake word détecté → démarre obs');
    if (_status == SnowStatus.idle) startRecording();
  }

  void _onStopWordDetected() {
    debugPrint('[snow] stop word détecté → arrête obs');
    if (_status == SnowStatus.recording) stopRecording();
  }

  // ── Timer auto-stop ───────────────────────────────────────────────────────
  Timer? _autoStopTimer;
  static const _maxRecordingDuration = Duration(seconds: 15);

  // ── Démarrage ─────────────────────────────────────────────────────────────

  bool _started = false;
  Future<void> start() async {
    if (_started) return;
    _started = true;

    final prefs = await SharedPreferences.getInstance();
    _shareWithCommunity = prefs.getBool('snow.shareWithCommunity') ?? true;

    await _sound.init();
    await refreshObservations();

    // Lance processPending() au démarrage pour uploader les obs vocales
    // qui auraient pu rester pending (crash, hors-ligne, etc.).
    // Fire-and-forget.
    // ignore: discarded_futures
    processPending();
  }

  Future<void> refreshObservations() async {
    _observations = await _dao.loadAll();
    notifyListeners();
  }

  // ── Enregistrement ────────────────────────────────────────────────────────

  Future<void> startRecording() async {
    if (_status != SnowStatus.idle) return;

    final pos = _gps.last;
    if (pos == null) {
      _statusMessage = 'Position GPS indisponible';
      notifyListeners();
      return;
    }

    final audioPath = await _recording.start();
    if (audioPath == null) {
      _statusMessage = 'Micro indisponible (permission ?)';
      notifyListeners();
      return;
    }

    await _sound.bipStart();

    final altitude = pos.altitude;
    final obs = Observation(
      id:        DateTime.now().millisecondsSinceEpoch.toString(),
      lat:       pos.latitude,
      lon:       pos.longitude,
      altitudeM: altitude == 0.0 ? null : altitude,
      timestamp: DateTime.now(),
      audioPath: audioPath,
    );

    await _dao.save(obs);
    _observations.insert(0, obs);

    _status = SnowStatus.recording;
    _statusMessage = 'Décris la neige…';
    _autoStopTimer = Timer(_maxRecordingDuration, () {
      if (_status == SnowStatus.recording) stopRecording();
    });
    notifyListeners();
  }

  Future<void> stopRecording() async {
    if (_status != SnowStatus.recording) return;
    _autoStopTimer?.cancel();
    _autoStopTimer = null;
    await _recording.stop();
    await _sound.bipStop();
    _status = SnowStatus.idle;
    _statusMessage = '${_observations.length} obs en mémoire';
    notifyListeners();
  }

  // ── Pipeline batch (obs vocales uniquement) ───────────────────────────────

  /// Lance Whisper + IA + upload Supabase sur les obs vocales pending.
  /// NE PAS appeler depuis une obs rapide — utiliser uploadQuickObservation().
  Future<void> processPending() async {
    if (_status != SnowStatus.idle) return;

    final pending = await _dao.loadPending();
    if (pending.isEmpty) {
      _statusMessage = 'Aucune observation à traiter';
      notifyListeners();
      return;
    }

    _status = SnowStatus.processing;
    _progressCurrent = 0;
    _progressTotal   = pending.length;
    _statusMessage   = 'Traitement…';
    notifyListeners();

    final result = await _processing.processObservations(
      pending,
      onProgress: (current, total) {
        _progressCurrent = current;
        _progressTotal   = total;
        _statusMessage   = 'Traitement $current / $total';
        notifyListeners();
      },
      shareWithCommunity: _shareWithCommunity,
    );

    await refreshObservations();

    _status = SnowStatus.idle;
    _statusMessage = result.failed > 0
        ? '${result.processed} traitées, ${result.failed} échecs'
        : '${result.processed} traitées · ${result.uploaded} partagées';
    notifyListeners();
  }

  // ── Upload direct obs rapide ──────────────────────────────────────────────

  /// Upload Supabase direct pour une obs rapide (sans audio).
  /// Bypass complet du pipeline Whisper+IA — l'obs est déjà enrichie par
  /// l'utilisateur (snowType défini). Fire-and-forget depuis le sheet.
  Future<void> uploadQuickObservation(Observation obs) async {
    if (!_shareWithCommunity) {
      debugPrint('[snow] uploadQuickObservation: partage désactivé, skip');
      return;
    }
    if (!obs.isEnriched) {
      debugPrint('[snow] uploadQuickObservation: obs non enrichie, skip');
      return;
    }
    debugPrint('[snow] uploadQuickObservation: upload direct Supabase');
    final ok = await _supabase.uploadObservation(obs);
    if (ok) {
      obs.uploaded = true;
      await _dao.update(obs);
      debugPrint('[snow] uploadQuickObservation: uploadée');
    } else {
      debugPrint('[snow] uploadQuickObservation: échec réseau, sera retentée '
          'au prochain processPending()');
    }
  }

  // ── Lecture / suppression d'obs ───────────────────────────────────────────

  Future<void> deleteObservation(Observation obs) async {
    await _dao.delete(obs.id);
    _observations.removeWhere((o) => o.id == obs.id);
    notifyListeners();
  }

  Observation? findById(String id) {
    try {
      return _observations.firstWhere((o) => o.id == id);
    } catch (_) {
      return null;
    }
  }

  LatLng? _pendingFocus;
  LatLng? get pendingFocus => _pendingFocus;
  void requestFocusOn(LatLng latLng) {
    _pendingFocus = latLng;
    notifyListeners();
  }
  void consumeFocusRequest() {
    _pendingFocus = null;
  }

  @override
  void dispose() {
    _autoStopTimer?.cancel();
    _wakeWord.dispose();
    super.dispose();
  }
}
