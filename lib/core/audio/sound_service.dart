// lib/core/audio/sound_service.dart
//
// Bips de feedback (début/fin d'enregistrement, validation, etc.).
// Génère des WAV synthétiques au premier lancement pour éviter d'embarquer
// des fichiers audio dans les assets.
//
// Migré depuis Hey Snowy (lib/services/sound_service.dart).

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

class SoundService {
  static final SoundService _instance = SoundService._();
  factory SoundService() => _instance;
  SoundService._();

  final AudioPlayer _player = AudioPlayer();
  String? _bipStartPath;
  String? _bipStopPath;
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    _bipStartPath = await _writeBeep(frequency: 880, durationMs: 120);
    _bipStopPath  = await _writeBeep(frequency: 660, durationMs: 100);
    _isInitialized = true;
  }

  Future<String> _writeBeep({
    required double frequency,
    required double durationMs,
    double sampleRate = 44100,
  }) async {
    final dir  = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/bip_${frequency.round()}.wav';
    final file = File(path);
    if (await file.exists()) return path;

    final numSamples = (sampleRate * durationMs / 1000).round();
    final buffer = ByteData(44 + numSamples * 2);
    int o = 0;
    for (final b in 'RIFF'.codeUnits) buffer.setUint8(o++, b);
    buffer.setUint32(o, 36 + numSamples * 2, Endian.little); o += 4;
    for (final b in 'WAVEfmt '.codeUnits) buffer.setUint8(o++, b);
    buffer.setUint32(o, 16, Endian.little); o += 4;
    buffer.setUint16(o, 1, Endian.little);  o += 2;
    buffer.setUint16(o, 1, Endian.little);  o += 2;
    buffer.setUint32(o, sampleRate.round(), Endian.little); o += 4;
    buffer.setUint32(o, sampleRate.round() * 2, Endian.little); o += 4;
    buffer.setUint16(o, 2, Endian.little);  o += 2;
    buffer.setUint16(o, 16, Endian.little); o += 2;
    for (final b in 'data'.codeUnits) buffer.setUint8(o++, b);
    buffer.setUint32(o, numSamples * 2, Endian.little); o += 4;
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final env = i < numSamples * 0.1
          ? i / (numSamples * 0.1)
          : i > numSamples * 0.8
              ? (numSamples - i) / (numSamples * 0.2)
              : 1.0;
      final s = (sin(2 * pi * frequency * t) * 32767 * 0.7 * env).round();
      buffer.setInt16(o, s.clamp(-32768, 32767), Endian.little);
      o += 2;
    }
    await file.writeAsBytes(buffer.buffer.asUint8List());
    return path;
  }

  Future<void> bipStart() async {
    if (_bipStartPath == null) return;
    try {
      await _player.setFilePath(_bipStartPath!);
      await _player.play();
    } catch (e) {
      debugPrint('[sound] bipStart error: $e');
    }
  }

  Future<void> bipStop() async {
    if (_bipStopPath == null) return;
    try {
      await _player.setFilePath(_bipStopPath!);
      await _player.play();
    } catch (e) {
      debugPrint('[sound] bipStop error: $e');
    }
  }

  void dispose() => _player.dispose();
}
