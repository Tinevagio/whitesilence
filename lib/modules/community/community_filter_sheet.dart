// lib/modules/community/community_filter_sheet.dart
//
// Bottom sheet de filtrage des observations communautaires.
// Permet de choisir : types de neige (multi-select) + fenêtre temporelle.

import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/snow_palette.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../snow/models/observation.dart';
import 'community_controller.dart';

class CommunityFilterSheet extends StatelessWidget {
  final CommunityController controller;
  const CommunityFilterSheet({super.key, required this.controller});

  static const _availableTypes = [
    SnowTypes.poudre,
    SnowTypes.moquette,
    SnowTypes.transfo,
    SnowTypes.beton,
    SnowTypes.croute,
    SnowTypes.ventee,
    SnowTypes.humide,
    SnowTypes.purge,
    SnowTypes.lourde,
    SnowTypes.autre,
  ];

  static const _windowOptions = [1, 3, 7, 14, 30];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Container(
          decoration: const BoxDecoration(
            color: WSColors.snowWhite,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(WSRadius.xl),
            ),
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
              const Text('Filtres', style: WSText.title),
              const SizedBox(height: WSSpacing.lg),

              // ── Fenêtre temporelle ───────────────────────────────────────
              _label('Période'),
              const SizedBox(height: WSSpacing.sm),
              Wrap(
                spacing: WSSpacing.sm,
                children: [
                  for (final d in _windowOptions)
                    _PillButton(
                      label: d == 1 ? '24h' : '${d}j',
                      selected: controller.windowDays == d,
                      onTap: () => controller.setWindowDays(d),
                    ),
                ],
              ),

              const SizedBox(height: WSSpacing.xl),

              // ── Types de neige ───────────────────────────────────────────
              Row(
                children: [
                  Expanded(child: _label('Types de neige')),
                  if (controller.selectedTypes.isNotEmpty)
                    TextButton(
                      onPressed: controller.clearTypeFilter,
                      style: TextButton.styleFrom(
                        foregroundColor: WSColors.stoneGray,
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                      ),
                      child: const Text('Réinitialiser',
                          style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
              const SizedBox(height: WSSpacing.xs),
              Text(
                controller.selectedTypes.isEmpty
                    ? 'Aucun filtre → tous les types affichés'
                    : '${controller.selectedTypes.length} type(s) sélectionné(s)',
                style: WSText.micro,
              ),
              const SizedBox(height: WSSpacing.sm),
              Wrap(
                spacing: WSSpacing.sm,
                runSpacing: WSSpacing.sm,
                children: [
                  for (final t in _availableTypes)
                    _TypeChip(
                      label: t,
                      color: SnowPalette.colorForUserType(t),
                      selected: controller.isTypeSelected(t),
                      onTap: () => controller.toggleType(t),
                    ),
                ],
              ),

              const SizedBox(height: WSSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Voir sur la carte'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _label(String s) => Text(
        s.toUpperCase(),
        style: WSText.micro.copyWith(color: WSColors.stoneGray),
      );
}

class _PillButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PillButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(WSRadius.pill),
      child: Container(
        constraints: const BoxConstraints(minHeight: WSTouch.chip),
        padding: const EdgeInsets.symmetric(
          horizontal: WSSpacing.lg,
          vertical: WSSpacing.md,
        ),
        decoration: BoxDecoration(
          color: selected ? WSColors.glacierBlue : WSColors.snowWhite,
          borderRadius: BorderRadius.circular(WSRadius.pill),
          border: Border.all(
            color: selected ? WSColors.glacierBlue : WSColors.glacierMid,
            width: 0.5,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? WSColors.snowWhite : WSColors.slateDark,
            ),
          ),
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _TypeChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(WSRadius.pill),
      child: Container(
        constraints: const BoxConstraints(minHeight: WSTouch.chip),
        padding: const EdgeInsets.symmetric(
          horizontal: WSSpacing.lg,
          vertical: WSSpacing.md,
        ),
        decoration: BoxDecoration(
          color: selected ? color : WSColors.snowWhite,
          borderRadius: BorderRadius.circular(WSRadius.pill),
          border: Border.all(
            color: selected ? color : WSColors.glacierMid,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!selected) ...[
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? WSColors.snowWhite : WSColors.slateDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
