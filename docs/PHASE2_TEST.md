# Phase 2 — Module Neige (migration Hey Snowy)

## Ce qui a changé depuis Phase 1

### Nouveaux fichiers

```
.env.template                                  ← clés API (à copier en .env)
.gitignore                                     ← ignore .env, BDD, HGT

lib/core/secrets.dart                          ← accès typé aux clés
lib/core/storage/
└── db.dart                                    ← BDD SQLite globale whitesilence.db
lib/core/audio/
├── recording_service.dart                     ← enregistrement micro (ChangeNotifier)
└── sound_service.dart                         ← bips de feedback

lib/modules/snow/                              ← Module Neige
├── models/observation.dart
├── services/
│   ├── transcription_service.dart             ← Whisper via Groq
│   ├── ai_service.dart                        ← Llama 3.3 via Groq
│   ├── supabase_service.dart                  ← partage anonyme (opt-in)
│   ├── processing_service.dart                ← pipeline batch
│   └── wake_word_service.dart                 ← pont natif (désactivé, attente Phase 5)
├── snow_dao.dart                              ← accès BDD
├── snow_controller.dart                       ← orchestrateur
├── snow_overlay.dart                          ← pins + action panel
└── review_screen.dart                         ← liste des obs
```

### Fichiers modifiés

- `pubspec.yaml` — ajout `flutter_dotenv`, `flutter_sound`, `just_audio`,
  `permission_handler`, `supabase_flutter`. Déclare `.env` comme asset.
- `lib/core/theme/colors.dart` — `snowTypeColors` aligné sur Hey Snowy
  (poudre, moquette, transfo, béton, croûte, ventée, lourde, humide, purge)
- `lib/main.dart` — charge `.env`, initialise Supabase, branche
  `SnowModuleOverlay` à côté de `TimeModuleOverlay`

## Installation

### 1. Dézipper par-dessus

```powershell
cd C:\flutter\whitesilence
# Dézippe le tarball de la phase 2 dans le dossier
```

### 2. Régénérer la clé Groq

**Important** : la clé Groq de Hey Snowy était commitée en clair dans ton repo, elle a donc transité dans cette conversation. Va sur https://console.groq.com/keys et :
1. Révoque l'ancienne clé `gsk_njAw2u...`
2. Génère une nouvelle clé
3. Note-la pour l'étape 3

### 3. Créer le `.env`

```powershell
cp .env.template .env
# Édite .env et colle tes clés :
# GROQ_API_KEY=gsk_LA_NOUVELLE_CLE
# SUPABASE_URL=https://ergfihxckvzilpkupdef.supabase.co
# SUPABASE_ANON_KEY=eyJhbGc...     (la même qu'avant, c'est une clé publique anon)
```

Si tu laisses `GROQ_API_KEY` vide → pas de transcription ni d'IA, mais
les obs vocales restent enregistrées localement en audio brut.
Si tu laisses les `SUPABASE_*` vides → pas de partage communautaire,
les obs restent locales.

### 4. Ajouter les permissions Android

