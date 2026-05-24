// lib/modules/snow/snow_controller.dart
//
// Contrôleur du module Neige.
//
// Orchestre :
//   - l'enregistrement d'observations vocales (bouton micro)
//   - la persistance immédiate (audio + GPS, AVANT le traitement IA)
//   - le pipeline batch (transcription + IA + upload Supabase)
//   - le chargement des obs existantes pour les afficher sur la carte
//   - le partage communautaire opt-in/out
//
// Le wake word n'est PAS démarré ici (cf. Phase 5).

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/audio/recording_service.dart';
import '../../core/audio/sound_service.dart';
import '../../core/gps/gps_service.dart';
import 'models/observation.dart';
import 'services/processing_service.dart';
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

  final RecordingService _recording = RecordingService();
  final SoundService     _sound     = SoundService();
  final GpsService       _gps       = GpsService();
  final SnowDao          _dao       = SnowDao();
  final ProcessingService _processing = ProcessingService();

  // ── État ─────────────────────────────────────────────────────────────────
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

  // ── Préférence partage communautaire ─────────────────────────────────────
  bool _shareWithCommunity = true;
  bool get shareWithCommunity => _shareWithCommunity;

  Future<void> setShareWithCommunity(bool v) async {
    _shareWithCommunity = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('snow.shareWithCommunity', v);
    notifyListeners();
  }

  // ── Mode mains-libres (wake word) ────────────────────────────────────────
  // Activable depuis le toggle "Activer mains libres" de l'action panel.
  // Quand actif, le micro tourne en permanence pour détecter "hey snowy" /
  // "bye bye snowy". CPU et batterie sont consommés en continu — c'est
  // pour ça qu'on en fait un toggle explicite plutôt qu'une activation
  // automatique.
  //
  // Si le code natif Android n'est pas en place (cf. android_patch_phase5),
  // le service WakeWordService.init() retourne false et le toggle reste
  // visible mais inerte — l'app continue de fonctionner normalement avec
  // le bouton micro classique.
  final WakeWordService _wakeWord = WakeWordService();
  bool _handsFreeEnabled = false;
  bool _wakeWordReady = false;

  /// True si l'utilisateur a activé le toggle mains-libres et que le micro
  /// écoute pour le wake word.
  bool get handsFreeEnabled => _handsFreeEnabled;

  /// True si le moteur natif est disponible (code Kotlin + ONNX en place).
  /// Quand false, le toggle dans l'UI doit être désactivé/grisé.
  bool get wakeWordReady => _wakeWordReady;

  /// Active le mode mains-libres. Initialise le moteur natif au premier appel.
  /// Retourne false si l'init a échoué (pas de moteur natif, permission micro
  /// refusée, etc.) ; dans ce cas le toggle UI doit revenir à off.
  Future<bool> enableHandsFree() async {
    if (_handsFreeEnabled) return true;

    // S'assure que le micro a la permission (pour quand le wake word
    // détectera et qu'on devra démarrer l'enregistrement immédiatement)
    final micOk = await _recording.init();
    if (!micOk) {
      _statusMessage = 'Permission micro refusée';
      notifyListeners();
      return false;
    }

    // Init du moteur natif si pas déjà fait
    if (!_wakeWordReady) {
      _wakeWordReady = await _wakeWord.init();
      if (!_wakeWordReady) {
        _statusMessage = 'Wake word indisponible (code natif manquant ?)';
        notifyListeners();
        return false;
      }
    }

    // Branche les callbacks
    _wakeWord.onWakeWord = _onWakeWordDetected;
    _wakeWord.onStopWord = _onStopWordDetected;

    await _wakeWord.startListening();
    _handsFreeEnabled = true;
    _statusMessage = 'Mains libres actif — dis "hey snowy" pour enregistrer';
    notifyListeners();

    // Persistance pour rétablir au prochain démarrage
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('snow.handsFreeEnabled', true);
    return true;
  }

  /// Désactive le mode mains-libres. Le micro s'arrête, plus de détection.
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
    // Ne déclenche que si on n'enregistre pas déjà — évite les doublons
    if (_status == SnowStatus.idle) {
      startRecording();
    }
  }

  void _onStopWordDetected() {
    debugPrint('[snow] stop word détecté → arrête obs');
    if (_status == SnowStatus.recording) {
      stopRecording();
    }
  }

  // ── Timer auto-stop (sécurité 15s comme Hey Snowy) ───────────────────────
  Timer? _autoStopTimer;
  static const _maxRecordingDuration = Duration(seconds: 15);

  // ── Démarrage ────────────────────────────────────────────────────────────

  bool _started = false;
  Future<void> start() async {
    if (_started) return;
    _started = true;

    // Charge la préférence "partage communautaire"
    final prefs = await SharedPreferences.getInstance();
    _shareWithCommunity = prefs.getBool('snow.shareWithCommunity') ?? true;

    // Initialise les sons (génère les bips au premier lancement)
    await _sound.init();

    // Marque toutes les obs historiques comme déjà uploadées : on ne réuploade
    // pas l'historique au premier démarrage du module
    // (cohérent avec ce que faisait Hey Snowy au démarrage de HomeScreen)
    await _dao.markAllAsUploaded();

    // Charge les obs de la session courante pour les pins
    await refreshObservations();
  }

  /// Recharge les observations depuis la BDD locale.
  ///
  /// Depuis la fusion des modules Neige et Obs (v0.5), on charge TOUTES les
  /// obs (`loadAll()`) et plus seulement celles des dernières 24h
  /// (`loadSession()`). Raison : l'onglet Obs présente l'historique complet
  /// de l'utilisateur, pas la "session du jour".
  Future<void> refreshObservations() async {
    _observations = await _dao.loadAll();
    notifyListeners();
  }

  // ── Enregistrement ───────────────────────────────────────────────────────

  /// Démarre un enregistrement d'observation. Snap la position GPS, lance le
  /// micro. Auto-stop après 15s (sécurité).
  Future<void> startRecording() async {
    if (_status != SnowStatus.idle) return;

    // Vérifie GPS dispo
    final pos = _gps.last;
    if (pos == null) {
      _statusMessage = 'Position GPS indisponible';
      notifyListeners();
      return;
    }

    // Démarre l'audio
    final audioPath = await _recording.start();
    if (audioPath == null) {
      _statusMessage = 'Micro indisponible (permission ?)';
      notifyListeners();
      return;
    }

    await _sound.bipStart();

    // Crée l'obs (sans transcript ni IA pour l'instant).
    // Note geolocator : `altitude` vaut 0.0 si non disponible. On garde null
    // dans ce cas pour distinguer "altitude inconnue" de "à l'altitude 0".
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
      if (_status == SnowStatus.recording) {
        stopRecording();
      }
    });
    notifyListeners();
  }

  /// Stoppe l'enregistrement. L'obs reste à l'état "brut" en BDD ; le
  /// traitement IA se fait en batch via `processPending()`.
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

  // ── Traitement batch ─────────────────────────────────────────────────────

  /// Lance le pipeline (Whisper → IA → Supabase) sur toutes les obs non
  /// encore traitées (pas de snowType ou pas uploadées).
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

  // ── Lecture / suppression d'obs ──────────────────────────────────────────

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

  /// Recentre la carte sur une obs (utilisé par review_screen).
  /// Le module Map gère le centrage, ici on signale juste la demande.
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
