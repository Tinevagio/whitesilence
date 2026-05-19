// lib/modules/time/time_overlay.dart
//
// Overlay du module Temps sur la WSMapScreen.
//
// - Layers : contours isochrones + remplissage + marqueur cible
// - Tap carte : déclenche estimateToPoint() du contrôleur
// - Action panel : carte flottante avec le résultat + bouton "Isochrones"

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/map/map_module_overlay.dart';
import '../../core/module_navigator.dart';
import '../../core/module_registry.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import 'time_controller.dart';
import 'widgets/hgt_coverage_layer.dart';

// Palette des isochrones — cohérente avec la palette WhiteSilence.
// Du plus proche (15 min) au plus loin (60 min).
const _isoColors = [
  WSColors.powderGreen,     // 15 min
  WSColors.glacierBlue,     // 30 min
  WSColors.sunOrange,       // 45 min
  WSColors.avalancheRed,    // 60 min
];
const _isoStrokeWidths = [3.0, 2.4, 2.0, 1.6];

class TimeModuleOverlay extends MapModuleOverlay {
  final TimeController controller = TimeController();

  TimeModuleOverlay() {
    // Répercute les notifs du controller pour que le shell rebuild quand
    // showHgtCoverage change (le layer apparaît/disparaît).
    controller.addListener(notifyListeners);
  }

  @override
  ModuleId get id => ModuleId.time;

  @override
  List<Widget> buildMapLayers(BuildContext context) {
    // Si une autre partie de l'app a demandé qu'on calcule un temps vers
    // un point précis (typiquement Idées via ModuleNavigator), on consomme
    // l'intention ici. C'est appelé à chaque rebuild de la WSMapScreen,
    // donc dès que ce module devient actif.
    final pending = ModuleNavigator().pendingTimeTarget;
    if (pending != null) {
      // Fire-and-forget : déclenche le calcul en background, l'UI se mettra
      // à jour via notifyListeners du controller.
      controller.estimateToPoint(pending);
    }

    // On rend les couches comme listenables individuels parce que FlutterMap
    // attend des Layer widgets directement dans `children`, pas un widget
    // englobant. Chaque _IsoPolygons / _IsoLines / _TargetMarkerLayer écoute
    // le controller et rebuild quand les contours changent.
    return [
      _IsoPolygons(controller: controller),
      _IsoLines(controller: controller),
      _TargetMarkerLayer(controller: controller),
      _PinnedOriginLayer(controller: controller),
      if (controller.showHgtCoverage) const HgtCoverageLayer(),
    ];
  }

  @override
  bool onMapTap(BuildContext context, TapPosition tapPosition, LatLng latLng) {
    controller.estimateToPoint(latLng);
    return true; // tap consommé
  }

  @override
  bool onMapLongPress(BuildContext context, TapPosition tapPosition, LatLng latLng) {
    controller.setPinnedOrigin(latLng);
    return true;
  }

  @override
  Widget? buildActionPanel(BuildContext context) {
    return _TimeActionPanel(controller: controller);
  }
}

// ─── Layers ──────────────────────────────────────────────────────────────────

/// Polygones de remplissage (calques semi-transparents par budget).
class _IsoPolygons extends StatelessWidget {
  final TimeController controller;
  const _IsoPolygons({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final contours = controller.contours;
        if (contours.isEmpty) return const SizedBox.shrink();

        final budgets = contours.keys.toList()..sort();
        final polygons = <Polygon>[];
        // Du plus grand au plus petit pour l'effet de remplissage en oignon
        for (int i = budgets.length - 1; i >= 0; i--) {
          final pts = contours[budgets[i]]!;
          if (pts.isEmpty) continue;
          final color = _isoColors[i % _isoColors.length];
          polygons.add(Polygon(
            points: pts,
            color: color.withOpacity(0.10),
            borderColor: Colors.transparent,
            borderStrokeWidth: 0,
          ));
        }
        return PolygonLayer(polygons: polygons);
      },
    );
  }
}

/// Contours (lignes par budget).
class _IsoLines extends StatelessWidget {
  final TimeController controller;
  const _IsoLines({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final contours = controller.contours;
        if (contours.isEmpty) return const SizedBox.shrink();

        final budgets = contours.keys.toList()..sort();
        final polylines = <Polyline>[];
        for (int i = budgets.length - 1; i >= 0; i--) {
          final pts = contours[budgets[i]]!;
          if (pts.isEmpty) continue;
          final color = _isoColors[i % _isoColors.length];
          final stroke = _isoStrokeWidths[i % _isoStrokeWidths.length];
          polylines.add(Polyline(
            points: [...pts, pts.first],
            color: color.withOpacity(0.85),
            strokeWidth: stroke,
          ));
        }
        return PolylineLayer(polylines: polylines);
      },
    );
  }
}

