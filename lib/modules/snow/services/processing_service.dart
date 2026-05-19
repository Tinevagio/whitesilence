// lib/modules/snow/services/processing_service.dart
//
// Pipeline batch : transcription → extraction IA → persistance → upload.
// Migré depuis Hey Snowy avec adaptation aux nouveaux DAO/services.

import 'package:flutter/foundation.dart';

import '../models/observation.dart';
import '../snow_dao.dart';
import 'ai_service.dart';
import 'supabase_service.dart';
import 'transcription_service.dart';

class ProcessingResult {
  final int processed;
  final int uploaded;
  final int failed;
  const ProcessingResult({
    required this.processed,
    required this.uploaded,
    required this.failed,
  });
}

class ProcessingService {
  final TranscriptionService _transcription = TranscriptionService();
  final AiService             _ai           = AiService();
  final SupabaseService       _supabase     = SupabaseService();
  final SnowDao               _dao          = SnowDao();

  /// Traite chaque obs de [observations] séquentiellement. [onProgress]
  /// est appelé après chaque obs avec son index 1-based et le total.
  Future<ProcessingResult> processObservations(
    List<Observation> observations, {
    required void Function(int current, int total) onProgress,
    bool shareWithCommunity = true,
  }) async {
    var uploaded = 0;
    var failed = 0;

    for (int i = 0; i < observations.length; i++) {
      final obs = observations[i];
      onProgress(i + 1, observations.length);

      // 1. Transcription
      final transcript = await _transcription.transcribe(obs.audioPath);
      if (transcript == null || transcript.isEmpty) {
        obs.rawNotes = 'Transcription échouée';
        await _dao.update(obs);
        failed++;
        continue;
      }

      // 2. Extraction IA
      final enriched = await _ai.extractSnowData(obs, transcript);
      await _dao.update(enriched);

      // 3. Upload Supabase (si autorisé et obs vraiment enrichie)
      if (shareWithCommunity && enriched.isEnriched) {
        final ok = await _supabase.uploadObservation(enriched);
        if (ok) {
          enriched.uploaded = true;
          await _dao.update(enriched);
          uploaded++;
        }
      }
    }

    final processed = observations.length - failed;
    debugPrint('[processing] terminé : $processed traités, $uploaded uploadés, $failed échecs');
    return ProcessingResult(
      processed: processed,
      uploaded:  uploaded,
      failed:    failed,
    );
  }
}
