# Phase 6 — Logo & Icône d'app WhiteSilence

Ce patch ajoute :
- **L'icône d'app Android** générée à partir du logo officiel (toutes tailles, mdpi → xxxhdpi, + adaptive icon Android 13+)
- **Le logo (montagne + monogramme WS)** affiché en haut à gauche de la carte, tap → ouvre les Réglages
- **Le nom officiel "WhiteSilence"** dans le manifeste Android (à appliquer manuellement, cf. ci-dessous)

## Étape 1 — Extraction du tar

```powershell
cd C:\flutter\whitesilence
tar -xzf chemin\vers\whitesilence_logo_icon.tar.gz
```

Le tar contient :
```
assets/images/
├── icon_1024.png                    ← icône d'app pleine (logo + texte sur fond clair)
├── icon_adaptive_foreground.png     ← foreground transparent pour Adaptive Icon
└── logo_mountain.png                ← montagne+WS seul, pour le bandeau carte

lib/
├── core/map/map_screen.dart         ← _LogoBadge ajouté en haut à gauche
└── (etc.)

pubspec.yaml                         ← config flutter_launcher_icons + assets
docs/PHASE6_LOGO_TEST.md             ← ce fichier
```

## Étape 2 — Générer les icônes Android

```powershell
flutter pub get
flutter pub run flutter_launcher_icons
```

Cela génère automatiquement :
- `android/app/src/main/res/mipmap-mdpi/launcher_icon.png` (48×48)
- `android/app/src/main/res/mipmap-hdpi/launcher_icon.png` (72×72)
- `android/app/src/main/res/mipmap-xhdpi/launcher_icon.png` (96×96)
- `android/app/src/main/res/mipmap-xxhdpi/launcher_icon.png` (144×144)
- `android/app/src/main/res/mipmap-xxxhdpi/launcher_icon.png` (192×192)
- + tous les fichiers d'adaptive icon (Android 13+)

## Étape 3 — Modifier le manifeste Android

Édite `android/app/src/main/AndroidManifest.xml` et modifie les attributs
`android:label` et `android:icon` du `<application>` :

```xml
<application
    android:label="WhiteSilence"
    android:name="${applicationName}"
    android:icon="@mipmap/launcher_icon"
    ...>
```

**Important** : `launcher_icon` (avec underscore) doit matcher exactement le
nom `android: "launcher_icon"` dans le bloc `flutter_launcher_icons` du
pubspec. Si tu l'avais déjà nommé autrement avant, supprime les anciens
fichiers `ic_launcher.*` dans les mipmap pour éviter la confusion.

## Étape 4 — Rebuild propre

```powershell
flutter clean
flutter run
```

Le `flutter clean` est important parce qu'on touche aux ressources natives
Android (icônes mipmap) — le cache de build doit être régénéré.

## Vérification

### Icône d'app
- Quitte l'app, regarde le drawer d'apps Android : tu dois voir le logo
  WhiteSilence à la place de l'icône Flutter par défaut.
- Sur Android 13+ avec icônes "thématiques" actives : l'adaptive icon doit
  bien s'afficher quelle que soit la forme du launcher (cercle, squircle...).

### Logo sur la carte
- Lance l'app → en haut à gauche de la carte tu dois voir le logo
  montagne+WS sur fond blanc cassé.
- Tap dessus → ouvre l'écran Réglages.
- Le chip du module actif (ex: "Conditions") reste affiché à droite du logo.

## Troubleshooting

### "asset not found: assets/images/logo_mountain.png"
Lance `flutter pub get` puis hot restart (`R` majuscule dans la console
`flutter run`). Si ça persiste, vérifie que `assets/images/` est listé
dans `pubspec.yaml` sous `flutter: assets:`.

### Icône inchangée après build
- Vérifie que `flutter pub run flutter_launcher_icons` s'est bien exécuté
  sans erreur (regarde le output console).
- Vérifie le contenu de `android/app/src/main/res/mipmap-xxxhdpi/` : tu
  dois voir `launcher_icon.png` (≠ `ic_launcher.png` original).
- Vérifie le manifeste : `android:icon="@mipmap/launcher_icon"` (PAS
  `@mipmap/ic_launcher`).
- Désinstalle complètement l'app de ton téléphone puis réinstalle —
  Android cache parfois l'ancienne icône.

### Nom d'app inchangé
- Vérifie `android:label="WhiteSilence"` dans le manifeste.
- Désinstalle et réinstalle l'app.

### Logo flou ou mal détouré
Le logo source est un JPEG basse résolution (420×354). J'ai fait du mieux
possible pour détourer le fond gris, mais des micro-artefacts peuvent
subsister sur les bords. Si tu veux un résultat parfait, sors le logo en
SVG ou PNG transparent depuis ton outil de design d'origine, et envoie-moi
la version vectorielle pour qu'on régénère.