/// Marqueur du point cible (drapeau).
class _TargetMarkerLayer extends StatelessWidget {
  final TimeController controller;
  const _TargetMarkerLayer({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final target = controller.targetPoint;
        if (target == null) return const SizedBox.shrink();
        return MarkerLayer(markers: [
          Marker(
            point: target,
            width: 30,
            height: 30,
            child: const _TargetMarker(),
          ),
        ]);
      },
    );
  }
}

/// Marqueur du point d'origine épinglé (long-press).
/// Visuellement distinct du marqueur cible : grand point bleu cerclé,
/// comme la position GPS mais en plus marqué pour signifier "depuis ici".
class _PinnedOriginLayer extends StatelessWidget {
  final TimeController controller;
  const _PinnedOriginLayer({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final pin = controller.pinnedOrigin;
        if (pin == null) return const SizedBox.shrink();
        return MarkerLayer(markers: [
          Marker(
            point: pin,
            width: 40,
            height: 40,
            child: const _PinnedOriginMarker(),
          ),
        ]);
      },
    );
  }
}

class _PinnedOriginMarker extends StatelessWidget {
  const _PinnedOriginMarker();
  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Halo extérieur
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: WSColors.glacierBlue.withOpacity(0.18),
            shape: BoxShape.circle,
          ),
        ),
        // Couronne fixe
        Container(
          width: 22, height: 22,
          decoration: BoxDecoration(
            color: WSColors.snowWhite,
            shape: BoxShape.circle,
            border: Border.all(color: WSColors.glacierBlue, width: 2),
          ),
        ),
        // Petite icône punaise
        const Icon(Icons.push_pin, size: 12, color: WSColors.glacierBlue),
      ],
    );
  }
}

class _TargetMarker extends StatelessWidget {
  const _TargetMarker();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: WSColors.snowWhite,
        shape: BoxShape.circle,
        border: Border.all(color: WSColors.slateDark, width: 1.5),
        boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
      ),
      child: const Icon(Icons.flag_outlined, size: 16, color: WSColors.slateDark),
    );
  }
}

// ─── Action panel ────────────────────────────────────────────────────────────

