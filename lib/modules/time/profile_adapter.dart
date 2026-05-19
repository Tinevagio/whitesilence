// lib/modules/time/profile_adapter.dart
//
// Convertit le UserProfile global (shared/settings/user_profile.dart)
// en MunterProfile attendu par le moteur.
//
// Le mapping est trivial parce que les enums correspondent 1:1, mais on
// l'isole ici pour que si le profil global évolue, on n'ait qu'un seul
// endroit à mettre à jour.

import '../../shared/settings/user_profile.dart';
import 'munter.dart';

MunterProfile munterProfileFrom(UserProfile profile) {
  return MunterProfile(
    activity: _mapActivity(profile.activity),
    fitness:  _mapLevel(profile.level),
    terrain:  _mapConditions(profile.conditions),
  );
}

MunterActivity _mapActivity(Activity a) {
  switch (a) {
    case Activity.hiking:       return MunterActivity.hiking;
    case Activity.skiTouring:   return MunterActivity.skiTouring;
    case Activity.trailRunning: return MunterActivity.trail;
  }
}

MunterFitness _mapLevel(Level l) {
  switch (l) {
    case Level.beginner: return MunterFitness.beginner;
    case Level.trained:  return MunterFitness.trained;
    case Level.warrior:  return MunterFitness.warrior;
  }
}

MunterTerrain _mapConditions(FieldConditions c) {
  switch (c) {
    case FieldConditions.normal:      return MunterTerrain.normal;
    case FieldConditions.difficult:   return MunterTerrain.difficultTerrain;
    case FieldConditions.heavySnow:   return MunterTerrain.heavySnow;
  }
}
