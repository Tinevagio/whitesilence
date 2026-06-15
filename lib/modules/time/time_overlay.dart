// lib/modules/time/time_overlay.dart
//
// Overlay du module Temps & Itinéraire (fusion des anciens modules Temps et
// Itinéraire).
//
// - Tap court  : pose départ puis arrivée → calcul d'itinéraire offline
// - Long-press : épingle une origine custom pour les isochrones
// - Layers     : contours isochrones + tracé de l'itinéraire
// - Panel      : contextuel — stats itinéraire si tracé actif, sinon isochrones

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/map/map_module_overlay.dart';
import '../../core/module_navigator.dart';
import '../../core/module_registry.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../route/route_controller.dart';
import 'time_controller.dart';
import 'widgets/hgt_coverage_layer.dart';

// Palette des isochrones.
const _isoColors = [
  WSColors.powderGreen,
  WSColors.glacierBlue,
  WSColors.sunOrange,
  WSColors.avalancheRed,
];
const _isoStrokeWidths = [3.0, 2.4, 2.0, 1.6];

class TimeModuleOverlay extends MapModuleOverlay {
  final TimeController controller = TimeController();
  final RouteController _route = RouteController();

  // DragHandler exposé en mode freehand → la WSMapScreen désactive le pan/zoom
  // et relaie les gestes convertis en LatLng.
  late final _FreehandDragHandler _dragHandler =
      _FreehandDragHandler(_route);

  TimeModuleOverlay() {
    controller.addListener(notifyListeners);
    _route.addListener(notifyListeners);
  }

  @override
  void dispose() {
    controller.removeListener(notifyListeners);
    _route.removeListener(notifyListeners);
    super.dispose();
  }

  @override
  ModuleId get id => ModuleId.time;

  /// Expose le dragHandler uniquement en mode freehand.
  /// La WSMapScreen détecte sa présence et gèle le pan/zoom automatiquement.
  @override
  MapDragHandler? get dragHandler =>
      _route.mode == RouteMode.freehand ? _dragHandler : null;

  // ── Layers carte ───────────────────────────────────────────────────────────

  @override
  List<Widget> buildMapLayers(BuildContext context) {
    final pending = ModuleNavigator().pendingTimeTarget;
    if (pending != null) {
      controller.estimateToPoint(pending);
    }

    return [
      // ── Isochrones ────────────────────────────────────────────────────────
      _IsoPolygons(controller: controller),
      _IsoLines(controller: controller),
      _TargetMarkerLayer(controller: controller),
      _PinnedOriginLayer(controller: controller),
      if (controller.showHgtCoverage) const HgtCoverageLayer(),

      // ── Tracé itinéraire / main levée ─────────────────────────────────────
      _RouteTraceLayer(route: _route),
      _RouteMarkersLayer(route: _route),
    ];
  }

  // ── Interactions ───────────────────────────────────────────────────────────

  @override
  bool onMapTap(BuildContext context, TapPosition tapPosition, LatLng latLng) {
    // En mode freehand, les taps sont ignorés (le dessin se fait via pan).
    if (_route.mode == RouteMode.freehand) return false;
    _route.onTap(latLng);
    return true;
  }

  @override
  bool onMapLongPress(
      BuildContext context, TapPosition tapPosition, LatLng latLng) {
    // Long-press → épingle l'origine des isochrones (comportement inchangé).
    controller.setPinnedOrigin(latLng);
    return true;
  }

  // ── Panneau d'action ───────────────────────────────────────────────────────

  @override
  Widget? buildActionPanel(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, _route]),
      builder: (context, _) {
        // Routage actif → panneau itinéraire en priorité.
        switch (_route.phase) {
          case RoutePhase.awaitingEnd:
            return _RouteHintPanel(
              hint: 'Touche le point d\'arrivée',
              onCancel: _route.reset,
            );
          case RoutePhase.computing:
            return const _RouteHintPanel(
              hint: 'Calcul de l\'itinéraire…',
              spinner: true,
            );
          case RoutePhase.ready:
            return _RouteStatsPanel(route: _route);
          case RoutePhase.error:
            return _RouteErrorPanel(route: _route);
          case RoutePhase.idle:
            break;
        }
        // Aucun itinéraire actif → panneau Temps.
        return _TimeActionPanel(controller: controller, route: _route);
      },
    );
  }
}

