# MIGRATION.md — Du multi-repo vers WhiteSilence

Ce document trace la migration des 4 projets ski de rando existants vers une mono-app Flutter unifiée.

## État initial (avant migration)

| Projet | Rôle | Stack | À migrer |
|---|---|---|---|
| **GhostTime / TimeToGo** | Munter + isochrones | Flutter, HGT SRTM1, Open-Meteo | Totalement |
| **Hey Snowy** | Observations vocales | Flutter, Groq, Picovoice, Supabase | Totalement |
| **Névé / snow-conditions** | Conditions + BERA + avalanche | FastAPI + frontend web | Frontend uniquement, le backend reste |
| **Ski-touring-live** | Cron BERA + Open-Meteo | Python | Aucune migration (sert le backend Névé) |

## Phase 0 — Fondations ✅

- [x] Repo `whitesilence/` créé avec `pubspec.yaml`
- [x] Design system : `colors.dart`, `typography.dart`, `spacing.dart`, `theme.dart`
- [x] Service GPS partagé (`core/gps/gps_service.dart`)
- [x] Profil utilisateur unique (`shared/settings/user_profile.dart`)
- [x] Registre des modules (`core/module_registry.dart`)
- [x] MapScreen partagée avec système d'overlays (`core/map/`)
- [x] Shell de l'app avec bottom bar (`app.dart`)
- [x] Écran réglages (`shared/settings/settings_screen.dart`)
- [x] Écran manifeste (`shared/manifesto/manifesto_screen.dart`)
- [x] `main.dart` qui orchestre tout

**Test** : `flutter pub get && flutter run` → l'app s'ouvre sur une carte topo vide avec une bottom bar à 5 modules (tous sans overlay encore).

## Phase 1 — Migration TimeToGo → module `time` ✅

Module Temps livré. Voir `docs/PHASE1_TEST.md` pour le plan de test détaillé.

### Ce qui a été migré

| TimeToGo (source) | WhiteSilence (cible) | Notes |
|---|---|---|
| `lib/munter.dart` | `lib/modules/time/munter.dart` | Préfixé `Munter*` pour éviter collision avec UserProfile global |
| `lib/isochrone.dart` | `lib/modules/time/isochrone.dart` | Réconcilié avec `latlong2.LatLng` (fini la double classe LatLng) |
| `lib/gps_calibrator.dart` | `lib/modules/time/gps_calibrator.dart` | Branché sur `GpsService` partagé au lieu d'un stream privé |
| `lib/providers/hgt_elevation_provider.dart` | `lib/core/elevation/hgt_provider.dart` | **Devenu core** — réutilisable par snow/avalanche |
| `lib/providers/hgt_downloader.dart` | `lib/core/elevation/hgt_downloader.dart` | **Devenu core** |
| `lib/providers/open_meteo_elevation_provider.dart` | `lib/core/elevation/open_meteo_provider.dart` | **Devenu core** |
| `lib/providers/demo_elevation_provider.dart` | `lib/core/elevation/demo_provider.dart` | **Devenu core** |
| `lib/widgets/isochrone_layer.dart` | `lib/modules/time/time_overlay.dart` | Refactoré en 3 layers FlutterMap natifs |
| `lib/screens/zones_screen.dart` | `lib/shared/settings/zones_screen.dart` | **Devenu partagé**, restylé WhiteSilence |
| `lib/app_state.dart` (partie temps) | `lib/modules/time/time_controller.dart` | Découpé + le GPS/profil basculent dans les singletons partagés |

### Ce qui a été ajouté

