# Tests WhiteSilence

## Structure

```
test/
├── helpers/
│   ├── fake_dem.dart          # FlatDem, SlopedDem, FailingDem, StepDem
│   └── fake_gps.dart          # fakePos(), buildTrace(), buildUniformTrace()
├── munter_test.dart           # MunterEngine — logique pure
├── isochrone_test.dart        # IsochroneEngine — avec faux DEM
├── ideas_model_test.dart      # Idea.fromJson — parsing JSON
└── calibration/
    └── calibrator_lifecycle_test.dart  # GpsCalibrator — cycle de vie
```

## Commandes

```bash
# Un fichier
flutter test test/munter_test.dart --reporter expanded

# Tous les tests
flutter test --reporter expanded

# Un test spécifique (match sur le nom)
flutter test test/munter_test.dart --name "isCalibrated atteint"

# Dossier calibration uniquement
flutter test test/calibration/
```

## Scénarios couverts

### munter_test.dart
- `estimateSeconds` : plat, montée, descente, terrainFactor ×1.30 / ×1.45
- Calibration : seuils de rejet (trop court), isCalibrated à 10 segments,
  poids plafonné à 0.95, blend vers marcheur lent/rapide, fenêtre glissante,
  calibration D+ (segments de 12 min minimum)
- Snapshot : round-trip, mauvais profil, reprise après restore

### calibrator_lifecycle_test.dart
- Scénario 1 — sortie normale : segments acceptés, vitesse dans les bornes
- Scénario 2 — pause : clôture propre + reprise
- Scénario 3 — arrière-plan Android (coalescing) : positions en rafale
  avec vrais timestamps → durées reconstituées correctement
- Scénario 4 — kill & relaunch : snapshot conserve poids + acceptedCount
- Scénario 5 — mauvaise précision GPS (> 30m) : filtrage, reprise après
- Scénario 6 — fix aberrant (téléportation) : pas de corruption du D+
- Scénario 7 — DEM indisponible : fallback altitude GPS
- Scénario 8 — reset : remise à zéro propre

### isochrone_test.dart
- Terrain plat : rayCount points, isotropie < 5%, rayon ≈ 2250 m
- Multi-budgets : 15/30/45/60 min tous présents
- Terrain en pente : contraction asymétrique (nord < sud)
- tortuosityFactor : 0.8 contracte de ~20%
- Profil Munter : warrior > beginner, heavySnow < normal
- Lissage Chaikin : doublement des points, bounding box respectée

### ideas_model_test.dart
- Idea.fromJson : score, coordonnées, latLng, url/source null
- Champs AI optionnels : null sans AI, parsing complet avec AI
- MeteoSummary : valeurs, fallback icon ⛅
- BeraSummary : risque null toléré
- FeaturesDetail : null si absent, parsing complet
- Cohérence : score ∈ [0,1], aiNote10 ∈ [0,10], BERA ∈ [1,5]

## Note sur la calibration D+

La calibration du D+ dans `MunterEngine._recalibrate()` exige que
`ascentRate calculé = dist × 3600 / durationS ≤ 1500 m/h`.

Pour `dist=300m` : `durationS ≥ 720s` (12 min minimum par segment).

Conséquence pratique : en conditions réelles le `GpsCalibrator` émet des
segments de 60-120s, ce qui rend la calibration du D+ pratiquement
inatteignable avec de courts segments. La calibration de la vitesse
horizontale (segments plats, elevGain=0) reste le cas dominant.
