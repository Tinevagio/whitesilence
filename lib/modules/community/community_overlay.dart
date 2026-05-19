// lib/modules/community/community_overlay.dart
//
// Overlay du module Obs (communauté) sur la WSMapScreen.
//
// Affiche les observations partagées par d'autres skieurs comme des pins
// colorés sur la carte. Pas d'édition possible (lecture seule).
// L'action panel propose : rafraîchir, filtrer par type/date.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/map/map_module_overlay.dart';
import '../../core/module_registry.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../snow/models/observation.dart';
import 'community_controller.dart';
import 'community_filter_sheet.dart';

class CommunityModuleOverlay extends MapModuleOverlay {
  final CommunityController controller = CommunityController();

  CommunityModuleOverlay() {
    // Répercute les notifs du controller vers le shell
    controller.addListener(notifyListeners);
  }

  @override
  ModuleId get id => ModuleId.community;

  @override
  List<Widget> buildMapLayers(BuildContext context) {
    controller.start(); // idempotent
    return [_CommunityPinsLayer(controller: controller)];
  }

  @override
  Widget? buildActionPanel(BuildContext context) {
    return _CommunityActionPanel(controller: controller);
  }
}

// ─── Layer pins ──────────────────────────────────────────────────────────────

class _CommunityPinsLayer extends StatelessWidget {
  final CommunityController controller;
  const _CommunityPinsLayer({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final obs = controller.filtered;
        if (obs.isEmpty) return const SizedBox.shrink();
        return MarkerLayer(
          markers: [
            for (final o in obs)
              Marker(
                point: o.latLng,
                width: 44,
                height: 44,
                alignment: Alignment.center,
                child: _CommunityPin(
                  obs: o,
                  onTap: () => _openDetail(context, o),
                ),
              ),
          ],
        );
      },
    );
  }

  void _openDetail(BuildContext context, Observation obs) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _CommunityDetailSheet(obs: obs),
    );
  }
}

/// Pin légèrement différent de celui du module Neige (qui est TES obs).
/// Plus petit, contour pointillé/léger, pour signifier "obs d'autrui".
class _CommunityPin extends StatelessWidget {
  final Observation obs;
  final VoidCallback onTap;
  const _CommunityPin({required this.obs, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = WSColors.snowTypeColor(obs.snowType);
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Halo
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
          ),
          // Cœur du pin (anneau, pas plein, pour distinguer de TES obs)
          Container(
            width: 14, height: 14,
            decoration: BoxDecoration(
              color: WSColors.snowWhite,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bottom sheet de détail (lecture seule) ──────────────────────────────────

class _CommunityDetailSheet extends StatelessWidget {
  final Observation obs;
  const _CommunityDetailSheet({required this.obs});

  @override
  Widget build(BuildContext context) {
    final color = WSColors.snowTypeColor(obs.snowType);
    final dt = obs.timestamp;
    final dateStr = '${dt.day.toString().padLeft(2, "0")}/'
        '${dt.month.toString().padLeft(2, "0")} '
        '${dt.hour.toString().padLeft(2, "0")}:'
        '${dt.minute.toString().padLeft(2, "0")}';

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
          // Handle
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 12, height: 12,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: WSSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(obs.snowType ?? 'Non précisé', style: WSText.title),
                    Text(
                      '$dateStr  ·  ${obs.altitudeM?.round() ?? "?"} m'
                      '${obs.aspect != null ? "  ·  ${obs.aspect}" : ""}',
                      style: WSText.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (obs.depthCm != null || obs.stabilityScore != null) ...[
            const SizedBox(height: WSSpacing.md),
            Wrap(
              spacing: WSSpacing.sm,
              runSpacing: WSSpacing.sm,
              children: [
                if (obs.depthCm != null)
                  _Chip(label: '${obs.depthCm} cm', icon: Icons.straighten),
                if (obs.stabilityScore != null)
                  _Chip(
                    label: 'Stabilité ${obs.stabilityScore}/5',
                    icon: Icons.shield_outlined,
                  ),
              ],
            ),
          ],
          if (obs.rawNotes != null && obs.rawNotes!.isNotEmpty) ...[
            const SizedBox(height: WSSpacing.lg),
            Text(obs.rawNotes!, style: WSText.body),
          ],
          const SizedBox(height: WSSpacing.lg),
          Row(
            children: [
              const Icon(Icons.public, size: 12, color: WSColors.stoneGray),
              const SizedBox(width: 6),
              Text(
                'Partagé anonymement par la communauté',
                style: WSText.micro,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;
  const _Chip({required this.label, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WSSpacing.md,
        vertical: WSSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: WSColors.glacierLight,
        borderRadius: BorderRadius.circular(WSRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: WSColors.stoneGray),
          const SizedBox(width: WSSpacing.xs),
          Text(label, style: WSText.micro),
        ],
      ),
    );
  }
}

// ─── Action panel ────────────────────────────────────────────────────────────

class _CommunityActionPanel extends StatelessWidget {
  final CommunityController controller;
  const _CommunityActionPanel({required this.controller});

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
              _StatusLine(controller: controller),
              const SizedBox(height: WSSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openFilterSheet(context),
                      icon: const Icon(Icons.tune, size: 16),
                      label: Text(_filterLabel()),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: WSColors.glacierBlue,
                        side: const BorderSide(
                          color: WSColors.glacierBlue, width: 0.5),
                        padding: const EdgeInsets.symmetric(
                          horizontal: WSSpacing.md, vertical: 8,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: WSSpacing.sm),
                  IconButton.outlined(
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: 'Recharger',
                    onPressed: controller.refresh,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _filterLabel() {
    final n = controller.selectedTypes.length;
    final w = controller.windowDays;
    if (n == 0) return '${w}j · tous types';
    if (n == 1) return '${w}j · ${controller.selectedTypes.first}';
    return '${w}j · $n types';
  }

  void _openFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => CommunityFilterSheet(controller: controller),
    );
  }
}

class _StatusLine extends StatelessWidget {
  final CommunityController controller;
  const _StatusLine({required this.controller});

  @override
  Widget build(BuildContext context) {
    switch (controller.status) {
      case CommunityStatus.idle:
        return const Text('Chargement…', style: WSText.caption);
      case CommunityStatus.loading:
        return Row(children: const [
          SizedBox(
            width: 10, height: 10,
            child: CircularProgressIndicator(strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation(WSColors.glacierBlue)),
          ),
          SizedBox(width: WSSpacing.sm),
          Text('Récupération des obs partagées…', style: WSText.caption),
        ]);
      case CommunityStatus.error:
        return Text(
          'Erreur : ${controller.errorMessage ?? "inconnue"}',
          style: WSText.caption.copyWith(color: WSColors.avalancheRed),
        );
      case CommunityStatus.ready:
        final total = controller.all.length;
        final shown = controller.filtered.length;
        final txt = total == shown
            ? '$total obs sur ${controller.windowDays} jour(s)'
            : '$shown / $total obs (filtrées)';
        return Text(txt, style: WSText.caption);
    }
  }
}