// ─── Layers isochrones (inchangés) ───────────────────────────────────────────

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
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: WSColors.glacierBlue.withOpacity(0.18),
            shape: BoxShape.circle,
          ),
        ),
        Container(
          width: 22, height: 22,
          decoration: BoxDecoration(
            color: WSColors.snowWhite,
            shape: BoxShape.circle,
            border: Border.all(color: WSColors.glacierBlue, width: 2),
          ),
        ),
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

// ─── Layers itinéraire ────────────────────────────────────────────────────────

class _RouteTraceLayer extends StatelessWidget {
  final RouteController route;
  const _RouteTraceLayer({required this.route});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: route,
      builder: (context, _) {
        if (route.tracePoints.length < 2) return const SizedBox.shrink();
        return PolylineLayer(polylines: [
          Polyline(
            points: route.tracePoints,
            strokeWidth: 5,
            color: WSColors.glacierBlue.withOpacity(0.9),
            borderStrokeWidth: 1.5,
            borderColor: Colors.white.withOpacity(0.8),
          ),
        ]);
      },
    );
  }
}

class _RouteMarkersLayer extends StatelessWidget {
  final RouteController route;
  const _RouteMarkersLayer({required this.route});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: route,
      builder: (context, _) {
        final markers = <Marker>[];
        if (route.start != null) {
          markers.add(_routePin(route.start!, Icons.trip_origin, WSColors.glacierBlue));
        }
        if (route.end != null) {
          markers.add(_routePin(route.end!, Icons.place, Colors.redAccent));
        }
        if (markers.isEmpty) return const SizedBox.shrink();
        return MarkerLayer(markers: markers);
      },
    );
  }

  Marker _routePin(LatLng p, IconData icon, Color color) => Marker(
        point: p,
        width: 36,
        height: 36,
        alignment: Alignment.topCenter,
        child: Icon(icon, color: color, size: 32),
      );
}

// ─── Panneaux itinéraire ──────────────────────────────────────────────────────

