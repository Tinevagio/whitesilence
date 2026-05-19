# Build & Signing — Guide step-by-step

Objectif : produire un fichier **`app-release.aab`** signé avec ton keystore, prêt à être uploadé sur Play Console.

⚠️ **CRITIQUE — Le keystore est ta clé d'identité d'app** :
- **Garde-le précieusement** (idéalement dans un coffre-fort numérique : 1Password, Bitwarden, ou backup chiffré sur cloud).
- **Si tu le perds, tu ne pourras plus jamais mettre à jour l'app** — il faudrait republier sous un autre AppID, ce qui veut dire perdre les utilisateurs.
- **Ne le commit JAMAIS dans Git**. Il doit rester en local + backup chiffré.

---

## Étape 1 — Générer le keystore (one-shot, à faire une seule fois)

Ouvre PowerShell et tape (en remplaçant `MON_MOT_DE_PASSE_SOLIDE` par un vrai mot de passe que tu retiendras) :

```powershell
cd C:\flutter\whitesilence
keytool -genkey -v -keystore android/whitesilence-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias whitesilence
```

Le programme te demandera :
- Mot de passe du keystore — choisis-en un solide, retiens-le
- Mot de passe de la clé — utilise **le même** que le keystore (sinon ça complique)
- Nom complet → "Tinevagio"
- Unité organisationnelle → laisse vide ou "Personal"
- Organisation → "Tinevagio"
- Ville → ta ville
- Code pays → FR

Vérification :
```powershell
ls android/whitesilence-release.jks  # doit afficher le fichier
```

**Backup immédiat** :
- Copie `whitesilence-release.jks` dans un endroit sûr hors de ton PC (cloud chiffré, clé USB sécurisée, etc.)
- Note le mot de passe dans ton gestionnaire de mots de passe

---

## Étape 2 — Configurer Gradle pour utiliser le keystore

Crée le fichier `android/key.properties` avec ton mot de passe :

```properties
storePassword=MON_MOT_DE_PASSE_SOLIDE
keyPassword=MON_MOT_DE_PASSE_SOLIDE
keyAlias=whitesilence
storeFile=whitesilence-release.jks
```

**⚠️ Important** : ce fichier contient ton mot de passe en clair. Vérifie qu'il est dans `.gitignore` :

```powershell
# Vérifier
Select-String -Path .gitignore -Pattern "key.properties"
```

S'il n'apparaît pas, ajoute ces lignes au `.gitignore` :

```
# Android signing
android/key.properties
android/*.jks
android/*.keystore
```

---

## Étape 3 — Modifier `android/app/build.gradle`

Ouvre le fichier `android/app/build.gradle` (ou `.kts` selon ta version Flutter) et ajoute le bloc signing.

**Avant la ligne `android {`**, ajoute :

```gradle
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}
```

**Dans le bloc `android {`**, ajoute (avant `buildTypes`) :

```gradle
    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }
```

**Modifie le bloc `buildTypes.release`** :

```gradle
    buildTypes {
        release {
            signingConfig signingConfigs.release
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }
```

---

## Étape 4 — Vérifier l'AppID et la version

Dans `android/app/build.gradle`, vérifie :

```gradle
defaultConfig {
    applicationId "app.whitesilence.whitesilence"  // ← doit être ton AppID
    minSdk 24                                       // Android 7+
    targetSdk 34                                    // Android 14 (exigence 2024)
    versionCode 1                                   // entier, incrémente à chaque release
    versionName "0.1.0"                             // string visible utilisateur
}
```

**Important sur les versions** :
- `versionCode` = entier incrémenté à CHAQUE release (1, 2, 3, ...). Tu ne peux JAMAIS le décrémenter.
- `versionName` = string visible utilisateur ("0.1.0", "1.0", etc.)
- À chaque mise à jour : bump `versionCode +1` ET `versionName` selon semver.

---

## Étape 5 — Build de l'AAB de release