- `lib/core/elevation/elevation_provider.dart` — interface séparée (n'était pas un fichier dédié dans TimeToGo)
- `lib/core/elevation/dem_selector.dart` — extraction de la logique HGT > OpenMeteo > Demo qui était inline dans `app_state.dart`
- `lib/modules/time/profile_adapter.dart` — pont entre `UserProfile` global et `MunterProfile` local

### Ce qui n'a PAS été migré

- `lib/widgets/profile_sheet.dart` — remplacé par l'écran Réglages global de WhiteSilence
- `lib/widgets/hgt_coverage_layer.dart` — pas migré pour l'instant ; à reprendre en phase ultérieure si besoin (overlay carte montrant les zones HGT installées)
- `lib/screens/map_screen.dart` — remplacé par `WSMapScreen` partagée
- Gestion du mode "pin" vs "GPS" — simplifié : on utilise toujours la position GPS courante du `GpsService` comme origine

## Phase 2 — Migration Hey Snowy → module `snow` ✅

Module Neige livré. Voir `docs/PHASE2_TEST.md` pour le plan de test détaillé.

### Ce qui a été migré

| Hey Snowy (source) | WhiteSilence (cible) | Notes |
|---|---|---|
| `lib/services/audio_service.dart` | `lib/core/audio/recording_service.dart` | **Devient core** + ChangeNotifier singleton |
| `lib/services/sound_service.dart` | `lib/core/audio/sound_service.dart` | **Devient core** + singleton |
| `lib/services/storage_service.dart` | `lib/core/storage/db.dart` + `lib/modules/snow/snow_dao.dart` | BDD globale `whitesilence.db` + DAO du module |
| `lib/services/transcription_service.dart` | `lib/modules/snow/services/transcription_service.dart` | Clé via `WSSecrets` (lit .env) |
| `lib/services/ai_service.dart` | `lib/modules/snow/services/ai_service.dart` | Idem + tolère absence de clé |
| `lib/services/supabase_service.dart` | `lib/modules/snow/services/supabase_service.dart` | Idem + no-op silencieux si absent |
| `lib/services/processing_service.dart` | `lib/modules/snow/services/processing_service.dart` | + retourne `ProcessingResult` |
| `lib/services/wake_word_service.dart` | `lib/modules/snow/services/wake_word_service.dart` | Conservé mais désactivé (Phase 5) |
| `lib/models/observation.dart` | `lib/modules/snow/models/observation.dart` | `altitudeM` devient nullable |
| `lib/screens/home_screen.dart` | DISSOUS dans `snow_controller.dart` + `snow_overlay.dart` | La logique de session/enregistrement passe dans le contrôleur, l'UI dans l'overlay |
| `lib/screens/map_screen.dart` | DISSOUS dans `snow_overlay.dart` (MarkerLayer) | Plus de map dédiée, l'overlay s'intègre à la WSMapScreen |
| `lib/screens/review_screen.dart` | `lib/modules/snow/review_screen.dart` | Restylé WhiteSilence (était dark mode) |
| `lib/services/gps_service.dart` | SUPPRIMÉ | On utilise le `GpsService` global de WhiteSilence |

### Ce qui a été ajouté

- `.env.template` + `.gitignore` — gestion propre des clés API
- `lib/core/secrets.dart` — accès typé aux clés, tolérant à l'absence
- `lib/core/storage/db.dart` — BDD SQLite globale (préfigure Phase 5 avec table `tours`)
- Couleurs `WSColors.snowTypeColors` enrichies avec tous les types Hey Snowy

### Ce qui n'a PAS été migré

- `lib/screens/edit_observation_screen.dart` — l'édition manuelle d'une obs n'a pas été reportée pour la Phase 2. Si tu veux pouvoir corriger un type de neige détecté par l'IA, on l'ajoutera plus tard (c'est ~150 lignes).
- Le **code natif Android du wake word** (Kotlin + ONNX) — viendra en Phase 5 quand on activera le wake word avec le module Sortie.
- Migration des données Hey Snowy → WhiteSilence — bases séparées, pas de pont. Les obs Hey Snowy restent dans Hey Snowy si tu veux les exporter manuellement.
- Le bouton "communauté" affichant les obs des autres skieurs sur la carte — pas migré en Phase 2, c'est un nice-to-have. À ajouter en option dans le menu "..." plus tard.

## Phase 3 — Module `conditions` & avalanche (WebView Névé) ✅

Module Conditions livré sous forme de **WebView intégrée** chargeant le frontend
Névé hébergé sur Netlify (`https://snow-conditions.netlify.app`). Le HTML appelle
ensuite le backend FastAPI sur Render pour ses données.

Voir `docs/PHASE3_TEST.md` pour le plan de test détaillé.

### Décision d'archi

La Phase 3 a commencé comme une **refonte Flutter native** (models + controller +
cache SQLite + drag de bbox côté carte). Après livraison initiale, on a basculé
vers **une WebView pure** pour les raisons suivantes :

- **Fidélité 1:1 avec le site web** : pas de divergence de comportement
- **Maintenance unique** : tu fais évoluer le HTML, l'app suit automatiquement
- **Avalanche incluse de facto** : le frontend Netlify gère déjà Conditions ET
  Avalanche, donc Phase 4 (qui devait être un module dédié) est absorbée
