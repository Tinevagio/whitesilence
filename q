[33mcommit b5fe510be78ef42c1ad8be4475aa655c8b41e8d0[m
Author: Matthieu GIOVANETTI <giovanetti.matthieu@gmail.com>
Date:   Sun May 24 17:15:24 2026 +0200

    second commit

[1mdiff --git a/lib/modules/time/time_controller.dart b/lib/modules/time/time_controller.dart[m
[1mindex 4735342..4260947 100644[m
[1m--- a/lib/modules/time/time_controller.dart[m
[1m+++ b/lib/modules/time/time_controller.dart[m
[36m@@ -11,8 +11,11 @@[m
 //[m
 // Remplace la partie "temps/isochrones" de l'ancien app_state.dart de TimeToGo.[m
 [m
[32m+[m[32mimport 'dart:convert';[m
[32m+[m
 import 'package:flutter/foundation.dart';[m
 import 'package:latlong2/latlong.dart';[m
[32m+[m[32mimport 'package:shared_preferences/shared_preferences.dart';[m
 [m
 import '../../core/elevation/dem_selector.dart';[m
 import '../../core/elevation/elevation_provider.dart';[m
[36m@@ -23,6 +26,10 @@[m [mimport 'isochrone.dart';[m
 import 'munter.dart';[m
 import 'profile_adapter.dart';[m
 [m
[32m+[m[32m/// Clé SharedPreferences pour la persistance de la calibration Munter.[m
[32m+[m[32m/// Format JSON : { "profile": "skiTouring/trained/normal", "measurements": [...] }[m
[32m+[m[32mconst String _kMunterSnapshotKey = 'time.munter.snapshot';[m
[32m+[m
 class TimeController extends ChangeNotifier {[m
   static final TimeController _instance = TimeController._();[m
   factory TimeController() => _instance;[m
[36m@@ -126,10 +133,20 @@[m [mclass TimeController extends ChangeNotifier {[m
     }[m
     _calibrator = GpsCalibrator(munter: _munter, dem: _cachedDem);[m
     // Branche les notifications du calibrator pour que l'UI suive en[m
[31m-    // temps réel (segments acceptés, % calibration, vitesses Munter).[m
[31m-    _calibrator.onUpdate = notifyListeners;[m
[32m+[m[32m    // temps réel + sauver la calibration après chaque update.[m
[32m+[m[32m    _calibrator.onUpdate = () {[m
[32m+[m[32m      _saveSnapshot(); // fire-and-forget, ne bloque pas l'UI[m
[32m+[m[32m      notifyListeners();[m
[32m+[m[32m    };[m
     _calibratorInitialized = true;[m
     if (_calibratorAttached) _calibrator.attachToGpsService();[m
[32m+[m
[32m+[m[32m    // Tente de restaurer la calibration précédente. Si la signature de[m
[32m+[m[32m    // profil ne correspond plus, le snapshot est ignoré (calibration repart[m
[32m+[m[32m    // proprement de zéro pour ce nouveau profil).[m
[32m+[m[32m    // Fire-and-forget : on n'attend pas le résultat pour libérer le UI.[m
[32m+[m[32m    _restoreSnapshot();[m
[32m+[m
     if (!_computing) {[m
       _contours      = {};[m
       _targetPoint   = null;[m
[36m@@ -306,4 +323,63 @@[m [mclass TimeController extends ChangeNotifier {[m
     _pointEstimate = null;[m
     notifyListeners();[m
   }[m
[32m+[m
[32m+[m[32m  // ── Persistance Munter ──────────────────────────────────────────────────[m
[32m+[m[32m  //[m
[32m+[m[32m  // On sauve les N dernières mesures GPS avec la signature du profil. Au[m
[32m+[m[32m  // démarrage, on tente de recharger : si la signature matche, la[m
[32m+[m[32m  // calibration reprend où elle en était. Si elle ne matche pas (profil[m
[32m+[m[32m  // modifié), on ignore le snapshot et la calibration repart de zéro.[m
[32m+[m[32m  //[m
[32m+[m[32m  // Stratégie debounce : `_saveSnapshot()` est appelé après chaque mesure[m
[32m+[m[32m  // GPS, soit potentiellement plusieurs fois par minute en sortie. C'est[m
[32m+[m[32m  // OK car SharedPreferences est rapide (~ms) et le payload est petit[m
[32m+[m[32m  // (< 1 KB). Pas besoin de debouncing complexe.[m
[32m+[m
[32m+[m[32m  Future<void> _saveSnapshot() async {[m
[32m+[m[32m    try {[m
[32m+[m[32m      final snapshot = _munter.toSnapshot();[m
[32m+[m[32m      // Skip si pas de mesure (rien à sauver, et évite d'écraser un[m
[32m+[m[32m      // snapshot précédent valide par un état vide post-redémarrage).[m
[32m+[m[32m      final ms = snapshot['measurements'];[m
[32m+[m[32m      if (ms is List && ms.isEmpty) return;[m
[32m+[m[32m      final prefs = await SharedPreferences.getInstance();[m
[32m+[m[32m      await prefs.setString(_kMunterSnapshotKey, jsonEncode(snapshot));[m
[32m+[m[32m    } catch (e) {[m
[32m+[m[32m      // Persistance non critique — on log mais on ne fait pas tomber l'app.[m
[32m+[m[32m      debugPrint('[time] Save snapshot failed: $e');[m
[32m+[m[32m    }[m
[32m+[m[32m  }[m
[32m+[m
[32m+[m[32m  Future<void> _restoreSnapshot() async {[m
[32m+[m[32m    try {[m
[32m+[m[32m      final prefs = await SharedPreferences.getInstance();[m
[32m+[m[32m      final raw = prefs.getString(_kMunterSnapshotKey);[m
[32m+[m[32m      if (raw == null || raw.isEmpty) return;[m
[32m+[m
[32m+[m[32m      final snapshot = jsonDecode(raw) as Map<String, dynamic>;[m
[32m+[m[32m      final ok = _munter.restoreFromSnapshot(snapshot);[m
[32m+[m[32m      if (ok) {[m
[32m+[m[32m        debugPrint('[time] Calibration Munter restaurée '[m
[32m+[m[32m            '(${_munter.calibrationReport()['measurements']} mesures, '[m
[32m+[m[32m            '${_munter.calibrationReport()['weight']}).');[m
[32m+[m[32m        notifyListeners();[m
[32m+[m[32m      } else {[m
[32m+[m[32m        // Signature de profil différente — on jette le vieux snapshot et[m
[32m+[m[32m        // on repart proprement.[m
[32m+[m[32m        debugPrint('[time] Profil changé, snapshot Munter ignoré.');[m
[32m+[m[32m        await prefs.remove(_kMunterSnapshotKey);[m
[32m+[m[32m      }[m
[32m+[m[32m    } catch (e) {[m
[32m+[m[32m      debugPrint('[time] Restore snapshot failed: $e');[m
[32m+[m[32m    }[m
[32m+[m[32m  }[m
[32m+[m
[32m+[m[32m  /// Efface manuellement la calibration sauvegardée.[m
[32m+[m[32m  /// Utile pour un bouton "Réinitialiser la calibration" dans Réglages.[m
[32m+[m[32m  Future<void> clearMunterCalibration() async {[m
[32m+[m[32m    final prefs = await SharedPreferences.getInstance();[m
[32m+[m[32m    await prefs.remove(_kMunterSnapshotKey);[m
[32m+[m[32m    _rebuildEngine();[m
[32m+[m[32m  }[m
 }[m