class _RouteHintPanel extends StatelessWidget {
  final String hint;
  final bool spinner;
  final VoidCallback? onCancel;
  const _RouteHintPanel({
    required this.hint,
    this.spinner = false,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return _PanelShell(
      child: Row(
        children: [
          if (spinner) ...[
            const SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: WSSpacing.sm),
          ],
          Expanded(child: Text(hint, style: WSText.body)),
          if (onCancel != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: onCancel,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }
}

class _RouteStatsPanel extends StatelessWidget {
  final RouteController route;
  const _RouteStatsPanel({required this.route});

  @override
  Widget build(BuildContext context) {
    final s = route.stats!;
    return _PanelShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _stat(Icons.straighten, s.distanceLabel),
              _stat(Icons.trending_up, '+${s.elevGainM.round()} m'),
              _stat(Icons.trending_down, '-${s.elevLossM.round()} m'),
              _stat(Icons.schedule, s.durationLabel),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: route.reset,
                padding: EdgeInsets.zero,
                tooltip: 'Nouvel itinéraire',
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          if (route.message != null) ...[
            const SizedBox(height: WSSpacing.xs),
            Text(
              route.message!,
              style: WSText.micro.copyWith(color: WSColors.stoneGray),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String value) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: WSColors.glacierBlue),
          const SizedBox(height: 2),
          Text(value,
              style: WSText.caption
                  .copyWith(fontWeight: FontWeight.w600)),
        ],
      );
}

class _RouteErrorPanel extends StatelessWidget {
  final RouteController route;
  const _RouteErrorPanel({required this.route});

  @override
  Widget build(BuildContext context) {
    return _PanelShell(
      child: Row(
        children: [
          const Icon(Icons.error_outline,
              size: 18, color: WSColors.avalancheRed),
          const SizedBox(width: WSSpacing.sm),
          Expanded(
            child: Text(
              route.message ?? 'Erreur de calcul',
              style: WSText.caption
                  .copyWith(color: WSColors.avalancheRed),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: route.reset,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

class _PanelShell extends StatelessWidget {
  final Widget child;
  const _PanelShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
          WSSpacing.lg, WSSpacing.md, WSSpacing.md, WSSpacing.md),
      decoration: BoxDecoration(
        color: WSColors.snowWhite.withOpacity(0.96),
        borderRadius: BorderRadius.circular(WSRadius.lg),
        border: Border.all(color: WSColors.glacierMid, width: 0.5),
      ),
      child: child,
    );
  }
}

// ─── Panneau Temps + toggle mode ─────────────────────────────────────────────

class _TimeActionPanel extends StatelessWidget {
  final TimeController controller;
  final RouteController route;
  const _TimeActionPanel({
    required this.controller,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, route]),
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
              // ── Toggle Auto / Main levée ───────────────────────────────────
              _RouteModeToggle(route: route),
              const SizedBox(height: WSSpacing.sm),

              if (controller.pinnedOrigin != null) ...[
                _PinnedOriginBanner(controller: controller),
                const SizedBox(height: WSSpacing.sm),
              ],
              // Hint contextuel selon le mode
              if (controller.pointEstimate == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: WSSpacing.sm),
                  child: Text(
                    route.mode == RouteMode.freehand
                        ? 'Dessine ton itinéraire au doigt · long-press pour l\'isochrone'
                        : controller.pinnedOrigin == null
                            ? 'Tape un départ puis une arrivée · long-press pour l\'isochrone'
                            : 'Isochrone depuis l\'épingle · tape pour planifier',
                    style: WSText.caption,
                  ),
                )
              else ...[
                _EstimateRow(controller: controller),
                const SizedBox(height: WSSpacing.sm),
              ],
              Row(
                children: [
                  Expanded(
                    child: controller.computing
                        ? const _ComputingIndicator()
                        : FilledButton.icon(
                            onPressed: () => controller.computeIsochrones(),
                            icon: const Icon(
                                Icons.scatter_plot_outlined, size: 18),
                            label: Text(controller.contours.isEmpty
                                ? 'Calculer les isochrones'
                                : 'Recalculer'),
                          ),
                  ),
                  const SizedBox(width: WSSpacing.sm),
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
                      icon: const Icon(
                          Icons.layers_clear_outlined, size: 18),
                      onPressed: controller.clearIsochrones,
                      tooltip: 'Effacer les isochrones',
                    ),
                  ],
                ],
              ),
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

// ─── Widgets partagés (inchangés) ─────────────────────────────────────────────

class _PinnedOriginBanner extends StatelessWidget {
  final TimeController controller;
  const _PinnedOriginBanner({required this.controller});

  @override
  Widget build(BuildContext context) {
    final pin = controller.pinnedOrigin;
    if (pin == null) return const SizedBox.shrink();
    final coords =
        '${pin.latitude.toStringAsFixed(4)}, ${pin.longitude.toStringAsFixed(4)}';
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: WSSpacing.md, vertical: WSSpacing.sm),
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
                Text('Origine épinglée',
                    style: WSText.caption.copyWith(
                        color: WSColors.glacierBlue,
                        fontWeight: FontWeight.w500)),
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
        Expanded(child: Text(estimate, style: WSText.heading)),
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

class _CalibrationSummary extends StatelessWidget {
  final TimeController controller;
  const _CalibrationSummary({required this.controller});

  @override
  Widget build(BuildContext context) {
    final report = controller.calibratorReport;
    final isCalibrated = controller.isCalibrated;
    final weight = report['poids'] ?? '0%';
    final hSpeed = report['hSpeed'] ?? '?';
    final aRate = report['ascentRate'] ?? '?';
    final segments = report['segments'] ?? '';

    final mainText = isCalibrated
        ? '$hSpeed · $aRate'
        : segments.isNotEmpty &&
                segments != '0 acceptés, 0 rejetés'
            ? segments
            : 'Calibration en attente (marche pour démarrer)';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: WSSpacing.sm, vertical: 6),
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
            child: Text(mainText,
                style: WSText.micro.copyWith(color: WSColors.slateDark),
                overflow: TextOverflow.ellipsis),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: controller.anyLocked
                  ? WSColors.sunOrange.withOpacity(0.15)
                  : isCalibrated
                      ? WSColors.powderGreen.withOpacity(0.18)
                      : WSColors.glacierMid.withOpacity(0.25),
              borderRadius: BorderRadius.circular(WSRadius.pill),
            ),
            child: Text(
              controller.anyLocked
                  ? '🔒 manuel'
                  : isCalibrated ? '✓ $weight' : 'baseline',
              style: WSText.micro.copyWith(
                color: controller.anyLocked
                    ? WSColors.sunOrange
                    : isCalibrated ? WSColors.powderGreen : WSColors.stoneGray,
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

void _openCalibrationSheet(
    BuildContext context, TimeController controller) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) =>
          _CalibrationSheet(controller: controller),
    ),
  );
}

// ─── CalibrationSheet avec cadenas ───────────────────────────────────────────

class _CalibrationSheet extends StatefulWidget {
  final TimeController controller;
  const _CalibrationSheet({required this.controller});

  @override
  State<_CalibrationSheet> createState() => _CalibrationSheetState();
}

class _CalibrationSheetState extends State<_CalibrationSheet> {
  TimeController get c => widget.controller;

  // Valeurs locales des sliders (mise à jour en temps réel sans sauvegarder
  // à chaque tick — la sauvegarde intervient quand on pose le cadenas).
  late double _hSpeedVal;
  late double _ascentVal;
  late double _descentVal;

  @override
  void initState() {
    super.initState();
    _hSpeedVal  = c.hSpeedOverride  ?? c.munter.currentParams.horizontalSpeed;
    _ascentVal  = c.ascentOverride  ?? c.munter.currentParams.ascentRate;
    _descentVal = c.descentOverride ?? c.munter.currentParams.descentRate;
  }

  @override
  Widget build(BuildContext context) {
    final report       = c.calibratorReport;
    final isCalibrated = c.isCalibrated;
    final anyLocked    = c.anyLocked;

    return Container(
      decoration: const BoxDecoration(
        color: WSColors.snowWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(WSRadius.xl)),
      ),
      // Limite la hauteur max à 85% de l'écran et rend le contenu scrollable
      // pour éviter le overflow quand les sliders sont tous ouverts.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            WSSpacing.xl, WSSpacing.lg, WSSpacing.xl, WSSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // ── Poignée ─────────────────────────────────────────────────────
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

          // ── Titre + badge calibration ────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.speed, size: 18, color: WSColors.slateDark),
              const SizedBox(width: WSSpacing.sm),
              const Text('Paramètres Munter', style: WSText.title),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: WSSpacing.md, vertical: 4),
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

          // ── Toggle global Mode manuel ────────────────────────────────────
          _ManualModeToggle(
            anyLocked: anyLocked,
            onToggle: (enabled) {
              setState(() {
                if (enabled) {
                  // Active tous les cadenas sur les valeurs courantes
                  _hSpeedVal  = c.munter.effectiveParams.horizontalSpeed;
                  _ascentVal  = c.munter.effectiveParams.ascentRate;
                  _descentVal = c.munter.effectiveParams.descentRate;
                  c.lockHSpeed(_hSpeedVal);
                  c.lockAscent(_ascentVal);
                  c.lockDescent(_descentVal);
                } else {
                  c.unlockAll();
                }
              });
            },
          ),
          const SizedBox(height: WSSpacing.md),

          // ── Ligne Vitesse horizontale ────────────────────────────────────
          _LockableParamRow(
            label: 'Vitesse horizontale',
            unit: 'km/h',
            value: _hSpeedVal,
            locked: c.hSpeedLocked,
            min: 1.0,
            max: 12.0,
            divisions: 22,
            displayValue: c.hSpeedLocked
                ? _hSpeedVal.toStringAsFixed(1)
                : (report['hSpeed'] ?? '?'),
            onLockToggle: () => setState(() {
              if (c.hSpeedLocked) {
                c.unlockHSpeed();
              } else {
                _hSpeedVal = c.munter.effectiveParams.horizontalSpeed;
                c.lockHSpeed(_hSpeedVal);
              }
            }),
            onChanged: (v) => setState(() {
              _hSpeedVal = v;
              c.updateHSpeedOverride(v);
            }),
            onChangeEnd: (v) => c.lockHSpeed(v),
          ),

          // ── Ligne Dénivelé positif ───────────────────────────────────────
          _LockableParamRow(
            label: 'Dénivelé positif',
            unit: 'm/h',
            value: _ascentVal,
            locked: c.ascentLocked,
            min: 100.0,
            max: 1000.0,
            divisions: 18,
            displayValue: c.ascentLocked
                ? _ascentVal.toStringAsFixed(0)
                : (report['ascentRate'] ?? '?'),
            onLockToggle: () => setState(() {
              if (c.ascentLocked) {
                c.unlockAscent();
              } else {
                _ascentVal = c.munter.effectiveParams.ascentRate;
                c.lockAscent(_ascentVal);
              }
            }),
            onChanged: (v) => setState(() {
              _ascentVal = v;
              c.updateAscentOverride(v);
            }),
            onChangeEnd: (v) => c.lockAscent(v),
          ),

          // ── Ligne Dénivelé négatif ───────────────────────────────────────
          _LockableParamRow(
            label: 'Dénivelé négatif',
            unit: 'm/h',
            value: _descentVal,
            locked: c.descentLocked,
            min: 200.0,
            max: 1500.0,
            divisions: 13,
            displayValue: c.descentLocked
                ? _descentVal.toStringAsFixed(0)
                : (report['descentRate'] ?? '?'),
            onLockToggle: () => setState(() {
              if (c.descentLocked) {
                c.unlockDescent();
              } else {
                _descentVal = c.munter.effectiveParams.descentRate;
                c.lockDescent(_descentVal);
              }
            }),
            onChanged: (v) => setState(() {
              _descentVal = v;
              c.updateDescentOverride(v);
            }),
            onChangeEnd: (v) => c.lockDescent(v),
          ),

          const SizedBox(height: WSSpacing.md),

          // ── Segments GPS ─────────────────────────────────────────────────
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
                  Text('Segments GPS',
                      style: WSText.micro.copyWith(color: WSColors.stoneGray)),
                  const SizedBox(height: 4),
                  Text(report['segments']!, style: WSText.body),
                ],
              ),
            ),

          const SizedBox(height: WSSpacing.md),

          // ── Source altitude ──────────────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.terrain, size: 14, color: WSColors.stoneGray),
              const SizedBox(width: 6),
              Text('Source d\'altitude : ${c.demSourceLabel}',
                  style: WSText.caption),
            ],
          ),
          const SizedBox(height: WSSpacing.md),

          // ── Info contextuelle ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(WSSpacing.md),
            decoration: BoxDecoration(
              color: anyLocked
                  ? WSColors.sunOrange.withOpacity(0.08)
                  : WSColors.glacierBlueBg,
              borderRadius: BorderRadius.circular(WSRadius.md),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  anyLocked ? Icons.lock_outline : Icons.info_outline,
                  size: 14,
                  color: anyLocked ? WSColors.sunOrange : WSColors.glacierBlue,
                ),
                const SizedBox(width: WSSpacing.sm),
                Expanded(
                  child: Text(
                    anyLocked
                        ? 'Paramètres manuels actifs. La calibration GPS continue '
                            'en arrière-plan et s\'applique dès que tu décadenasses.'
                        : isCalibrated
                            ? 'Paramètres calibrés sur tes mesures GPS. '
                                'Cadenas un paramètre pour le forcer manuellement.'
                            : 'Marche au moins 3 segments de 50m / 1 min pour démarrer '
                                'la calibration. Tu peux aussi forcer les valeurs avec le cadenas.',
                    style: WSText.caption.copyWith(
                      color: anyLocked
                          ? WSColors.sunOrange
                          : WSColors.glacierBlue,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }
}

// ── Toggle global Mode manuel ─────────────────────────────────────────────────

class _ManualModeToggle extends StatelessWidget {
  final bool anyLocked;
  final ValueChanged<bool> onToggle;
  const _ManualModeToggle({required this.anyLocked, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onToggle(!anyLocked),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
            horizontal: WSSpacing.md, vertical: WSSpacing.sm),
        decoration: BoxDecoration(
          color: anyLocked
              ? WSColors.sunOrange.withOpacity(0.10)
              : WSColors.glacierLight,
          borderRadius: BorderRadius.circular(WSRadius.md),
          border: Border.all(
            color: anyLocked
                ? WSColors.sunOrange.withOpacity(0.40)
                : WSColors.glacierMid,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              anyLocked ? Icons.lock : Icons.lock_open,
              size: 16,
              color: anyLocked ? WSColors.sunOrange : WSColors.stoneGray,
            ),
            const SizedBox(width: WSSpacing.sm),
            Expanded(
              child: Text(
                anyLocked ? 'Mode manuel actif' : 'Mode manuel',
                style: WSText.body.copyWith(
                  color: anyLocked ? WSColors.sunOrange : WSColors.slateDark,
                  fontWeight: anyLocked ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            Switch(
              value: anyLocked,
              onChanged: onToggle,
              activeColor: WSColors.sunOrange,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Ligne paramètre avec cadenas individuel ───────────────────────────────────

class _LockableParamRow extends StatelessWidget {
  final String label;
  final String unit;
  final double value;
  final bool locked;
  final double min;
  final double max;
  final int divisions;
  final String displayValue;
  final VoidCallback onLockToggle;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _LockableParamRow({
    required this.label,
    required this.unit,
    required this.value,
    required this.locked,
    required this.min,
    required this.max,
    required this.divisions,
    required this.displayValue,
    required this.onLockToggle,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WSSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Label + valeur + cadenas ───────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Text(label, style: WSText.body),
              ),
              Text(
                '$displayValue $unit',
                style: WSText.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: locked ? WSColors.sunOrange : WSColors.slateDark,
                ),
              ),
              const SizedBox(width: WSSpacing.sm),
              GestureDetector(
                onTap: onLockToggle,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: locked
                        ? WSColors.sunOrange.withOpacity(0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(WSRadius.sm),
                  ),
                  child: Icon(
                    locked ? Icons.lock : Icons.lock_open_outlined,
                    size: 16,
                    color: locked ? WSColors.sunOrange : WSColors.stoneGray,
                  ),
                ),
              ),
            ],
          ),
          // ── Slider (visible uniquement si cadenassé) ───────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: locked
                ? SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: WSColors.sunOrange,
                      thumbColor: WSColors.sunOrange,
                      inactiveTrackColor: WSColors.sunOrange.withOpacity(0.20),
                      overlayColor: WSColors.sunOrange.withOpacity(0.12),
                      trackHeight: 2,
                    ),
                    child: Slider(
                      value: value.clamp(min, max),
                      min: min,
                      max: max,
                      divisions: divisions,
                      onChanged: onChanged,
                      onChangeEnd: onChangeEnd,
                    ),
                  )
                : const SizedBox.shrink(),
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
          Text(value,
              style: WSText.body.copyWith(fontWeight: FontWeight.w600)),
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
            width: 16, height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor:
                  AlwaysStoppedAnimation(WSColors.glacierBlue),
            ),
          ),
          SizedBox(width: WSSpacing.sm),
          Text('Calcul des isochrones…',
              style: TextStyle(
                  fontSize: 12, color: WSColors.glacierBlue)),
        ],
      ),
    );
  }
}