- **Pas de double code à entretenir**

Trade-offs assumés :
- Pas d'intégration carte unifiée (la WebView est un îlot)
- Pas d'offline (besoin du backend pour les données ET de Netlify pour la UI)
- Léger décalage stylistique entre l'UI HTML et le reste de WhiteSilence

### Fichiers

```
lib/modules/conditions/
├── conditions_overlay.dart           ← MapModuleOverlay minimaliste (bouton)
└── conditions_webview_screen.dart    ← Écran plein écran WebView
```

`lib/core/secrets.dart` expose `WSSecrets.neveFrontendUrl` (Netlify) en plus
de `neveApiUrl` (Render, conservé pour d'éventuels appels Flutter natifs futurs).

### Le code Flutter natif est conservé en archive

Si on veut un jour refaire une vraie intégration Flutter (carte unifiée, position
GPS partagée, offline) :
- Code initial : tar `whitesilence_phase3.tar.gz`
- Itérations successives : `whitesilence_phase3_idle_fix`, `whitesilence_phase3_draw_bbox`,
  `whitesilence_coldstart_fix`

## Phase 4 — Module `avalanche` ⬇️ ABSORBÉE EN PHASE 3

Le frontend Névé gère déjà l'affichage avalanche (endpoint `/avalanche` du
backend). La Phase 4 originale (cônes Flutter + slider risque) est donc
**absorbée par la Phase 3 WebView** et disparaît de la roadmap.

Si on veut un jour une intégration native pour les cônes (par exemple pour
afficher les zones dangereuses directement sur la carte WhiteSilence partagée),
on créera un module dédié à ce moment-là. Le pattern `MapModuleOverlay` permet
de l'ajouter sans toucher au reste.

## Phase 3.5 — Module `ideas` (WebView Ski Touring Live) ✅

Module de recommandation d'itinéraires de ski de rando, intégré sous forme
de WebView Streamlit. Source : https://github.com/Tinevagio/Ski-touring-live

Voir `docs/PHASE3_5_IDEAS_TEST.md` pour le plan de test détaillé.

### Décision d'archi
Même stratégie que Phase 3 (Conditions) — WebView in-app de l'app Streamlit
hébergée sur Streamlit Cloud. Maintenance unique côté Streamlit, pas de
double code.

### Conséquence sur la bottom bar
Le module **Avalanche** (qui n'avait pas d'implémentation dédiée puisque
absorbé par Conditions) est retiré du registry pour faire place au nouveau
module **Idées**. La bottom bar reste à 5 entrées visibles.

### Fichiers
```
lib/modules/ideas/
├── ideas_overlay.dart            ← MapModuleOverlay minimaliste
└── ideas_webview_screen.dart     ← Écran plein écran WebView Streamlit
```

`lib/core/secrets.dart` expose `WSSecrets.ideasUrl` (Streamlit Cloud par
défaut, override via `IDEAS_URL` dans `.env`).

## Phase 5 — Module `tour`

C'est le module fédérateur — il enregistre la trace GPX et **agrège ce que les autres modules ont produit pendant la sortie**.

### Fonctionnalités
- Bouton "Démarrer sortie" (gros, central, FAB en accueil)
- En arrière-plan : enregistre la trace GPS en SQLite
- Fin de sortie → écran récap :
  - Trace + statistiques (distance, D+, durée)
  - Observations neige enregistrées pendant la sortie
  - Conditions BERA du jour
  - Export GPX + partage

## Phase 6 — Manifeste public + Play Store

- [ ] Page d'onboarding au premier lancement (3 swipes : philo, modules, démarrage)
- [ ] README béton avec captures
- [ ] Icône d'app (le sommet stylisé)
- [ ] Screenshots Play Store
- [ ] Description Play Store qui claque
- [ ] Build signé + premier upload
- [ ] **Proxy backend pour les clés API** (Groq, Picovoice) — critique pour la distribution publique

## Stratégie git

```bash
# Au début de chaque phase
git checkout -b phase-N-<module>

# Migration progressive : on ne touche pas aux repos sources tant que
# la phase N+1 n'est pas démarrée. Ça permet de cherry-picker des fixes.

# À la fin de toutes les phases
# → archiver ghosttime/, hey-snowy/, snow-conditions-frontend/ en README "moved to WhiteSilence"
# → garder snow-conditions/ (backend) et ski-touring-live/ (cron BERA) tels quels
```
