import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Activité pratiquée. Influence les calculs Munter et les seuils par défaut
/// (notamment le seuil de pente pour les cônes d'avalanche).
enum Activity { hiking, skiTouring, trailRunning }

/// Niveau de l'utilisateur. Calibre les vitesses de référence Munter avant
/// que la calibration automatique ne prenne le relais (après ~20-40 min).
enum Level { beginner, trained, warrior }

/// Conditions du jour, choisi à la volée par l'utilisateur.
enum FieldConditions { normal, difficult, heavySnow }

/// Profil utilisateur WhiteSilence — unique et partagé.
///
/// Remplace les profils séparés de GhostTime / Hey Snowy / Névé.
/// Stocké localement, jamais envoyé sur le réseau.
class UserProfile extends ChangeNotifier {
  static final UserProfile _instance = UserProfile._();
  factory UserProfile() => _instance;
  UserProfile._();

  Activity _activity = Activity.skiTouring;
  Level _level = Level.trained;
  FieldConditions _conditions = FieldConditions.normal;
  bool _isLoaded = false;

  Activity get activity => _activity;
  Level get level => _level;
  FieldConditions get conditions => _conditions;
  bool get isLoaded => _isLoaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _activity = Activity.values[prefs.getInt('profile.activity') ?? 1];
    _level = Level.values[prefs.getInt('profile.level') ?? 1];
    _conditions = FieldConditions.values[prefs.getInt('profile.conditions') ?? 0];
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setActivity(Activity a) async {
    _activity = a;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('profile.activity', a.index);
    notifyListeners();
  }

  Future<void> setLevel(Level l) async {
    _level = l;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('profile.level', l.index);
    notifyListeners();
  }

  Future<void> setConditions(FieldConditions c) async {
    _conditions = c;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('profile.conditions', c.index);
    notifyListeners();
  }
}
