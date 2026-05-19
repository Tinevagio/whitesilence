// lib/modules/snow/snow_overlay.dart
//
// Overlay du module Neige sur la WSMapScreen.
//
// - Layers : un MarkerLayer avec un pin coloré par observation
// - Tap court sur un pin : ouvre la fiche
// - Tap court hors pin : pas d'action particulière (on n'estime pas comme time)
// - Action panel : bouton micro + traitement + accès au review

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/map/map_module_overlay.dart';
import '../../core/module_registry.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import 'edit_observation_screen.dart';
import 'models/observation.dart';
import 'review_screen.dart';
import 'snow_controller.dart';

class SnowModuleOverlay extends MapModuleOverlay {
  final SnowController controller = SnowController();

  @override
  ModuleId get id => ModuleId.snow;

  @override
  List<Widget> buildMapLayers(BuildContext context) {
    return [
      _ObservationsLayer(controller: controller),
    ];
  }

  @override
  Widget? buildActionPanel(BuildContext context) {
    return _SnowActionPanel(controller: controller);
  }
}

// ─── Layer pins ──────────────────────────────────────────────────────────────

class _ObservationsLayer extends StatelessWidget {
  final SnowController controller;
  const _ObservationsLayer({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final obs = controller.observations;
        if (obs.isEmpty) return const SizedBox.shrink();

        return MarkerLayer(
          markers: [
            for (final o in obs)
              Marker(
                point: o.latLng,
                width: 44,
                height: 44,
                alignment: Alignment.center,
                child: _ObservationMarker(
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
      builder: (_) => _ObservationDetailSheet(
        obs: obs,
        controller: controller,
      ),
    );
  }
}

class _ObservationMarker extends StatelessWidget {
  final Observation obs;
  final VoidCallback onTap;
  const _ObservationMarker({required this.obs, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = WSColors.snowTypeColor(obs.snowType);
    final isPending = !obs.isEnriched; // pas encore passé par l'IA

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Halo discret
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.18),
              shape: BoxShape.circle,
            ),
          ),
          // Cœur du pin
          Container(
            width: 16, height: 16,
            decoration: BoxDecoration(
              color: isPending ? WSColors.snowWhite : color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isPending ? WSColors.stoneGray : WSColors.snowWhite,
                width: 2,
              ),
            ),
            child: isPending
                ? Center(
                    child: Container(
                      width: 4, height: 4,
                      decoration: const BoxDecoration(
                        color: WSColors.stoneGray,
                        shape: BoxShape.circle,
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

// ─── Bottom sheet de détail ──────────────────────────────────────────────────

class _ObservationDetailSheet extends StatelessWidget {
  final Observation obs;
  final SnowController controller;

  const _ObservationDetailSheet({
    required this.obs,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final color = WSColors.snowTypeColor(obs.snowType);
    final timeStr = '${obs.timestamp.day.toString().padLeft(2, "0")}/'
        '${obs.timestamp.month.toString().padLeft(2, "0")} '
        '${obs.timestamp.hour.toString().padLeft(2, "0")}:'
        '${obs.timestamp.minute.toString().padLeft(2, "0")}';

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
              width: 36,
              height: 4,
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
                    Text(
                      obs.snowType ?? 'Non traitée',
                      style: WSText.title.copyWith(
                        color: obs.isEnriched ? WSColors.slateDark : WSColors.stoneGray,
                      ),
                    ),
                    Text(
                      '$timeStr  ·  ${obs.altitudeM?.round() ?? "?"} m'
                      '${obs.aspect != null ? "  ·  ${obs.aspect}" : ""}',
                      style: WSText.caption,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: 'Modifier',
                onPressed: () async {
                  Navigator.pop(context); // ferme le bottom sheet
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => EditObservationScreen(observation: obs),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: 'Supprimer',
                onPressed: () async {
                  await controller.deleteObservation(obs);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ],
          ),

          // Détails
          if (obs.depthCm != null || obs.stabilityScore != null) ...[
            const SizedBox(height: WSSpacing.md),
            Row(
              children: [
                if (obs.depthCm != null) ...[
                  _Chip(label: '${obs.depthCm} cm', icon: Icons.straighten),
                  const SizedBox(width: WSSpacing.sm),
                ],
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
          ] else if (obs.transcript != null) ...[
            const SizedBox(height: WSSpacing.lg),
            Text(
              '« ${obs.transcript} »',
              style: WSText.body.copyWith(fontStyle: FontStyle.italic),
            ),
          ] else if (!obs.isEnriched) ...[
            const SizedBox(height: WSSpacing.lg),
            Text(
              'Observation enregistrée — pas encore traitée par l\'IA.',
              style: WSText.caption,
            ),
          ],

          const SizedBox(height: WSSpacing.lg),
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

class _SnowActionPanel extends StatelessWidget {
  final SnowController controller;
  const _SnowActionPanel({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // start() est idempotent (cf. flag _started dans SnowController),
        // donc on peut l'appeler à chaque rebuild sans risque
        controller.start();

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
              _HandsFreeToggle(controller: controller),
              const SizedBox(height: WSSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: _MicButton(controller: controller),
                  ),
                  const SizedBox(width: WSSpacing.sm),
                  _MoreMenu(controller: controller),
                ],
              ),
              if (controller.isProcessing &&
                  controller.progressTotal > 0) ...[
                const SizedBox(height: WSSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: controller.progressCurrent /
                        controller.progressTotal,
                    minHeight: 3,
                    backgroundColor: WSColors.glacierLight,
                    valueColor: const AlwaysStoppedAnimation(
                      WSColors.glacierBlue,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _StatusLine extends StatelessWidget {
  final SnowController controller;
  const _StatusLine({required this.controller});

  @override
  Widget build(BuildContext context) {
    final n = controller.observations.length;
    final msg = controller.statusMessage.isEmpty
        ? (n == 0
            ? 'Tap micro pour enregistrer une observation'
            : '$n observation(s) cette session')
        : controller.statusMessage;
    return Text(msg, style: WSText.caption);
  }
}

class _MicButton extends StatelessWidget {
  final SnowController controller;
  const _MicButton({required this.controller});

  @override
  Widget build(BuildContext context) {
    if (controller.isProcessing) {
      return const _ProcessingIndicator();
    }

    final rec = controller.isRecording;
    return FilledButton.icon(
      onPressed: rec ? controller.stopRecording : controller.startRecording,
      style: FilledButton.styleFrom(
        backgroundColor: rec ? WSColors.avalancheRed : WSColors.glacierBlue,
        // Hauteur encore plus généreuse pour le bouton principal du module :
        // c'est LA cible critique en condition réelle (sommet, gants, fatigue).
        minimumSize: const Size(0, WSTouch.bigAction - 8),
        padding: const EdgeInsets.symmetric(
          horizontal: WSSpacing.xl,
          vertical: WSSpacing.md,
        ),
        textStyle: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      icon: Icon(
        rec ? Icons.stop_circle_outlined : Icons.mic,
        size: 28,
      ),
      label: Text(rec ? 'Stop' : 'Enregistrer une obs'),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  final SnowController controller;
  const _MoreMenu({required this.controller});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20, color: WSColors.slateDark),
      tooltip: 'Actions',
      onSelected: (action) async {
        switch (action) {
          case 'process':
            await controller.processPending();
            break;
          case 'review':
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReviewScreen()),
            );
            break;
          case 'share_on':
            await controller.setShareWithCommunity(true);
            break;
          case 'share_off':
            await controller.setShareWithCommunity(false);
            break;
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'process',
          child: Row(children: [
            Icon(Icons.auto_awesome, size: 18, color: WSColors.glacierBlue),
            SizedBox(width: 12),
            Text('Traiter les obs en attente'),
          ]),
        ),
        const PopupMenuItem(
          value: 'review',
          child: Row(children: [
            Icon(Icons.list_alt, size: 18, color: WSColors.slateDark),
            SizedBox(width: 12),
            Text('Voir toutes les observations'),
          ]),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: controller.shareWithCommunity ? 'share_off' : 'share_on',
          child: Row(children: [
            Icon(
              controller.shareWithCommunity
                  ? Icons.public_off_outlined
                  : Icons.public_outlined,
              size: 18,
              color: WSColors.slateDark,
            ),
            const SizedBox(width: 12),
            Text(
              controller.shareWithCommunity
                  ? 'Désactiver le partage'
                  : 'Activer le partage communautaire',
            ),
          ]),
        ),
      ],
    );
  }
}

/// Toggle "mains libres" — active/désactive l'écoute du wake word.
/// Si le code natif Android n'est pas en place, le toggle reste activable
/// mais affiche une erreur explicite au tap.
class _HandsFreeToggle extends StatelessWidget {
  final SnowController controller;
  const _HandsFreeToggle({required this.controller});

  @override
  Widget build(BuildContext context) {
    final on = controller.handsFreeEnabled;
    return InkWell(
      borderRadius: BorderRadius.circular(WSRadius.md),
      onTap: () async {
        if (on) {
          await controller.disableHandsFree();
        } else {
          final ok = await controller.enableHandsFree();
          if (!ok && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text(controller.statusMessage.isEmpty
                  ? 'Wake word indisponible'
                  : controller.statusMessage),
            ));
          }
        }
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: WSTouch.primaryHeight),
        padding: const EdgeInsets.symmetric(
          horizontal: WSSpacing.md,
          vertical: WSSpacing.md,
        ),
        decoration: BoxDecoration(
          color: on
              ? WSColors.glacierBlueBg
              : WSColors.glacierLight,
          borderRadius: BorderRadius.circular(WSRadius.md),
          border: Border.all(
            color: on
                ? WSColors.glacierBlue
                : WSColors.glacierMid,
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              on ? Icons.hearing : Icons.hearing_disabled,
              size: 24,
              color: on ? WSColors.glacierBlue : WSColors.stoneGray,
            ),
            const SizedBox(width: WSSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    on ? 'Mains libres actif' : 'Activer mains libres',
                    style: WSText.body.copyWith(
                      fontWeight: FontWeight.w500,
                      color: on ? WSColors.glacierBlue : WSColors.slateDark,
                    ),
                  ),
                  Text(
                    on
                        ? '« hey snowy » pour démarrer · « bye bye snowy » pour stopper'
                        : 'Wake word pour mains libres en course',
                    style: WSText.micro.copyWith(
                      color: on ? WSColors.glacierBlue : WSColors.stoneGray,
                    ),
                  ),
                ],
              ),
            ),
            // Switch en mode visuel uniquement — le tap global sur la
            // rangée gère le toggle via onTap du InkWell.
            IgnorePointer(
              child: Switch(
                value: on,
                activeColor: WSColors.glacierBlue,
                onChanged: (_) {},
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProcessingIndicator extends StatelessWidget {
  const _ProcessingIndicator();
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
            width: 14, height: 14,
            child: CircularProgressIndicator(strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(WSColors.glacierBlue)),
          ),
          SizedBox(width: WSSpacing.sm),
          Text('Traitement IA…',
              style: TextStyle(fontSize: 12, color: WSColors.glacierBlue)),
        ],
      ),
    );
  }
}
