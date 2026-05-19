// lib/modules/conditions/condition_detail_sheet.dart
//
// Bottom sheet affichant les conditions détaillées (24h) d'un point.
// Affiché quand l'utilisateur tape sur la carte (ou sur une cellule de grille).

import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import 'conditions_controller.dart';
import 'models/condition_code.dart';
import 'models/point_conditions.dart';

class ConditionDetailSheet extends StatelessWidget {
  final PointConditions point;
  final int selectedHour;

  const ConditionDetailSheet({
    super.key,
    required this.point,
    required this.selectedHour,
  });

  @override
  Widget build(BuildContext context) {
    final hours = point.hours;
    return Container(
      decoration: const BoxDecoration(
        color: WSColors.snowWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(WSRadius.xl)),
      ),
      padding: const EdgeInsets.fromLTRB(
        WSSpacing.xl, WSSpacing.lg, WSSpacing.xl, WSSpacing.xl,
      ),
      child: SingleChildScrollView(
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

            // Header : altitude, exposition, pente
            _Header(point: point),

            const SizedBox(height: WSSpacing.lg),

            // Bera (si présent)
            if (point.bera != null && point.bera!.massifName != null) ...[
              _BeraSummary(point: point),
              const SizedBox(height: WSSpacing.lg),
            ],

            // Bandeau 24h
            _label('Évolution sur 24h'),
            const SizedBox(height: WSSpacing.sm),
            SizedBox(
              height: 64,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: hours.length,
                itemBuilder: (_, i) {
                  final h = hours[i];
                  final isSelected = h.hour == selectedHour;
                  final meta = ConditionMeta.forCode(h.condition);
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Container(
                      width: 36,
                      decoration: BoxDecoration(
                        color: meta.color.withOpacity(isSelected ? 0.32 : 0.15),
                        borderRadius: BorderRadius.circular(WSRadius.sm),
                        border: Border.all(
                          color: isSelected ? meta.color : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Text('${h.hour}h',
                              style: WSText.micro.copyWith(
                                  color: WSColors.slateDark,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w400)),
                          Text('${h.tempSurface.round()}°',
                              style: WSText.caption),
                          Text('${h.windSpeed.round()}',
                              style: WSText.micro.copyWith(
                                  color: WSColors.stoneGray)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: WSSpacing.lg),

            // Condition à l'heure sélectionnée
            _CurrentHourBlock(point: point, hour: selectedHour),

            const SizedBox(height: WSSpacing.md),
          ],
        ),
      ),
    );
  }

  Widget _label(String txt) => Text(
        txt.toUpperCase(),
        style: WSText.micro.copyWith(color: WSColors.stoneGray),
      );
}

class _Header extends StatelessWidget {
  final PointConditions point;
  const _Header({required this.point});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('${point.elevationM.round()}', style: WSText.numeric),
                  const SizedBox(width: 4),
                  Text(' m', style: WSText.caption),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Versant ${point.aspectLabel}  ·  Pente ${point.slopeDeg.round()}°',
                style: WSText.caption,
              ),
              const SizedBox(height: 2),
              Text(
                '${point.lat.toStringAsFixed(4)}, ${point.lon.toStringAsFixed(4)}',
                style: WSText.micro,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BeraSummary extends StatelessWidget {
  final PointConditions point;
  const _BeraSummary({required this.point});

  @override
  Widget build(BuildContext context) {
    final bera = point.bera!;
    return Container(
      padding: const EdgeInsets.all(WSSpacing.md),
      decoration: BoxDecoration(
        color: WSColors.glacierBlueBg,
        borderRadius: BorderRadius.circular(WSRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.terrain, size: 14, color: WSColors.glacierBlue),
              const SizedBox(width: WSSpacing.xs),
              Expanded(
                child: Text(
                  bera.massifName ?? '—',
                  style: WSText.body.copyWith(
                    color: WSColors.glacierBlue,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (bera.beraDate != null)
                Text(bera.beraDate!, style: WSText.micro),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: WSSpacing.md,
            runSpacing: WSSpacing.xs,
            children: [
              if (bera.bera24hCm != null)
                Text('24h : ${bera.bera24hCm!.round()} cm',
                    style: WSText.caption),
              if (bera.bera72hCm != null)
                Text('72h : ${bera.bera72hCm!.round()} cm',
                    style: WSText.caption),
              if (bera.limiteNordM != null)
                Text('Limite N : ${bera.limiteNordM} m',
                    style: WSText.caption),
              if (bera.limiteSudM != null)
                Text('Limite S : ${bera.limiteSudM} m',
                    style: WSText.caption),
            ],
          ),
        ],
      ),
    );
  }
}

class _CurrentHourBlock extends StatelessWidget {
  final PointConditions point;
  final int hour;
  const _CurrentHourBlock({required this.point, required this.hour});

  @override
  Widget build(BuildContext context) {
    final h = point.conditionAt(hour);
    if (h == null) return const SizedBox.shrink();
    final meta = ConditionMeta.forCode(h.condition);
    return Container(
      padding: const EdgeInsets.all(WSSpacing.md),
      decoration: BoxDecoration(
        color: meta.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(WSRadius.md),
      ),
      child: Row(
        children: [
          Container(
            width: 14, height: 14,
            decoration: BoxDecoration(
              color: meta.color, shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: WSSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${h.hour}h UTC  ·  ${meta.label}',
                    style: WSText.body.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(
                  'Surface ${h.tempSurface.toStringAsFixed(1)}°C  ·  '
                  'Vent ${h.windSpeed.round()} km/h',
                  style: WSText.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
