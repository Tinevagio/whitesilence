// lib/modules/snow/services/processing_service.dart
//
// Pipeline de traitement des observations.
//
// Deux cas d'usage :
//   1. Obs vocales (audioPath non vide) : Whisper → IA → Supabase
//   2. Obs rapides (audioPath vide)     : déjà enrichies par l'utilisateur,
//                                         passage direct à Supabase
//
// L'upload Supabase a lieu seulement si :
//   - shareWithCommunity = true
//   - l'obs est "enrichie" (au minimum un snowType défini)

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
  final SnowDao _dao = SnowDao();
  final TranscriptionService _transcription = TranscriptionService();
  final AiService _ai = AiService();
  final SupabaseService _supabase = SupabaseService();

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

      Observation enriched = obs;

      // ── Cas 1 : obs vocale → pipeline Whisper + IA ──────────────────────
      if (obs.audioPath.isNotEmpty) {
        final transcript = await _transcription.transcribe(obs.audioPath);
        if (transcript == null || transcript.isEmpty) {
          obs.rawNotes = 'Transcription échouée';
          await _dao.update(obs);
          failed++;
          continue;
        }
        enriched = await _ai.extractSnowData(obs, transcript);
        await _dao.update(enriched);
      }
      // ── Cas 2 : obs rapide (sans audio) → déjà enrichie par l'utilisateur,
      // on saute Whisper et l'IA et on passe direct à l'upload.

      // ── Upload Supabase ─────────────────────────────────────────────────
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