// ─── Toggle Auto / Main levée ─────────────────────────────────────────────────

class _RouteModeToggle extends StatelessWidget {
  final RouteController route;
  const _RouteModeToggle({required this.route});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: WSColors.glacierLight,
        borderRadius: BorderRadius.circular(WSRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _pill(
            icon: Icons.route_outlined,
            label: 'Auto',
            active: route.mode == RouteMode.auto,
            onTap: () => route.setMode(RouteMode.auto),
          ),
          _pill(
            icon: Icons.gesture,
            label: 'Main levée',
            active: route.mode == RouteMode.freehand,
            onTap: () => route.setMode(RouteMode.freehand),
          ),
        ],
      ),
    );
  }

  Widget _pill({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(
            horizontal: WSSpacing.md, vertical: 4),
        decoration: BoxDecoration(
          color: active ? WSColors.glacierBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(WSRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: active ? WSColors.snowWhite : WSColors.stoneGray),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: active ? WSColors.snowWhite : WSColors.stoneGray,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── DragHandler dessin libre ─────────────────────────────────────────────────
//
// Implémente MapDragHandler : la WSMapScreen gèle le pan/zoom et relaie
// les gestes convertis en LatLng via _pixelToLatLng.

class _FreehandDragHandler extends MapDragHandler {
  final RouteController route;
  _FreehandDragHandler(this.route);

  @override
  void onDragStart(LatLng start) => route.onFreehandStart(start);

  @override
  void onDragUpdate(LatLng current) => route.onFreehandUpdate(current);

  @override
  void onDragEnd(LatLng end) => route.onFreehandEnd();
}

