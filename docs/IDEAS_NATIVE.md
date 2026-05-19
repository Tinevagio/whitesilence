# Module Idées natif Flutter

Remplace l'ancienne WebView Streamlit par un module 100 % natif WhiteSilence
qui consomme l'API FastAPI ski-touring-api (voir repo séparé).

## Installation

```powershell
cd C:\flutter\whitesilence
tar -xzf chemin\vers\whitesilence_ideas_native.tar.gz
flutter pub get
flutter run
```

`flutter pub get` est nécessaire pour la nouvelle dépendance `url_launcher`.

## Architecture

```
lib/modules/ideas/
├── ideas_overlay.dart              ← MapModuleOverlay (entry point)
├── ideas_controller.dart           ← orchestrateur état + filtres + résultats
├── models/
│   ├── idea.dart                   ← Idea + MeteoSummary + BeraSummary + FeaturesDetail
│   ├── ideas_filter.dart           ← critères utilisateur
│   └── ideas_response.dart         ← IdeasResponse + IdeasMetadata
├── services/
│   └── ideas_api.dart              ← client HTTP avec cold start handling
└── widgets/
    ├── idea_pin.dart               ← marker numéroté sur la carte
    ├── idea_card.dart              ← card du carousel
    ├── idea_detail_sheet.dart      ← bottom sheet riche + cross-module
    └── ideas_filters_sheet.dart    ← bottom sheet de filtres

lib/core/
├── module_navigator.dart           ← NOUVEAU singleton pour switch cross-module
├── map/map_module_overlay.dart     ← ajout buildBottomSheet()
└── map/map_screen.dart             ← layout adapté (carousel + action panel)
```

## Configuration

URL backend par défaut : `https://ski-touring-api.onrender.com`.
Pour la changer, ajouter dans `.env` :
```
IDEAS_API_URL=https://mon-backend.com
```

## UX

1. **Bottom bar → Idées**
2. **Module activé** → action panel "Idées" en bas avec :
   - Header replié/déplié (chevron)
   - Résumé filtres : "S3 · 800-1500m · 5 idées"
   - Boutons "Filtres" + "Trouver"
3. **Tap "Filtres"** → bottom sheet avec :
   - Date (J0-J7)
   - Niveau S1-S5
   - Range D+ (slider)
   - Expositions (chips multi-select)
   - Massifs (chips multi-select, depuis /metadata)
   - Nombre de résultats (slider 3-20)
   - Toggle IA
4. **Tap "Trouver"** → fetch /ideas, carousel apparaît au-dessus du panel
5. **Carousel horizontal** : 5+ cards swipeable. La card active = pin
   sélectionné sur la carte (et vice-versa : tap pin → scroll vers card)
6. **Tap card** → bottom sheet de détail complet avec :
   - Score IA mis en avant (étoile + qualité + note/10)
   - Détails itinéraire, météo, BERA
   - Expander "Détails IA" (features 7j)
   - **Boutons cross-module** :
     - "Mon temps" → bascule module Temps, destination = sommet
     - "Conditions" → bascule module Conditions, bbox auto
   - Lien externe Camptocamp/Skitour

## Cross-module : comment ça marche

Singleton `ModuleNavigator` (lib/core/module_navigator.dart) :
- `switchToTimeWithTarget(LatLng)` : passe au module Temps avec destination
- `switchToConditionsWithBbox(LatLng sw, LatLng ne)` : passe à Conditions
  avec bbox
- Le shell `WSShell` écoute `requestedModule` et change `_active`
- Le module cible consomme le pending payload dans son `buildMapLayers`

## Plan de test

### Test 1 — Cold start
- Quitte l'app, attends 30+ min (Render dort)
- Bottom bar → Idées
- Action panel affiche "Backend en cours de réveil…" puis "Configure tes filtres."
- ~30-60s d'attente normale au premier appel.

### Test 2 — Recherche
- Filtres → date demain, S3, 800-1500m, toutes expos, tous massifs, 5 idées
- "Trouver" → cartes apparaissent, pins numérotés sur la carte
- Status "5 idées pour printemps" (ou la saison correspondante)

### Test 3 — Sélection
- Swipe le carousel → le pin sélectionné change sur la carte
- Tap un pin → le carousel scrolle vers la card correspondante
- Tap card → bottom sheet détail

### Test 4 — Cross-module Temps
- Bottom sheet détail → "Mon temps"
- Bascule sur module Temps, isochrones calculées vers le sommet sélectionné

### Test 5 — Cross-module Conditions
- Bottom sheet détail → "Conditions"
- Bascule sur module Conditions, grille fetchée sur ~5km autour du sommet

### Test 6 — Lien externe
- Bottom sheet détail → "Voir sur Camptocamp"
- Ouvre le navigateur sur la page de l'itinéraire

## Notes

- L'API consommée est `ski-touring-api` (repo séparé). Voir le README de ce
  repo pour le déploiement.
- Le SHA des données n'est pas figé : le backend fetch toujours la dernière
  version de la branche `main`. Mises à jour quotidiennes par cron côté repo
  `Ski-touring-live`.
- Pas d'offline : si le backend est down ou hors réseau, on affiche une erreur
  claire. Choix assumé pour ce module (cf. discussion plan d'attaque).
- Streamlit reste accessible en parallèle (le repo Ski-touring-live continue
  de tourner sur streamlit.app). On peut s'en servir comme référence/debug.