class _TimeActionPanel extends StatelessWidget {
  final TimeController controller;
  const _TimeActionPanel({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.fromLTRB(
            WSSpacing.lg, WSSpacing.md, WSSpacing.md, WSSpacing.md),
          decoration: BoxDecoration(
            color: WSColors.snowWhite.withOpacity(0.96),
            borderRadius: BorderRadius.circular(WSRadius.lg),
            border: Border.all(color: WSColors.glacierMid, width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (controller.pinnedOrigin != null) ...[
                _PinnedOriginBanner(controller: controller),
                const SizedBox(height: WSSpacing.sm),
              ],
              if (controller.pointEstimate != null) ...[
                _EstimateRow(controller: controller),
                const SizedBox(height: WSSpacing.sm),
              ] else
                Padding(
                  padding: const EdgeInsets.only(bottom: WSSpacing.sm),
                  child: Text(
                    controller.pinnedOrigin == null
                        ? 'Tape sur la carte pour estimer un temps · long-press pour poser une origine'
                        : 'Tape sur la carte pour estimer depuis l\'épingle',
                    style: WSText.caption,
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: controller.computing
                        ? const _ComputingIndicator()
                        : FilledButton.icon(
                            onPressed: () => controller.computeIsochrones(),
                            icon: const Icon(Icons.scatter_plot_outlined, size: 18),
                            label: Text(controller.contours.isEmpty
                                ? 'Calculer les isochrones'
                                : 'Recalculer'),
                          ),
                  ),
                  const SizedBox(width: WSSpacing.sm),
                  // Toggle couverture HGT — bordure plus marquée quand actif
                  IconButton.outlined(
                    icon: Icon(
                      controller.showHgtCoverage
                          ? Icons.grid_on
                          : Icons.grid_off,
                      size: 18,
                      color: controller.showHgtCoverage
                          ? WSColors.glacierBlue
                          : null,
                    ),
                    onPressed: controller.toggleHgtCoverage,
                    tooltip: controller.showHgtCoverage
                        ? 'Masquer la couverture HGT'
                        : 'Afficher la couverture HGT (1°×1°)',
                  ),
                  if (controller.contours.isNotEmpty) ...[
                    const SizedBox(width: WSSpacing.sm),
                    IconButton.outlined(
                      icon: const Icon(Icons.layers_clear_outlined, size: 18),
                      onPressed: controller.clearIsochrones,
                      tooltip: 'Effacer les isochrones',
                    ),
                  ],
                ],
              ),
              // Bandeau Calibration — tappable, ouvre une bottom sheet riche
              Padding(
                padding: const EdgeInsets.only(top: WSSpacing.sm),
                child: InkWell(
                  borderRadius: BorderRadius.circular(WSRadius.sm),
                  onTap: () => _openCalibrationSheet(context, controller),
                  child: _CalibrationSummary(controller: controller),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Bandeau "Origine épinglée" + bouton pour retirer le pin.
class _PinnedOriginBanner extends StatelessWidget {
  final TimeController controller;
  const _PinnedOriginBanner({required this.controller});

  @override
  Widget build(BuildContext context) {
    final pin = controller.pinnedOrigin;
    if (pin == null) return const SizedBox.shrink();

    final coords = '${pin.latitude.toStringAsFixed(4)}, '
                   '${pin.longitude.toStringAsFixed(4)}';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WSSpacing.md,
        vertical: WSSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: WSColors.glacierBlueBg,
        borderRadius: BorderRadius.circular(WSRadius.md),
      ),
      child: Row(
        children: [
          const Icon(Icons.push_pin, size: 14, color: WSColors.glacierBlue),
          const SizedBox(width: WSSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Origine épinglée',
                  style: WSText.caption.copyWith(
                    color: WSColors.glacierBlue,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(coords, style: WSText.micro),
              ],
            ),
          ),
          InkWell(
            onTap: controller.clearPinnedOrigin,
            borderRadius: BorderRadius.circular(WSRadius.sm),
            child: const Padding(
              padding: EdgeInsets.all(WSSpacing.xs),
              child: Icon(Icons.close, size: 16, color: WSColors.glacierBlue),
            ),
          ),
        ],
      ),
    );
  }
}

class _EstimateRow extends StatelessWidget {
  final TimeController controller;
  const _EstimateRow({required this.controller});

  @override
  Widget build(BuildContext context) {
    final estimate = controller.pointEstimate;
    if (estimate == null) return const SizedBox.shrink();

    return Row(
      children: [
        Expanded(
          child: Text(estimate, style: WSText.heading),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 18, color: WSColors.stoneGray),
          onPressed: controller.clearTarget,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ],
    );
  }
}

/// Ligne de récap calibration affichée sous les boutons (toujours visible).
/// Tappable → ouvre la bottom sheet détaillée.
class _CalibrationSummary extends StatelessWidget {
  final TimeController controller;
  const _CalibrationSummary({required this.controller});

  @override
  Widget build(BuildContext context) {
    final report = controller.calibratorReport;
    final isCalibrated = controller.isCalibrated;
    final weight = report['poids'] ?? '0%';
    final hSpeed = report['hSpeed'] ?? '?';
    final aRate  = report['ascentRate'] ?? '?';
    final segments = report['segments'] ?? '';

    // En phase "pas encore calibré", on montre les segments accumulés pour
    // que l'utilisateur voie que ça progresse.
    final mainText = isCalibrated
        ? '$hSpeed km/h · $aRate m/h'
        : segments.isNotEmpty && segments != '0 acceptés, 0 rejetés'
            ? segments
            : 'Calibration en attente (marche pour démarrer)';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WSSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: WSColors.glacierLight,
        borderRadius: BorderRadius.circular(WSRadius.sm),
      ),
      child: Row(
        children: [
          Icon(
            isCalibrated ? Icons.tune : Icons.tune_outlined,
            size: 14,
            color: isCalibrated ? WSColors.powderGreen : WSColors.stoneGray,
          ),
          const SizedBox(width: WSSpacing.sm),
          Expanded(
            child: Text(
              mainText,
              style: WSText.micro.copyWith(color: WSColors.slateDark),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: isCalibrated
                  ? WSColors.powderGreen.withOpacity(0.18)
                  : WSColors.glacierMid.withOpacity(0.25),
              borderRadius: BorderRadius.circular(WSRadius.pill),
            ),
            child: Text(
              isCalibrated ? '✓ $weight' : 'baseline',
              style: WSText.micro.copyWith(
                color: isCalibrated ? WSColors.powderGreen : WSColors.stoneGray,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 14, color: WSColors.stoneGray),
        ],
      ),
    );
  }
}

void _openCalibrationSheet(BuildContext context, TimeController controller) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _CalibrationSheet(controller: controller),
    ),
  );
}

