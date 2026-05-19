# Phase 3.5 — Module Idées (WebView Ski Touring Live)

Module de recommandation d'itinéraires de ski de rando, intégré sous forme
de **WebView Streamlit** dans WhiteSilence.

## Contexte

- Source : https://github.com/Tinevagio/Ski-touring-live
- Déploiement : https://ski-touring-live.streamlit.app
- Concept : croise 150+ itinéraires × météo × BERA × niveau utilisateur
  pour suggérer les meilleures sorties du jour
- Pattern : identique au module Conditions (WebView in-app)

## Changements

### Bottom bar — Avalanche retiré, Idées ajouté

Le module **Avalanche** est retiré de la bottom bar (sa logique métier est
déjà couverte par le frontend Névé chargé dans le module Conditions). À sa
place, le nouveau module **Idées** (`Icons.lightbulb_outline`).

Bottom bar finale :

| Position | Icône | Label | Action |
|---|---|---|---|
| 1 | 🕐 | Temps | Munter + isochrones |
| 2 | ❄️ | Neige | Observations vocales |
| 3 | ☁️ | Conditions | WebView Névé (conditions + BERA + avalanche) |
| 4 | 💡 | Idées | WebView Streamlit (recommandations sorties) |
| 5 | 🎒 | Sortie | (Phase 5 — non implémenté) |

### Nouveaux fichiers

```
lib/modules/ideas/
├── ideas_overlay.dart            ← MapModuleOverlay minimaliste (bouton)
└── ideas_webview_screen.dart     ← Écran plein écran WebView Streamlit
```

### Modifications

- `lib/core/module_registry.dart` — enum `avalanche` → `ideas`, catalog
  mis à jour avec icône + description
- `lib/core/secrets.dart` — getter `WSSecrets.ideasUrl` (lit `IDEAS_URL`
  ou défaut `https://ski-touring-live.streamlit.app`)
- `.env.template` — ajoute `IDEAS_URL=https://ski-touring-live.streamlit.app`
- `lib/main.dart` — instancie `IdeasModuleOverlay()` dans le shell

## Installation

Dézippe le tar par-dessus, puis :

```powershell
cd C:\flutter\whitesilence
flutter pub get
flutter run
```

Pas de nouvelle dépendance (`webview_flutter` est déjà installé depuis
la phase 3). Pas de nouvelle permission Android.

### Pour activer la variable d'environnement

Si ton `.env` existe déjà, ajoute la ligne :
```
IDEAS_URL=https://ski-touring-live.streamlit.app
```

Si tu ne l'ajoutes pas, `WSSecrets.ideasUrl` retombera sur cette même
valeur par défaut codée en dur, donc ça marchera quand même.

## Plan de test

### Test 1 — Le module Idées est visible
- Lance l'app → la bottom bar a 5 modules
- Le 4ème est **Idées** (icône ampoule)
- Le module **Avalanche** n'apparaît plus

### Test 2 — Ouverture WebView Streamlit
- Tape **Idées** → action panel : *« Trouve les meilleures sorties du jour
  selon la météo et le BERA »* + bouton **Ouvrir les idées de sortie**
- Tape le bouton → écran plein écran avec :
  - AppBar « Idées de sortie » + bouton refresh
  - Bandeau « Streamlit met ~30s à se réveiller… » si cold start
- Après 30-60s : le dashboard Streamlit apparaît avec carte + filtres + top 3

### Test 3 — Retour vers la carte
- Flèche back de l'AppBar
- Retour à la WSMapScreen avec le module Idées sélectionné

### Test 4 — Refresh manuel
- Bouton refresh dans l'AppBar → reload du Streamlit

## Points d'attention

### Cold start Streamlit Cloud
Streamlit Cloud (free) met les apps en veille après inactivité, comme Render.
Le wake-up prend typiquement 30-60s. Le bandeau « Streamlit met ~30s à se
réveiller… » prévient l'utilisateur tant que la page n'a pas avancé au-delà
de 15% de chargement.

### UX "data scientist"
Streamlit fait du HTML/CSS responsive mais reste typé "interface de notebook".
Tu verras des sliders, des dropdowns, etc. dans un style différent du reste
de WhiteSilence. C'est le compromis assumé (cf. Phase 3 Conditions) :
**fidélité au site original > cohérence visuelle**.

### Pas d'intégration avec la carte WhiteSilence
Comme pour Conditions, la WebView est un îlot. Pas de pin sur la carte
partagée pour montrer les sorties suggérées, pas de bascule "naviguer vers
cette sortie" qui ouvrirait le module Temps avec l'isochrone. Si on veut un
jour ça, il faudra une intégration native (cf. roadmap MIGRATION.md).

## Si tu veux retirer le module plus tard

Tout est isolé dans `lib/modules/ideas/` + 1 ligne dans `main.dart` + 1 entrée
dans le catalog. Suppression propre en 2 minutes.
