# WhiteSilence

> La seule trace, c'est celle dans la neige.

WhiteSilence est une application Android de ski de randonnée pensée pour le terrain : sans inscription, sans tracking, sans publicité, offline-first, open source.

## Ce qu'elle fait

- **Temps (TimeToGo)** : calcule des isochrones depuis ta position ou un point posé sur la carte. Modèle Munter calibré sur ton allure réelle, avec mise à jour continue pendant la marche.
- **Neige (Hey Snowy)** : enregistre des observations vocales déclenchables au mot-clé, transcrites et stockées localement. Partage anonyme optionnel.
- **Conditions** : grille horaire météo, BERA Météo France, heatmap d'enneigement, cônes d'avalanche par zone de départ, fenêtres optimales poudre / moquette.
- **Idées** : suggestions de sorties basées sur la météo des derniers jours, le BERA actuel, ton niveau et tes filtres (massif, expo, dénivelé). Scoring IA optionnel.
- **Obs** : carte des observations partagées par la communauté.

Mode gants permanent, fonctionne hors-ligne avec tuiles topo téléchargées par zone.

## Pour qui

Des skieurs de rando qui veulent un outil :
- qui respecte leur vie privée (pas de compte, pas de tracking)
- qui ne les transforme pas en "performeurs" (pas de leaderboard, pas de comparaison sociale)
- qui marche en montagne quand le réseau ne marche pas
- dont ils peuvent vérifier le fonctionnement en lisant le code

## Installation

À venir sur le Play Store (en attente de validation).

En attendant, build manuel :

```bash
flutter pub get
flutter run --release
```

Pré-requis : Flutter 3.x, Android SDK, un téléphone Android 7+ ou un émulateur.

## Architecture

Mono-app Flutter, carte unique partagée, modules pluggables qui contribuent des layers carte et un panneau d'action. Chaque module est indépendant et peut être désactivé via Réglages.

Backends Python FastAPI :
- [snow-conditions](https://snow-conditions.onrender.com) — conditions horaires + BERA + cônes avalanche
- [ski-touring-api](https://ski-touring-api.onrender.com) — scoring d'itinéraires (module Idées)

Les backends ne reçoivent que des coordonnées géographiques (bbox ou point) — aucun identifiant utilisateur.

## Sources de données

- **Cartographie** : OpenStreetMap, OpenTopoMap
- **BERA** : Météo France
- **Météo horaire** : Open-Meteo
- **Topo-guides** : Camptocamp.org, Skitour
- **Altimétrie** : SRTM (NASA)

Toutes les attributions complètes sont dans l'app (Réglages → Crédits & sources) et respectent les licences ODbL, CC-BY-SA, CC-BY.

## Confidentialité

[Politique de confidentialité complète](https://tinevagio.github.io/whitesilence/privacy.html).

En une phrase : WhiteSilence ne collecte aucune donnée personnelle. Tout reste sur le téléphone.

## Contribuer

Le code est open source sous licence MIT. Issues et PRs bienvenues :

- 🐛 [Reporter un bug](https://github.com/Tinevagio/whitesilence/issues/new?labels=bug)
- 💡 [Proposer une fonctionnalité](https://github.com/Tinevagio/whitesilence/issues/new?labels=feature)
- 📖 Améliorer la doc, la traduction (EN à venir)

## Soutenir le projet

WhiteSilence est gratuit et le restera. Si tu veux soutenir le développement :

- ☕ [Ko-fi](https://ko-fi.com/Tinevagio) — café offert, ponctuel ou récurrent
- ❤️ [GitHub Sponsors](https://github.com/sponsors/Tinevagio) — mensuel

## Licence

[MIT](LICENSE) © 2026 Tinevagio
