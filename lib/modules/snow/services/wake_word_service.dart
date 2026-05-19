// lib/modules/snow/services/wake_word_service.dart
//
// Pont Dart vers le wake word natif Android (ONNX dans le code Kotlin).
// Migré depuis Hey Snowy.
//
// En Phase 2 : ce service N'EST PAS démarré par défaut. Il existe pour que
// la Phase 5 (module Sortie) puisse l'activer quand une sortie démarre.
//
// Côté natif Android, il faut migrer (à la Phase 5) :
//   - les ONNX models (hey_snowy.onnx, bye_bye_snowy.onnx, melspectrogram.onnx,
//     embedding_model.onnx) dans assets/
//   - le code Kotlin qui implémente les MethodChannel 'whitesilence/wake_word'
//     et 'whitesilence/wake_word_events'
//
// Tant que ce code natif n'est pas en place, init() retournera simplement
// false (pas de wake word) et l'app continuera de fonctionner normalement.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class WakeWordService {
  // Note: à terme on alignera ces noms avec 'whitesilence/...' côté Kotlin
  // pour la cohérence. Pour la migration, on garde les noms Hey Snowy pour
  // pouvoir réutiliser le code natif tel quel.
  static const _methodChannel = MethodChannel('hey_snowy/wake_word');
  static const _eventChannel  = EventChannel('hey_snowy/wake_word_events');

  StreamSubscription? _subscription;
  bool _isAvailable = false;

  bool get isAvailable => _isAvailable;

  /// Callbacks à brancher avant `startListening()`.
  void Function()? onWakeWord;
  void Function()? onStopWord;

  /// Initialise le service. Retourne false si le canal natif n'est pas
  /// disponible (ce qui sera le cas tant que la Phase 5 n'a pas migré le
  /// code Kotlin).
  Future<bool> init() async {
    try {
      final ok = await _methodChannel.invokeMethod<bool>('init');
      _isAvailable = ok ?? false;
      return _isAvailable;
    } on PlatformException catch (e) {
      debugPrint('[wakeWord] init impossible: ${e.message}');
      _isAvailable = false;
      return false;
    } on MissingPluginException catch (_) {
      // Le canal n'existe pas (code natif non migré ou pas en debug)
      debugPrint('[wakeWord] canal natif absent — wake word désactivé');
      _isAvailable = false;
      return false;
    }
  }

  Future<void> startListening() async {
    if (!_isAvailable) return;
    try {
      await _methodChannel.invokeMethod('start');
      _subscription = _eventChannel.receiveBroadcastStream().listen((label) {
        if (label == 'hey snowy') {
          onWakeWord?.call();
        } else if (label == 'bye bye snowy') {
          onStopWord?.call();
        }
      });
    } catch (e) {
      debugPrint('[wakeWord] start error: $e');
    }
  }

  Future<void> stopListening() async {
    await _subscription?.cancel();
    _subscription = null;
    if (!_isAvailable) return;
    try {
      await _methodChannel.invokeMethod('stop');
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stopListening();
    if (!_isAvailable) return;
    try {
      await _methodChannel.invokeMethod('dispose');
    } catch (_) {}
  }
}
