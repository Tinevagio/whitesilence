# Nettoyage avant install du patch Phase 3 WebView
#
# La version Flutter native du module Conditions est remplacée par une
# version WebView beaucoup plus légère. Il faut donc supprimer les anciens
# fichiers avant d'extraire le nouveau tar.gz, sinon les imports cassent.
#
# À exécuter dans PowerShell, depuis la racine de C:\flutter\whitesilence.

cd C:\flutter\whitesilence

# Supprime les fichiers Flutter natifs de la Phase 3 originale
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue lib\modules\conditions\models
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue lib\modules\conditions\services
Remove-Item -Force -ErrorAction SilentlyContinue lib\modules\conditions\conditions_controller.dart
Remove-Item -Force -ErrorAction SilentlyContinue lib\modules\conditions\condition_detail_sheet.dart

# (conditions_overlay.dart sera remplacé par le tar, pas besoin de le supprimer)

Write-Host "Nettoyage OK. Extraire maintenant le tar.gz par-dessus :"
Write-Host "  tar -xzf chemin\vers\whitesilence_phase3_webview.tar.gz"