/// Bottom sheet détaillée : tous les paramètres Munter + segments + DEM.
class _CalibrationSheet extends StatelessWidget {
  final TimeController controller;
  const _CalibrationSheet({required this.controller});

  @override
  Widget build(BuildContext context) {
    final report = controller.calibratorReport;
    final isCalibrated = controller.isCalibrated;

    return Container(
      decoration: const BoxDecoration(
        color: WSColors.snowWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(WSRadius.xl)),
      ),
      padding: const EdgeInsets.fromLTRB(
        WSSpacing.xl, WSSpacing.lg, WSSpacing.xl, WSSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: WSSpacing.lg),
              decoration: BoxDecoration(
                color: WSColors.glacierMid,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Row(
            children: [
              const Icon(Icons.speed, size: 18, color: WSColors.slateDark),
              const SizedBox(width: WSSpacing.sm),
              const Text('Paramètres Munter', style: WSText.title),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: WSSpacing.md, vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isCalibrated
                      ? WSColors.powderGreen.withOpacity(0.18)
                      : WSColors.glacierMid.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(WSRadius.pill),
                ),
                child: Text(
                  isCalibrated
                      ? '✓ Calibré ${report['poids']}'
                      : (report['calibré'] ?? 'Baseline'),
                  style: WSText.caption.copyWith(
                    color: isCalibrated
                        ? WSColors.powderGreen
                        : WSColors.stoneGray,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: WSSpacing.lg),

          // Stats principales
          _StatRow(label: 'Vitesse horizontale',
                   value: '${report['hSpeed'] ?? "?"} km/h'),
          _StatRow(label: 'Dénivelé positif',
                   value: '${report['ascentRate'] ?? "?"} m/h'),
          _StatRow(label: 'Dénivelé négatif',
                   value: '${report['descentRate'] ?? "?"} m/h'),

          const SizedBox(height: WSSpacing.md),

          // Segments
          if (report['segments'] != null)
            Container(
              padding: const EdgeInsets.all(WSSpacing.md),
              decoration: BoxDecoration(
                color: WSColors.glacierLight,
                borderRadius: BorderRadius.circular(WSRadius.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Segments GPS', style: WSText.micro.copyWith(
                      color: WSColors.stoneGray)),
                  const SizedBox(height: 4),
                  Text(report['segments']!, style: WSText.body),
                ],
              ),
            ),

          // Source DEM
          const SizedBox(height: WSSpacing.md),
          Row(
            children: [
              const Icon(Icons.terrain, size: 14, color: WSColors.stoneGray),
              const SizedBox(width: 6),
              Text('Source d\'altitude : ${controller.demSourceLabel}',
                  style: WSText.caption),
            ],
          ),

          // Explication
          const SizedBox(height: WSSpacing.md),
          Container(
            padding: const EdgeInsets.all(WSSpacing.md),
            decoration: BoxDecoration(
              color: WSColors.glacierBlueBg,
              borderRadius: BorderRadius.circular(WSRadius.md),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline,
                    size: 14, color: WSColors.glacierBlue),
                const SizedBox(width: WSSpacing.sm),
                Expanded(
                  child: Text(
                    isCalibrated
                        ? 'Tes paramètres sont calibrés sur tes propres mesures GPS. '
                          'Plus tu marches, plus le poids monte (max 80%).'
                        : 'Marche au moins 3 segments de 50m / 1 min pour démarrer '
                          'la calibration. Les estimations utilisent pour l\'instant '
                          'les valeurs Munter standards.',
                    style: WSText.caption.copyWith(
                      color: WSColors.glacierBlue,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: WSText.body)),
          Text(value, style: WSText.body.copyWith(
              fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ComputingIndicator extends StatelessWidget {
  const _ComputingIndicator();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: WSColors.glacierBlueBg,
        borderRadius: BorderRadius.circular(WSRadius.md),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(WSColors.glacierBlue)),
          ),
          SizedBox(width: WSSpacing.sm),
          Text('Calcul des isochrones…',
              style: TextStyle(fontSize: 12, color: WSColors.glacierBlue)),
        ],
      ),
    );
  }
}
