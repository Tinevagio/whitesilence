// lib/modules/conditions/conditions_date_chip.dart
//
// Chip compact affichant la date sélectionnée + ouvre une bottom sheet
// avec des options rapides (Aujourd'hui, Demain, J+2..J+7) et un bouton
// "Autre date" qui ouvre le DatePicker Material standard.
//
// Posé dans le bandeau du haut via `buildTopChrome` du module Conditions.
// Tap = ouvre bottom sheet. Mode gants permanent (~40dp de haut).

import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import 'conditions_controller.dart';

class ConditionsDateChip extends StatelessWidget {
  final ConditionsController controller;

  const ConditionsDateChip({super.key, required this.controller});

  // Open-Meteo Forecast couvre J → J+7 ; on autorise pas le passé (Conditions
  // = planification, pas analyse rétrospective).
  static const int _kDaysAhead = 7;
  static const int _kDaysBehind = 0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final selected = controller.selectedDate;
        final isToday = _isSameDay(selected, DateTime.now());
        final label = _formatChipLabel(selected);

        return InkWell(
          onTap: () => _openSheet(context),
          borderRadius: BorderRadius.circular(WSRadius.lg),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: WSSpacing.sm,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: isToday
                  ? Colors.white.withOpacity(0.95)
                  : WSColors.glacierBlue.withOpacity(0.12),
              borderRadius: BorderRadius.circular(WSRadius.lg),
              border: Border.all(
                color: isToday
                    ? WSColors.glacierMid
                    : WSColors.glacierBlue.withOpacity(0.4),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.event,
                  size: 14,
                  color: isToday
                      ? WSColors.slateDark
                      : WSColors.glacierBlue,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: WSText.micro.copyWith(
                    color: isToday
                        ? WSColors.slateDark
                        : WSColors.glacierBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Bottom sheet ─────────────────────────────────────────────────────────

  void _openSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _DateSheet(controller: controller),
    );
  }

  // ─── Helpers de format ────────────────────────────────────────────────────

  /// Format compact pour le chip ("Auj.", "Demain", "Sam 25").
  static String _formatChipLabel(DateTime d) {
    final today = DateTime.now();
    final t = DateTime(today.year, today.month, today.day);
    final s = DateTime(d.year, d.month, d.day);
    final diff = s.difference(t).inDays;

    if (diff == 0) return 'Auj.';
    if (diff == 1) return 'Demain';
    if (diff == -1) return 'Hier';
    // Au-delà : "Sam 25"
    return '${_shortWeekday(s.weekday)} ${s.day}';
  }

  static String _shortWeekday(int w) =>
      const ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'][w - 1];

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ─── Bottom sheet contenu ──────────────────────────────────────────────────

class _DateSheet extends StatelessWidget {
  final ConditionsController controller;
  const _DateSheet({required this.controller});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final selected = controller.selectedDate;

    // 8 options rapides : Aujourd'hui + J+1..J+7
    final quickOptions = List<DateTime>.generate(
      8,
      (i) => DateTime(today.year, today.month, today.day + i),
    );

    return Container(
      decoration: const BoxDecoration(
        color: WSColors.snowWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(WSRadius.lg)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            WSSpacing.lg,
            WSSpacing.md,
            WSSpacing.lg,
            WSSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Petit handle
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: WSSpacing.md),
                  decoration: BoxDecoration(
                    color: WSColors.glacierMid,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('Date des conditions', style: WSText.heading),
              const SizedBox(height: WSSpacing.xs),
              Text(
                'Choisis le jour pour lequel afficher les conditions de neige '
                'et météo. Le BERA tombe sur la dernière publication '
                'disponible si la date est plus tard.',
                style: WSText.micro.copyWith(
                  color: WSColors.stoneGray,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: WSSpacing.lg),

              // Grille de chips Auj / Demain / J+2..J+7
              Wrap(
                spacing: WSSpacing.sm,
                runSpacing: WSSpacing.sm,
                children: quickOptions.map((d) {
                  final isSel = _isSameDay(d, selected);
                  return _DateChip(
                    label: _formatFullLabel(d, today),
                    selected: isSel,
                    onTap: () async {
                      Navigator.of(context).pop();
                      await controller.setSelectedDate(d);
                    },
                  );
                }).toList(),
              ),

              const SizedBox(height: WSSpacing.lg),
              const Divider(color: WSColors.glacierMid, height: 1),
              const SizedBox(height: WSSpacing.md),

              // Bouton "Autre date" → DatePicker Material
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selected,
                      firstDate: today,
                      lastDate: today.add(
                        const Duration(days: ConditionsDateChip._kDaysAhead),
                      ),
                      helpText: 'Choisir une date',
                      cancelText: 'Annuler',
                      confirmText: 'OK',
                      locale: const Locale('fr', 'FR'),
                    );
                    if (picked != null && context.mounted) {
                      Navigator.of(context).pop();
                      await controller.setSelectedDate(picked);
                    }
                  },
                  icon: const Icon(Icons.calendar_month, size: 18),
                  label: const Text('Autre date'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(
                      color: WSColors.glacierMid,
                      width: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  /// Format complet pour les chips dans la sheet ("Aujourd'hui", "Demain",
  /// "Sam 25 mai").
  static String _formatFullLabel(DateTime d, DateTime today) {
    final t = DateTime(today.year, today.month, today.day);
    final s = DateTime(d.year, d.month, d.day);
    final diff = s.difference(t).inDays;
    if (diff == 0) return 'Aujourd\'hui';
    if (diff == 1) return 'Demain';
    return '${_fullWeekday(s.weekday)} ${s.day} ${_shortMonth(s.month)}';
  }

  static String _fullWeekday(int w) =>
      const ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'][w - 1];

  static String _shortMonth(int m) =>
      const ['janv', 'févr', 'mars', 'avr', 'mai', 'juin',
             'juil', 'août', 'sept', 'oct', 'nov', 'déc'][m - 1];

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ─── Chip d'option rapide ───────────────────────────────────────────────────

class _DateChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DateChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(WSRadius.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: WSSpacing.md,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: selected
              ? WSColors.glacierBlue
              : WSColors.glacierLight,
          borderRadius: BorderRadius.circular(WSRadius.lg),
          border: Border.all(
            color: selected ? WSColors.glacierBlue : WSColors.glacierMid,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: WSText.body.copyWith(
            fontSize: 14,
            color: selected ? Colors.white : WSColors.slateDark,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
