// lib/modules/snow/quick_observation_sheet.dart
//
// Bottom sheet pour créer une observation rapide AU POINT GPS ACTUEL
// sans enregistrement audio. L'utilisateur :
//   1. Voit sa position GPS (lat/lon, altitude si dispo)
//   2. Choisit un type de neige parmi 9 chips
//   3. Tape "Enregistrer"
//
// L'observation est sauvée localement et apparaît immédiatement sur la
// carte. L'utilisateur pourra ensuite éditer (note, profondeur, expo...)
// via le détail de l'obs (tap sur le pin).
//
// Si pas de position GPS → on bloque l'enregistrement avec un message clair.

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/gps/gps_service.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/snow_palette.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import 'models/observation.dart';
import 'snow_controller.dart';
import 'snow_dao.dart';

class QuickObservationSheet extends StatefulWidget {
  const QuickObservationSheet({super.key});

  /// Ouvre le sheet et retourne l'obs créée (ou null si annulé).
  static Future<Observation?> show(BuildContext context) {
    return showModalBottomSheet<Observation?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const QuickObservationSheet(),
    );
  }

  @override
  State<QuickObservationSheet> createState() => _QuickObservationSheetState();
}

class _QuickObservationSheetState extends State<QuickObservationSheet> {
  // Ordre cohérent avec la fréquence d'usage typique en ski de rando.
  static const _types = <String>[
    SnowTypes.poudre,
    SnowTypes.moquette,
    SnowTypes.transfo,
    SnowTypes.croute,
    SnowTypes.beton,
    SnowTypes.ventee,
    SnowTypes.humide,
    SnowTypes.lourde,
    SnowTypes.purge,
    SnowTypes.autre,
  ];

  String? _selectedType;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final gps = GpsService();
    final pos = gps.last;

    return Container(
      decoration: const BoxDecoration(
        color: WSColors.snowWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(WSRadius.lg)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            WSSpacing.lg,
            WSSpacing.md,
            WSSpacing.lg,
            WSSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
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

              Text('Nouvelle observation', style: WSText.heading),
              const SizedBox(height: WSSpacing.xs),
              Text(
                'Au point GPS actuel, sans audio.',
                style: WSText.micro.copyWith(color: WSColors.stoneGray),
              ),

              const SizedBox(height: WSSpacing.lg),

              // ─── Position GPS ───────────────────────────────────────────
              _PositionBlock(position: pos),

              const SizedBox(height: WSSpacing.lg),

              // ─── Sélection du type ──────────────────────────────────────
              Text(
                'Type de neige',
                style: WSText.heading.copyWith(fontSize: 16),
              ),
              const SizedBox(height: WSSpacing.md),
              Wrap(
                spacing: WSSpacing.sm,
                runSpacing: WSSpacing.sm,
                children: _types.map((t) {
                  final isSel = _selectedType == t;
                  return _TypeChip(
                    label: t,
                    color: SnowPalette.colorForUserType(t),
                    selected: isSel,
                    onTap: () => setState(() => _selectedType = t),
                  );
                }).toList(),
              ),

              const SizedBox(height: WSSpacing.xl),

              // ─── Boutons ────────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: WSSpacing.md),
                      ),
                      child: const Text('Annuler'),
                    ),
                  ),
                  const SizedBox(width: WSSpacing.md),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: (pos == null ||
                              _selectedType == null ||
                              _saving)
                          ? null
                          : () => _save(pos),
                      style: FilledButton.styleFrom(
                        backgroundColor: WSColors.glacierBlue,
                        padding:
                            const EdgeInsets.symmetric(vertical: WSSpacing.md),
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 16, width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : const Text('Enregistrer'),
                    ),
                  ),
                ],
              ),

              if (pos == null) ...[
                const SizedBox(height: WSSpacing.md),
                Container(
                  padding: const EdgeInsets.all(WSSpacing.md),
                  decoration: BoxDecoration(
                    color: WSColors.avalancheRedBg,
                    borderRadius: BorderRadius.circular(WSRadius.md),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: WSColors.avalancheRed, size: 18),
                      const SizedBox(width: WSSpacing.sm),
                      Expanded(
                        child: Text(
                          'Position GPS indisponible. Active la localisation '
                          'pour pouvoir enregistrer.',
                          style: WSText.micro.copyWith(
                            color: WSColors.avalancheRed,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─── Sauvegarde ─────────────────────────────────────────────────────────

  Future<void> _save(Position pos) async {
    if (_selectedType == null) return;
    setState(() => _saving = true);

    final obs = Observation(
      // Même format d'id que SnowController.startRecording : timestamp pur,
      // pour rester cohérent avec ce qui est uploadé sur Supabase.
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      lat: pos.latitude,
      lon: pos.longitude,
      altitudeM: pos.altitude,
      timestamp: DateTime.now(),
      audioPath: '', // pas d'audio pour une obs rapide
      snowType: _selectedType,
      // depthCm, stabilityScore, aspect, rawNotes : null → éditables ensuite
      uploaded: false,
    );

    try {
      await SnowDao().save(obs);
      // Notifier le controller pour rafraîchir la liste affichée
      await SnowController().refreshObservations();

      // ── Upload Supabase en arrière-plan ──────────────────────────────
      // L'obs rapide est déjà enrichie (snowType défini par l'utilisateur),
      // donc processPending() la passera direct à Supabase sans Whisper/IA.
      // Fire-and-forget : on ne bloque pas la fermeture du sheet.
      // Si l'upload échoue (réseau HS), l'obs reste avec uploaded=false et
      // sera retentée au prochain processPending() (ou au prochain lancement
      // de l'app si on branche ça plus tard).
      // ignore: discarded_futures
      SnowController().processPending();

      if (mounted) Navigator.of(context).pop(obs);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur enregistrement : $e')),
        );
      }
    }
  }
}

// ─── Sous-widgets ───────────────────────────────────────────────────────────

class _PositionBlock extends StatelessWidget {
  final Position? position;
  const _PositionBlock({required this.position});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(WSSpacing.md),
      decoration: BoxDecoration(
        color: WSColors.glacierBlueBg,
        borderRadius: BorderRadius.circular(WSRadius.md),
        border: Border.all(color: WSColors.glacierMid, width: 0.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on_outlined,
              size: 18, color: WSColors.glacierBlue),
          const SizedBox(width: WSSpacing.sm),
          Expanded(
            child: position == null
                ? Text(
                    'Position GPS introuvable',
                    style: WSText.body.copyWith(color: WSColors.stoneGray),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${position!.latitude.toStringAsFixed(5)}°N  '
                        '${position!.longitude.toStringAsFixed(5)}°E',
                        style: WSText.body.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          color: WSColors.slateDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${position!.altitude.toStringAsFixed(0)} m',
                        style: WSText.micro.copyWith(
                          color: WSColors.stoneGray,
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
      borderRadius: BorderRadius.circular(WSRadius.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: WSSpacing.md,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: selected ? color : WSColors.glacierLight,
          borderRadius: BorderRadius.circular(WSRadius.lg),
          border: Border.all(
            color: selected ? color : WSColors.glacierMid,
            width: selected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!selected)
              Container(
                width: 10, height: 10,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            Text(
              label,
              style: WSText.body.copyWith(
                fontSize: 14,
                color: selected ? Colors.white : WSColors.slateDark,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}