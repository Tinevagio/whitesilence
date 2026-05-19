# Phase 3 — Module Conditions (version WebView)

> **Note** : Cette phase a été révisée. La version initiale était une refonte
> Flutter native du frontend Névé. Elle a été remplacée par une **WebView
> chargeant le frontend HTML servi par le backend** pour gagner en fidélité
> et en simplicité.

## Architecture

```
WhiteSilence (Flutter)             Backend Névé (Render)
─────────────────────              ──────────────────────
ConditionsOverlay                  /        → Front End V7.html
   ↓ (bouton)                      /conditions, /avalanche, etc.
ConditionsWebViewScreen   ◄────►   → endpoints API consommés
   (WebView du HTML)                  par le JS du HTML
```

## Fichiers

```
lib/modules/conditions/
├── conditions_overlay.dart           ← MapModuleOverlay minimaliste (bouton)
└── conditions_webview_screen.dart    ← Écran plein écran WebView

docs/
├── BACKEND_PATCH_PHASE3.md           ← Modif FastAPI à appliquer côté backend
└── PHASE3_TEST.md                    ← Ce fichier
```

## Installation

### 1. Patch backend FastAPI

**Avant tout**, applique le patch `BACKEND_PATCH_PHASE3.md` à ton repo
`snow-conditions/api/main.py` et redéploie sur Render. Sans ça, l'URL
`https://snow-conditions.onrender.com/` renvoie un 404 et la WebView
affiche une erreur.

Test rapide après déploiement :
```
curl -I https://snow-conditions.onrender.com/
# Doit retourner : HTTP/1.1 200 OK + Content-Type: text/html
```

### 2. Installer le patch Flutter

```powershell
cd C:\flutter\whitesilence
tar -xzf chemin\vers\whitesilence_phase3_webview.tar.gz
flutter pub get
flutter run
```

`webview_flutter: ^4.10.0` est ajouté dans `pubspec.yaml`. Pas de
nouvelle permission Android (INTERNET est déjà là depuis Phase 2).

### 3. URL configurable (optionnel)

Si tu utilises une instance de dev local du backend, dans `.env` :
```
NEVE_API_URL=http://10.0.2.2:8000    # émulateur
NEVE_API_URL=http://192.168.1.X:8000  # téléphone physique
```

## Plan de test

### Test 1 — Module accessible
- Lance l'app → bottom bar → **Conditions**
- L'action panel affiche : *« Conditions de neige + BERA, vue web complète »* + bouton **Ouvrir conditions Névé**

### Test 2 — Ouverture WebView
- Tape **Ouvrir conditions Névé** (ou n'importe où sur la carte)
- Écran plein écran avec :
  - AppBar « Conditions de neige » + bouton refresh
  - Barre de progression linéaire en haut
  - Bandeau « Réveil du serveur… » si Render est en cold start
- Après quelques secondes (ou ~1 min en cold start) : le frontend V7 apparaît
- Tu peux dessiner ta bbox, naviguer, voir conditions et BERA comme sur le site

### Test 3 — Retour vers la carte
- Flèche back de l'AppBar (ou bouton Android back)
- Retour à la WSMapScreen avec le module Conditions toujours sélectionné

### Test 4 — Refresh manuel
- Bouton refresh dans l'AppBar de la WebView
- La page se recharge

### Test 5 — Erreur réseau
- Active le mode avion
- Ouvre Conditions → ouvre WebView
- Écran d'erreur propre : « Impossible de charger les conditions » + bouton Réessayer

## Points d'attention

### Pas d'intégration avec la position GPS WhiteSilence
La WebView est un îlot. Si tu veux voir tes conditions à ta position GPS, il faut soit que le JS utilise la geolocation du navigateur (qui demandera sa propre permission Android), soit qu'on passe la position via un paramètre d'URL au lancement. Faisable, mais hors-périmètre.

### Pas d'offline
La WebView a besoin du backend pour servir le HTML. Hors-ligne → écran d'erreur. Le cache SQLite de la version Flutter native a été supprimé. La table `conditions_cache` dans `whitesilence.db` reste mais n'est plus utilisée (cosmétique, on la dropera lors du prochain bump de schéma).

### Cold start Render reste un sujet
Le bandeau « Réveil du serveur… » s'affiche pendant le wake-up. Pour gommer ce comportement :
- UptimeRobot gratuit qui ping `/health` toutes les 14 min
- Render Starter (~7$/mois) sans sleep

### Look web vs look Flutter
La WebView fait du HTML/CSS dans une app Flutter. Léger décalage stylistique avec le reste de WhiteSilence. Compromis assumé : fidélité au site original > cohérence visuelle.

## Bugs probables à signaler

- **WebView blanche en permanence** : signe que le backend ne répond pas, ou que le HTML n'est pas servi à `/`. Vérifie : `curl https://snow-conditions.onrender.com/` doit retourner du HTML.
- **Le JS du frontend ne charge pas les conditions** : potentiel souci CORS depuis la WebView. Le backend a déjà `allow_origins=["*"]` donc ça devrait passer ; si ça râle, regarde la console navigateur via DevTools (`flutter run -d chrome`).
- **AppBar superposée au header du HTML** : le HTML a déjà ses titres. Si ça te gêne, on peut masquer notre AppBar.
- **`MissingPluginException`** : `flutter clean && flutter pub get && flutter run`.

## Si tu veux revenir à la version Flutter native

Le code de la version Flutter native (avec models, controller, cache SQLite, drag de bbox) est versionné dans les tar de la Phase 3 originale (`whitesilence_phase3.tar.gz` + ses patchs). Tu peux les extraire dans un dossier temporaire pour retrouver le code si besoin.
