// lib/modules/snow/services/transcription_service.dart
//
// Transcription audio via Whisper-large-v3 sur Groq.
// Migré depuis Hey Snowy. Différence : clé via WSSecrets, gestion d'absence.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/secrets.dart';

class TranscriptionService {
  static const String _apiUrl =
      'https://api.groq.com/openai/v1/audio/transcriptions';

  /// Retourne le texte transcrit, ou null en cas d'erreur.
  Future<String?> transcribe(String audioPath) async {
    final apiKey = WSSecrets.groqApiKey;
    if (apiKey.isEmpty) {
      debugPrint('[transcription] GROQ_API_KEY absent — transcription désactivée');
      return null;
    }

    try {
      final file = File(audioPath);
      if (!await file.exists()) {
        debugPrint('[transcription] fichier audio introuvable: $audioPath');
        return null;
      }

      final request = http.MultipartRequest('POST', Uri.parse(_apiUrl));
      request.headers['Authorization'] = 'Bearer $apiKey';
      request.fields['model']           = 'whisper-large-v3';
      request.fields['language']        = 'fr';
      request.fields['response_format'] = 'text';
      request.files.add(await http.MultipartFile.fromPath('file', audioPath));

      final response = await request.send();
      final body     = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        return body.trim();
      } else {
        debugPrint('[transcription] HTTP ${response.statusCode}: $body');
        return null;
      }
    } catch (e) {
      debugPrint('[transcription] erreur: $e');
      return null;
    }
  }
}
