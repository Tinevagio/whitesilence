package app.whitesilence.whitesilence

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.rementia.openwakeword.lib.WakeWordEngine
import com.rementia.openwakeword.lib.model.WakeWordModel
import com.rementia.openwakeword.lib.ParallelWakeWordEngine
import android.content.Intent
import kotlinx.coroutines.*

/**
 * Wake word natif WhiteSilence — migré depuis Hey Snowy.
 *
 * Détecte les mots-clés "hey snowy" (démarre enregistrement) et
 * "bye bye snowy" (stoppe enregistrement) en utilisant la lib
 * `xyz.rementia:openwakeword` qui encapsule les 4 modèles ONNX :
 *   - melspectrogram.onnx   : extraction de features audio
 *   - embedding_model.onnx  : embedding de voix
 *   - hey_snowy.onnx        : classifier wake word
 *   - bye_bye_snowy.onnx    : classifier stop word
 *
 * Les noms de canaux restent `hey_snowy/wake_word` et
 * `hey_snowy/wake_word_events` pour ne pas avoir à modifier le pont Dart
 * `lib/modules/snow/services/wake_word_service.dart` qui existe depuis
 * la Phase 2.
 *
 * Convention WhiteSilence : le wake word est activé/désactivé depuis le
 * module Neige (toggle "Activer mains libres"), JAMAIS automatiquement.
 * Économie de batterie + intentionnalité utilisateur.
 */
class MainActivity : FlutterActivity() {

    private val METHOD_CHANNEL      = "hey_snowy/wake_word"
    private val GPS_SERVICE_CHANNEL = "gps_foreground_service/control"
    private val EVENT_CHANNEL  = "hey_snowy/wake_word_events"

    private var engine: ParallelWakeWordEngine? = null
    private var eventSink: EventChannel.EventSink? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var collectJob: Job? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "init" -> {
                        scope.launch {
                            try {
                                val models = listOf(
                                    WakeWordModel(
                                        name = "hey snowy",
                                        modelPath = "hey_snowy.onnx",
                                        threshold = 0.12f
                                    ),
                                    WakeWordModel(
                                        name = "bye bye snowy",
                                        modelPath = "bye_bye_snowy.onnx",
                                        threshold = 0.5f
                                    )
                                )
                                engine = ParallelWakeWordEngine(
                                    context = applicationContext,
                                    models = models,
                                    detectionCooldownMs = 2000L,
                                    maxWorkers = 2
                                )
                                withContext(Dispatchers.Main) { result.success(true) }
                            } catch (e: Exception) {
                                android.util.Log.e("WakeWord", "Init failed", e)
                                withContext(Dispatchers.Main) {
                                    result.error("INIT_ERROR", e.message, null)
                                }
                            }
                        }
                    }
                    "start" -> {
                        val eng = engine
                        if (eng == null) {
                            result.error("NOT_INIT", "Engine not initialized", null)
                            return@setMethodCallHandler
                        }
                        eng.start()
                        collectJob = scope.launch {
                            eng.detections.collect { detection ->
                                withContext(Dispatchers.Main) {
                                    eventSink?.success(detection.model.name)
                                }
                            }
                        }
                        result.success(null)
                    }
                    "stop" -> {
                        collectJob?.cancel()
                        collectJob = null
                        engine?.stop()
                        result.success(null)
                    }
                    "dispose" -> {
                        collectJob?.cancel()
                        collectJob = null
                        engine?.release()
                        engine = null
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Foreground Service GPS ─────────────────────────────────────────
        // Reçoit les commandes "start" et "stop" de GpsService.dart pour
        // démarrer/arrêter GpsForegroundService en fonction du cycle de vie
        // de l'app (paused/resumed).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GPS_SERVICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val intent = Intent(this, GpsForegroundService::class.java)
                        startForegroundService(intent)
                        result.success(null)
                    }
                    "stop" -> {
                        val intent = Intent(this, GpsForegroundService::class.java)
                        stopService(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
        engine?.release()
    }
}