```powershell
cd C:\flutter\whitesilence
flutter clean
flutter pub get
flutter build appbundle --release
```

Le fichier produit sera ici :
```
build/app/outputs/bundle/release/app-release.aab
```

Vérification de la signature :
```powershell
# Doit afficher la clé "CN=Tinevagio..."
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab | findstr "Owner"
```

Si l'output contient `CN=Tinevagio`, la signature est correcte. Si tu vois `CN=Android Debug`, c'est qu'il manque le signing config — refais l'étape 3.

---

## Étape 6 — Test sur ton téléphone avant de pousser

Avant de soumettre, tu peux installer l'AAB localement pour vérifier qu'il fonctionne. C'est plus subtil que l'APK car AAB nécessite `bundletool` :

```powershell
# Télécharge bundletool si pas déjà fait
# https://github.com/google/bundletool/releases (dernière version .jar)

# Génère un APKS depuis l'AAB
java -jar bundletool.jar build-apks --bundle=build/app/outputs/bundle/release/app-release.aab --output=ws.apks --mode=universal --ks=android/whitesilence-release.jks --ks-key-alias=whitesilence

# Installe sur ton téléphone (USB debugging activé)
java -jar bundletool.jar install-apks --apks=ws.apks
```

Alternative plus simple si tu veux juste tester : build un **APK release** (pas accepté Play Store mais utilisable localement) :

```powershell
flutter build apk --release
```

Le fichier sera dans `build/app/outputs/flutter-apk/app-release.apk`. Tu peux le copier sur ton téléphone et l'installer.

---

## Étape 7 — Upload sur Play Console

1. Va sur https://play.google.com/console
2. Crée l'application (compte développeur Google Play requis : 25 € one-shot)
3. Remplis la fiche (utilise les fichiers `play_store_description.md`, `play_store_screenshots_guide.md`, `play_store_checklist.md`)
4. Va dans **Production > Releases > Create new release**
5. Upload `app-release.aab`
6. **Étape critique** : Play Console te demandera si tu veux activer **Play App Signing** (Google gère ta signature en plus de la tienne). **Active-le** — c'est la recommandation actuelle, ça te protège si tu perds ton keystore.
7. Remplis les notes de version (changelog visible utilisateurs)
8. Soumets pour review

Première soumission : 1 à 7 jours de review humaine.

---

## Étape 8 — Test interne avant production

Avant la production publique, tu peux faire un **test interne** :

1. Dans Play Console : **Testing > Internal testing**
2. Crée une release avec ton AAB
3. Liste les emails des testeurs (toi + 2-3 amis qui ont un compte Google)
4. Récupère le lien d'opt-in et envoie-le aux testeurs
5. Ils peuvent installer via Play Store comme une vraie app

Avantage : valide toute la chaîne (Play Store install, mise à jour OTA, etc.) sans risque de review prod.

---

## Checklist finale avant publication

- [ ] Keystore généré et **backupé** dans un endroit sûr
- [ ] `key.properties` créé et exclu de Git
- [ ] `android/app/build.gradle` modifié avec signing config
- [ ] `versionCode` et `versionName` corrects dans `build.gradle`
- [ ] `targetSdk 34` minimum
- [ ] `flutter build appbundle --release` produit un AAB sans erreur
- [ ] AAB testé sur téléphone (au moins en APK release ou via bundletool)
- [ ] Repo GitHub créé et public
- [ ] GitHub Pages activé pour `docs/privacy.html`
- [ ] Compte Play Console créé (25 € payés)
- [ ] Fiche Play Console remplie (titre, descriptions, screenshots, catégorisation, data safety, content rating)
- [ ] URL politique de confidentialité fonctionnelle (test : ouvrir l'URL en navigation privée)
- [ ] Test interne lancé avec 2-3 amis
- [ ] Retours du test interne intégrés
- [ ] Production release créée et soumise

🎿 Et voilà, WhiteSilence va officiellement exister sur le Play Store.
