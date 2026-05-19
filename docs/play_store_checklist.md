# Checklist Play Console — WhiteSilence

Ce document liste tout ce qu'il faut préparer avant de soumettre WhiteSilence
au Play Store. Les exigences proviennent de Google Play Console (mai 2026).

---

## 1. Icône d'application

| Item | Format | Dimensions | État |
|---|---|---|---|
| Icône Play Store | PNG (sans transparence) | **512 × 512 px** | ⏳ à générer depuis icon_1024.png |
| Icône in-app launcher | déjà gérée par flutter_launcher_icons | adaptive 108×108 | ✅ existant |

**Note** : l'icône 512 PlayStore doit être PNG sans canal alpha. Si tu pars de `icon_1024.png` et qu'il a un fond blanc opaque, c'est OK. Si fond transparent, il faudra ajouter un fond.

→ Commande pour vérifier : `identify -format "%[channels]" assets/images/icon_1024.png` (s'il y a `rgba` = alpha présent).

---

## 2. Feature Graphic (bannière en haut de la fiche)

| Item | Format | Dimensions |
|---|---|---|
| Feature graphic | JPG ou PNG sans alpha | **1024 × 500 px** |

**Contenu suggéré** : montagne enneigée en arrière-plan, logo WhiteSilence centré ou à gauche, baseline "La seule trace, c'est celle dans la neige."

**Important** : pas de texte trop petit (sera réduit sur mobile). Pas de mention de prix, pas de "5 étoiles", pas de "TÉLÉCHARGER MAINTENANT" — Google refuse ces éléments commerciaux racoleurs.

---

## 3. Screenshots — par taille d'appareil

### Phone (obligatoire, minimum 2 max 8)

| Item | Format | Dimensions min | Dimensions max |
|---|---|---|---|
| Screenshots phone | PNG/JPG sans alpha | 320×320 | 3840×3840 |
| Ratio | Portrait recommandé | 9:16 idéal | |

**Mes recommandations** : 4-6 screenshots qui racontent une histoire :

1. **Module Temps** — carte avec isochrones colorés depuis position GPS + panel "Time To Go"
2. **Module Conditions** — heatmap d'enneigement + slider d'heure + bandeau BERA
3. **Module Idées** — liste de sorties avec scores, badge IA visible
4. **Module Neige (Hey Snowy)** — interface vocale active
5. **Mode gants** — affichage avec gros boutons, lisible avec gants
6. **Onboarding** — la page 1 avec "Sans inscription / Sans tracking / Open source"

### Tablet 7" (optionnel mais recommandé)
Mêmes exigences que phone, en format paysage.

### Tablet 10" (optionnel)
Mêmes exigences.

---

## 4. Textes

### Titre de l'app
**WhiteSilence** (30 caractères max — tu en as 12, large)

### Description courte (80 caractères)
**WhiteSilence — Ski de rando offline, sans compte, sans tracking, open source.**

→ 75 caractères. Reformulations possibles si trop "sec" :
- *"Ski de rando offline. Sans compte, sans tracking. Pour le terrain."* (66)
- *"L'app de ski de rando libre. Conditions, BERA, isochrones, observations."* (75)
- *"Ski de rando : conditions, BERA, isochrones, obs. Sans compte. Open source."* (80)

### Description longue (4000 caractères max)
Voir fichier `play_store_description.md` séparé.

### Mots-clés Play Store (apparaissent dans le titre + description)
- skitouring
- ski de rando
- ski de randonnée
- BERA
- avalanche
- isochrones
- topo ski
- alpes
- neige
- météo montagne
- open source
- offline

→ À distribuer naturellement dans la description longue. Pas de spam de mots-clés (Google pénalise).

---

## 5. Configuration de la fiche Play Console

### Catégorisation
- **Catégorie principale** : Sports
- **Tags** : Outdoor, Maps & navigation, Weather

### Classification du contenu (Content Rating)
WhiteSilence n'a pas de contenu problématique. Le questionnaire IARC retournera **Tous publics (PEGI 3)**.

### Public cible (Target audience)
- **Tranches d'âge** : 18 ans et +
- **Pourquoi** : montagne hivernale = activité à risques, ce n'est pas une app pour mineurs sans accompagnement.

### Coordonnées du développeur
- **Email contact** : à toi de me dire (probablement tinevagio@... ou perso)
- **Site web** : laisser vide (page web pas encore faite) ou pointer sur le repo GitHub
- **Adresse postale** : Google demande une adresse publique. Tu peux utiliser celle d'un service de domiciliation, ta boîte postale, ou ton adresse perso (visible sur la fiche Play Store).

### Pays de distribution
- France
- (Optionnel) Tous les pays francophones : Belgique, Suisse, Luxembourg, Canada, Maroc...
- (Optionnel) Tous les pays alpins : France, Italie, Suisse, Autriche, Allemagne, Slovénie

→ Suggestion : commencer **France uniquement**, élargir plus tard quand l'app aura des localisations EN/IT/DE.

---

## 6. Confidentialité

### URL de la politique de confidentialité (obligatoire)
`https://tinevagio.github.io/whitesilence/privacy.html`

→ À activer via GitHub Pages avant la soumission.

### Section "Sécurité des données" (Data Safety)

Réponses à donner dans le formulaire Play Console :

**Cette application collecte-t-elle des données utilisateur ?**
→ **OUI** (techniquement, le micro et le GPS sont des "données")

**Cette application chiffre-t-elle les données en transit ?**
→ **OUI** (HTTPS pour tous les backends)

**Les utilisateurs peuvent-ils demander la suppression de leurs données ?**
→ **OUI** (en désinstallant l'app — tout est local)

**Types de données collectées** :
- ✓ **Localisation approximative** : utilisée pour fonctionnalité de l'app (isochrones, carte), **non partagée**, **non requise**
- ✓ **Localisation précise** : utilisée pour fonctionnalité de l'app, **non partagée**, **non requise**
- ✓ **Audio** : enregistrements vocaux uniquement quand l'utilisateur déclenche, transcrits, **non partagés sauf action explicite**, **non requis**
- ✓ **Fichiers et docs** : tuiles topo téléchargées localement pour usage offline, **non partagées**, **non requises**

**Ce que l'app NE collecte PAS** : nom, email, téléphone, contacts, identifiant utilisateur, historique de navigation, achats, identifiants publicitaires.

---

## 7. Conformité Android

### Niveau d'API cible
Vérifier dans `android/app/build.gradle` :
- `targetSdk` doit être **API 34** minimum (Android 14, exigence Google août 2024).
- `minSdk` peut rester à 24 (Android 7).

### Format de publication
- **AAB (Android App Bundle)** obligatoire depuis 2021.
- Pas d'APK direct (l'APK sera dérivé par Google selon l'appareil).

### Permissions déclarées
Doivent correspondre à ce que l'app demande réellement :
- `ACCESS_FINE_LOCATION` — GPS précis (isochrones, carte)
- `ACCESS_COARSE_LOCATION` — fallback réseau
- `RECORD_AUDIO` — observations vocales
- `INTERNET` — backend, tuiles cartes
- `ACCESS_NETWORK_STATE` — détecter offline
- (optionnel) `FOREGROUND_SERVICE` si wake word arrière-plan plus tard

---

## 8. Tracking de la progression de soumission

Étapes Play Console à valider (toutes obligatoires) :
- [ ] Détails de l'application (titre, description courte, longue)
- [ ] Catégorisation
- [ ] Coordonnées du contact (email + site web)
- [ ] Confidentialité (URL externe)
- [ ] Public cible et contenu
- [ ] Publicités → **Non**
- [ ] Contenu de l'application (Data Safety)
- [ ] Conformité du gouvernement américain (USA Export) — choisir **Non, l'app ne contient pas de chiffrement non standard**
- [ ] Classification du contenu (questionnaire IARC)
- [ ] Pays disponibles
- [ ] Format de publication (AAB)
- [ ] Configuration des tests (recommandé : test interne d'abord, puis test fermé avec 5-10 amis)

---

## 9. Première publication — pas de panique

Première soumission Play Store = quelques jours d'attente (1-7 jours en moyenne pour la review humaine). Si refus, Google précise exactement quoi corriger.

**Risque principal sur cette app** : la mention de **micro + position GPS** pourrait déclencher une review approfondie. La politique de confidentialité claire et l'absence totale de tracking jouent en notre faveur.

**Suggestion** : faire un **test interne** (test track Play Console) avec 2-3 amis avant de pousser en prod. Ça permet de valider toute la chaîne (signing, install, fonctionnement) sans risque.
