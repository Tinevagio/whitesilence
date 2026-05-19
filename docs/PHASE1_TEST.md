# Phase 1 — Module Temps (migration TimeToGo)

## Ce qui a changé depuis Phase 0

### Nouveaux fichiers

```
lib/core/elevation/                    ← Mutualisé pour tous les modules
├── elevation_provider.dart            (interface unifiée latlong2)
├── hgt_provider.dart                  (offline SRTM1)
├── hgt_downloader.dart                (AWS Skadi + catalogue massifs)
├── open_meteo_provider.dart           (online API)
├── demo_provider.dart                 (synthétique)
└── dem_selector.dart                  (orchestration HGT > OM > Demo)

lib/modules/time/                      ← Module Temps
├── munter.dart                        (moteur Munter + calibration)
├── isochrone.dart                     (ray-casting adaptatif)
├── gps_calibrator.dart                (branché sur GpsService)
├── profile_adapter.dart               (UserProfile global → MunterProfile)
├── time_controller.dart               (orchestrateur)
└── time_overlay.dart                  (MapModuleOverlay)

lib/shared/settings/zones_screen.dart  ← HGT installer restylé
```

### Fichiers modifiés

- `pubspec.yaml` — ajout de `archive: ^3.4.0` (décompression .hgt.gz)
- `core/map/map_module_overlay.dart` — `onMapTap` reçoit aussi le `LatLng`
- `core/map/map_screen.dart` — passe `latLng` aux overlays
- `shared/settings/settings_screen.dart` — section "Cartes hors-ligne" → `ZonesScreen`
- `main.dart` — branche `TimeModuleOverlay()` et démarre `TimeController().start()`

## Installation

Dézipper par-dessus ton dossier `whitesilence/` existant (écrase Phase 0).

```powershell
cd C:\flutter\whitesilence
flutter pub get
flutter run
```

## Plan de test

### Test 1 — L'app démarre, le module Temps est visible
- Lancer l'app → carte topo + bottom bar à 5 modules
- L'icône **Temps** (horloge) doit être sélectionnée par défaut
- L'action panel en bas affiche : *« Tape sur la carte pour estimer un temps »* + bouton **Calculer les isochrones**

### Test 2 — Estimation ponctuelle (tap)
- Taper n'importe où sur la carte
- Un drapeau apparaît à l'endroit tapé
- L'action panel affiche : `42 min · 1.9 km · +380 m` (valeurs indicatives)
- Si tu es en intérieur sans GPS récent : *« Position inconnue »* — c'est normal

### Test 3 — Isochrones
- Cliquer **Calculer les isochrones**
- Indicateur de progression *« Calcul des isochrones… »*
- Après quelques secondes : 4 contours empilés (vert/bleu/orange/rouge = 15/30/45/60 min)
- Sous le bouton : `🛰 Open-Meteo (±400m)` (puisque pas encore de HGT installé)

### Test 4 — Zones topographiques
- Réglages → **Cartes hors-ligne** → **Zones topographiques**
- Liste des 10 massifs alpins/pyrénéens
- Tap sur **Télécharger** sur Chamonix (~12 MB)
- Retour à la carte, recalcul des isochrones
- L'indicateur doit changer : `🗻 HGT SRTM1 (30m)`

### Test 5 — Profil change → isochrones invalidées
- Réglages → changer **Niveau** (Entraîné → Warrior)
- Retour à la carte
- Les isochrones précédentes doivent avoir disparu (le profil a changé → recalcul nécessaire)
- Recalculer → patches plus grands (Warrior va plus vite que Entraîné)

### Test 6 — Calibration (sortie réelle)
- Sortir marcher ≥ 5 min avec l'app ouverte
- Les segments GPS alimentent Munter en arrière-plan
- Après ~20-30 min, dans l'action panel : badge **✓ Calibré** doit apparaître

## Points d'attention

### Permissions Android
Tu as déjà ajouté `ACCESS_FINE_LOCATION` et `ACCESS_COARSE_LOCATION`.
**INTERNET** est ajouté par défaut par Flutter en debug, mais pour un build release il faudra explicitement :
```xml
<uses-permission android:name="android.permission.INTERNET"/>
```
(à ajouter dans `AndroidManifest.xml` avant la balise `<application>`).

### Première utilisation hors-ligne
Avant la première sortie : Réglages → Zones topo → télécharge ton massif sur WiFi.
Sinon, sans réseau et sans HGT, le module affichera un terrain synthétique
(⚠ Terrain synthétique) — l'estimation sera très approximative.

### Pourquoi le profil global remplace celui de TimeToGo
TimeToGo avait son propre `UserProfile` (activity/fitness/terrain). WhiteSilence
a `UserProfile` global (activity/level/conditions). Le pont est dans
`modules/time/profile_adapter.dart` — un mapping 1:1 d'enums.

Le profil saisi dans Réglages WhiteSilence alimente Munter via cet adaptateur.
Quand l'utilisateur change son profil, `TimeController` reconstruit le moteur
Munter avec les nouveaux paramètres, et invalide les isochrones.

## Bugs probables à signaler

- **Crash au démarrage** : probablement un import oublié ou une lib Flutter
  non installée. `flutter pub get` puis `flutter run` à nouveau.
- **Carte noire en mode web** : OpenTopoMap a parfois des soucis CORS sur
  Chrome dev. Préférer Windows ou le Pixel pour le développement.
- **Isochrones inversées** (15 min = grand cercle, 60 min = petit cercle) :
  le tri des budgets est défaillant. Improbable mais à signaler.
- **`MissingPluginException`** sur `path_provider` ou `shared_preferences` :
  signe que `flutter pub get` n'a pas tout récupéré. Hot restart, ou
  redémarrer `flutter run`.
