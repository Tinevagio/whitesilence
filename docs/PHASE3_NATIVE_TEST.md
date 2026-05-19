# Phase 3 — Module Conditions natif complet

Refonte du module Conditions en intégration **native Flutter** complète.
Remplace la version WebView Netlify qui était en place depuis le patch
`whitesilence_phase3_webview.tar.gz`.

## Ce qui change

### Avant (WebView)
- Bouton "Ouvrir conditions Névé" → push d'un écran plein écran
- WebView de https://snow-conditions.netlify.app
- UI HTML/JS chargée → look web, pas d'intégration carte
- Pas d'offline

### Après (natif complet)
- Pas d'écran séparé : tout sur la carte WhiteSilence partagée
- **Mode "Dessine ta zone"** : bouton dans l'action panel → drag sur la carte → fetch grille + BERA
- **Layer grille natif** : cercles colorés par condition de neige (poudre, transfo, etc.) sur ta bbox
- **Slider heure** : visualisation des conditions sur 24h dans l'action panel
- **Chip BERA** : niveau de risque massif visible en permanence
- **Toggle Avalanche** : zones de départ (points rouges) + cônes de propagation (polygones rouges) sur la carte
- **Slider risque BERA override** : simule un risque différent du réel pour exploration
- **Tap sur la carte** → bottom sheet de détail 24h horaires pour le point exact
- **Cache 6h offline** : la donnée reste dispo en montagne sans réseau
- **Cold start handling** : ping `/health` au démarrage du module, indicateur "Backend en cours de réveil…" si Render dort

## Fichiers

```
lib/modules/conditions/
├── conditions_overlay.dart           ← MapModuleOverlay avec layers + action panel + bloc avalanche
├── conditions_controller.dart        ← Orchestrateur d'état (loading/ready/error + drawing + avalanche)
├── condition_detail_sheet.dart       ← Bottom sheet 24h horaires au tap d'un point
├── models/
│   ├── condition_code.dart           ← Enum codes + labels FR + couleurs
│   ├── bera_info.dart                ← Bulletin Météo France
│   ├── point_conditions.dart         ← Réponses /conditions et /conditions/point
│   └── avalanche_zone.dart           ← Nouveau : modèle GeoJSON zones+cônes
└── services/
    ├── conditions_api.dart           ← Client HTTP : /conditions, /conditions/point,
    │                                   /debug/bera, /avalanche, /health
    └── conditions_cache.dart         ← Cache SQLite TTL 6h (table conditions_cache déjà en DB v2)
```

## Installation

### 1. Nettoyer les anciens fichiers WebView

Le tar inclut un script `cleanup_webview.ps1` à exécuter avant l'extraction :

```powershell
cd C:\flutter\whitesilence
# Supprime l'ancien conditions_webview_screen.dart qui n'existe plus
Remove-Item -Force -ErrorAction SilentlyContinue lib\modules\conditions\conditions_webview_screen.dart
```

### 2. Extraire le tar

```powershell
tar -xzf chemin\vers\whitesilence_phase3_native.tar.gz
```

### 3. Build

```powershell
flutter pub get
flutter run
```

Pas de modif native (Android), donc `flutter clean` pas nécessaire.

## Plan de test

### Test 1 — Module Conditions accessible
- Bottom bar → Conditions
- Action panel affiche : "Backend en cours de réveil…" ou "Touche 'Dessiner ma zone'…"
- (Le backend Render peut être en cold start si endormi, 30-90s)

### Test 2 — Dessin de bbox + fetch grille
- Tape **Dessiner ma zone**
- L'action panel devient un bandeau bleu : "Glisse sur la carte pour dessiner ta zone"
- Drag pour dessiner un rectangle (zoom 13-14 conseillé)
- À la fin du drag : rectangle bleu transparent reste visible, et la carte se colore avec les points de la grille
- BERA du massif apparaît en chip dans l'action panel
- Slider heure 0-23h fait évoluer les couleurs au fil du jour

### Test 3 — Détail au tap
- Tap sur un point de la grille
- Bottom sheet : 24h horaires + Munter time-to-go si calibré, conditions détaillées

### Test 4 — Avalanche
- Bouton "Afficher zones d'avalanche" dans l'action panel
- Carte se couvre de zones rouges (points = départs, polygones = cônes)
- Slider risque BERA 1-5 → modifie les zones affichées en live

### Test 5 — Offline
- Avoir une grille fraîche en cache (étape 2)
- Mode avion
- Re-tape "Dessiner ma zone" sur exactement la même zone → grille s'affiche depuis le cache, badge "Données du cache (hors-ligne)"

### Test 6 — Cold start
- App fermée plusieurs heures
- Bottom bar → Conditions
- Affichage discret "Backend en cours de réveil…" pendant ~30-90s
- Puis le module fonctionne normalement

## Points d'attention

### Avalanche est lourd côté backend
L'endpoint `/avalanche` calcule jusqu'à 300 zones de départ + cônes de propagation par bbox. Sur une bbox large à Render free tier, ça peut prendre 30-60s la première fois. C'est pour ça qu'on ne le déclenche **que** sur toggle explicite (jamais automatiquement).

### Cache 6h
La table `conditions_cache` (créée en DB v2) stocke les réponses 6h max. Au-delà, c'est purgé au prochain démarrage du module. Pas de gestion fine pour l'instant — si tu veux ajuster, voir `conditions_cache.dart`.

### Pas de cache pour l'avalanche
Volontaire : l'avalanche dépend du BERA du jour, qui change. Stocker en cache donnerait une fausse impression de fraîcheur. Toujours fetch en live.

### Idées (Streamlit) reste en WebView
Choix assumé : la logique de recommandation Streamlit est complexe (scoring multi-critères), pas portable facilement en Dart. La WebView fait son job pour cet usage.

## Si tu veux revenir à la WebView

Le code WebView est archivé dans `whitesilence_phase3_webview.tar.gz`. Tu peux
l'extraire dans un dossier temporaire pour récupérer `conditions_webview_screen.dart`
et `conditions_overlay.dart` (version WebView).