Édite `android/app/src/main/AndroidManifest.xml` et ajoute **avant** la
balise `<application>` :

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.INTERNET"/>
```

(`ACCESS_FINE_LOCATION` est déjà là depuis Phase 0.)

### 5. Lancer

```powershell
flutter pub get
flutter run
```

Au premier lancement, Android va demander la permission micro la première
fois que tu appuies sur le bouton micro. Accepte.

## Plan de test

### Test 1 — L'app démarre, le module Neige est visible
- Lance l'app → carte topo + bottom bar à 5 modules
- Tape sur **Neige** (icône flocon) dans la bottom bar
- L'action panel en bas affiche : `Tap micro pour enregistrer une observation` + bouton **Enregistrer une obs** bleu + bouton "..." à droite

### Test 2 — Enregistrement d'une observation
- Tape **Enregistrer une obs**
- Permission micro demandée (premier usage uniquement) → accepte
- Bip aigu de démarrage
- Le bouton devient rouge "Stop", message `Décris la neige…`
- Parle pendant ~5s : *"Belle moquette à 2400 mètres, exposition sud"*
- Tape **Stop** (ou laisse les 15s s'écouler — auto-stop)
- Bip grave de fin
- Un pin gris apparaît sur la carte à ta position (la couleur viendra après IA)

### Test 3 — Pipeline IA (transcription + Llama + upload)
- Tape sur les 3 points "..." → **Traiter les obs en attente**
- Status : `Traitement 1/1` puis barre de progression
- Quelques secondes plus tard :
  - Le pin gris devient vert (moquette)
  - Status : `1 traitée · 1 partagée`
- Tape sur le pin → bottom sheet : type "moquette", altitude, transcript IA

### Test 4 — Sans `.env` (test dégradé)
- Renomme `.env` → `.env.bak`
- Hot restart
- Le bouton micro fonctionne, l'obs est enregistrée en audio
- Le pin reste gris (= pas encore traité)
- Tape "Traiter les obs en attente" → log dans le terminal :
  `[transcription] GROQ_API_KEY absent — transcription désactivée`
- L'app ne plante pas, juste pas d'enrichissement IA

### Test 5 — Liste des observations (review screen)
- Tape sur "..." → **Voir toutes les observations**
- Liste groupée par date (`Aujourd'hui`, `Hier`, dates)
- Tape un trash icon → l'obs disparaît

### Test 6 — Désactiver le partage communautaire
- "..." → **Désactiver le partage**
- Enregistre une nouvelle obs, traite-la
- Status final : `1 traitée · 0 partagée` (au lieu de `1 partagée`)
- Vérifie sur Supabase : l'obs n'est pas dans la table

## Points d'attention

### Compatibilité avec Hey Snowy installé en parallèle
WhiteSilence utilise une BDD différente (`whitesilence.db` au lieu de `hey_snow.db`) et un dossier d'audio différent (dans le `getApplicationDocumentsDirectory` de l'app `whitesilence`). Tu peux donc garder les deux installées sans conflit. Tes obs Hey Snowy ne sont PAS migrées automatiquement — c'est volontaire (architecture propre, pas d'historique douteux).

### Permissions micro/internet/GPS
Si l'app ne fait rien quand tu appuies sur micro :
- Vérifie que tu as accepté la permission micro au système Android
- Vérifie dans Réglages Android → Apps → WhiteSilence → Permissions
- Sinon : `adb shell pm grant app.whitesilence.whitesilence android.permission.RECORD_AUDIO`

### Wake word "Hey Snow"
Pas activable en Phase 2. Le pont Dart existe (`wake_word_service.dart`) mais le code natif Android (Kotlin + ONNX) n'a pas été migré — il viendra en Phase 5 avec le module Sortie. Le service détecte l'absence du canal natif (`MissingPluginException`) et reste silencieux.

### Régénération automatique de la BDD
Si tu modifies la version SQLite (`_dbVersion` dans `db.dart`) sans écrire la migration correspondante dans `_onUpgrade`, **tu perdras toutes tes obs**. Pour la Phase 2 c'est `version: 1` — laisse à 1 sauf si tu veux faire évoluer le schéma.

## Bugs probables à signaler

- **`PlatformException: missing plugin` au démarrage** : `flutter pub get` n'a pas tout récupéré. Refaire `flutter clean && flutter pub get && flutter run`.
- **Permission micro refusée silencieusement** : sur certains Android, il faut redémarrer l'app après avoir donné la permission via Réglages système. Hot restart ne suffit pas.
- **Pas de bip au démarrage de l'enregistrement** : le device est peut-être en mode silencieux ; les bips ne shuntent pas le mode silencieux.
- **`[supabase] init failed: ...`** au démarrage : URL ou clé Supabase malformée dans `.env`. Vérifie que la clé ne contient pas de guillemets ou de saut de ligne.
- **L'IA met >30s** : Groq peut avoir des pics de latence aux heures de pointe européennes. C'est normal, ça remontera.
