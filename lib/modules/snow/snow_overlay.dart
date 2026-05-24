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
import '../../core/theme/snow_palette.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../community/community_controller.dart';
import 'edit_observation_screen.dart';
import 'models/observation.dart';
import 'quick_observation_sheet.dart';
import 'review_screen.dart';
import 'snow_controller.dart';

/// Filtre d'affichage : quelles obs montrer sur la carte.
enum ObsViewFilter { mine, community, all }

/// État partagé du module Obs : filtre source + filtre temporel + filtre types.
///
/// Singleton, persiste entre rebuilds. Le filtre temporel s'applique aux deux
/// sources (mes obs ET communauté). Le filtre types également.
class _ObsViewState extends ChangeNotifier {
  static final _ObsViewState _instance = _ObsViewState._();
  factory _ObsViewState() => _instance;
  _ObsViewState._();

  // ── Source ──────────────────────────────────────────────────────────────
  ObsViewFilter _filter = ObsViewFilter.all;
  ObsViewFilter get filter => _filter;
  set filter(ObsViewFilter f) {
    if (f == _filter) return;
    _filter = f;
    notifyListeners();
  }

  // ── Fenêtre temporelle (jours) ──────────────────────────────────────────
  /// Nombre de jours en arrière à afficher. 1 = J, 7 = J-7, etc.
  /// 0 (cas spécial) = "Toutes" (pas de filtre temporel).
  int _windowDays = 7;
  int get windowDays => _windowDays;
  void setWindowDays(int days) {
    final clamped = days.clamp(0, 90);
    if (clamped == _windowDays) return;
    _windowDays = clamped;
    notifyListeners();

    // Propager au CommunityController pour qu'il re-fetche les obs Supabase
    // sur cette nouvelle fenêtre. "0" (Tout) → 90 jours côté serveur (max).
    final commWindow = clamped == 0 ? 90 : clamped;
    CommunityController().setWindowDays(commWindow);
  }

  /// Date limite en deçà de laquelle les obs sont masquées.
  /// Null si pas de filtre (windowDays == 0).
  DateTime? get sinceCutoff {
    if (_windowDays == 0) return null;
    return DateTime.now().subtract(Duration(days: _windowDays));
  }

  // ── Types de neige sélectionnés ─────────────────────────────────────────
  final Set<String> _selectedTypes = {};
  Set<String> get selectedTypes => Set.unmodifiable(_selectedTypes);

  bool isTypeSelected(String type) => _selectedTypes.contains(type);

  void toggleType(String type) {
    if (_selectedTypes.contains(type)) {
      _selectedTypes.remove(type);
    } else {
      _selectedTypes.add(type);
    }
    notifyListeners();
  }

  void clearTypeFilter() {
    if (_selectedTypes.isEmpty) return;
    _selectedTypes.clear();
    notifyListeners();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  /// Applique tous les filtres (temporel + types) à une liste d'obs.
  List<Observation> apply(List<Observation> source) {
    final cutoff = sinceCutoff;
    final types = _selectedTypes;
    return source.where((o) {
      if (cutoff != null && o.timestamp.isBefore(cutoff)) return false;
      if (types.isNotEmpty &&
          (o.snowType == null || !types.contains(o.snowType))) {
        return false;
      }
      return true;
    }).toList();
  }
}

class SnowModuleOverlay extends MapModuleOverlay {
  final SnowController       controller          = SnowController();
  final CommunityController  communityController = CommunityController();
  final _ObsViewState        viewState           = _ObsViewState();

  @override
  ModuleId get id => ModuleId.snow;

  @override
  List<Widget> buildMapLayers(BuildContext context) {
    return [
      _ObservationsLayer(
        controller: controller,
        communityController: communityController,
        viewState: viewState,
      ),
    ];
  }

  @override
  Widget? buildActionPanel(BuildContext context) {
    return _SnowActionPanel(
      controller: controller,
      communityController: communityController,
      viewState: viewState,
    );
  }
}

// ─── Layer pins ──────────────────────────────────────────────────────────────

class _ObservationsLayer extends StatelessWidget {
  final SnowController controller;
  final CommunityController communityController;
  final _ObsViewState viewState;

  const _ObservationsLayer({
    required this.controller,
    required this.communityController,
    required this.viewState,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(
          [controller, communityController, viewState]),
      builder: (context, _) {
        final filter = viewState.filter;
        final showMine = filter != ObsViewFilter.community;
        final showCommunity = filter != ObsViewFilter.mine;

        // Source brute selon le toggle Mes/Comm/Toutes
        final mineRaw = showMine ? controller.observations : <Observation>[];
        final commRaw = showCommunity
            ? communityController.filtered // déjà dédoublonné côté community
            : <Observation>[];

        // Application des filtres temporel + types (state partagé)
        final mine = viewState.apply(mineRaw);
        final comm = viewState.apply(commRaw);

        if (mine.isEmpty && comm.isEmpty) return const SizedBox.shrink();

        return MarkerLayer(
          markers: [
            // Obs de la communauté en dessous (anneaux discrets)
            for (final o in comm)
              Marker(
                point: o.latLng,
                width: 44,
                height: 44,
                alignment: Alignment.center,
                child: _CommunityMarker(
                  obs: o,
                  onTap: () => _openCommunityDetail(context, o),
                ),
              ),
            // Mes obs au-dessus (disques pleins)
            for (final o in mine)
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

  void _openCommunityDetail(BuildContext context, Observation obs) {
    // Réutilise la même bottom sheet que mes obs, mais sans bouton Édition.
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ObservationDetailSheet(obs: obs, readOnly: true),
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
    final color = SnowPalette.colorForUserType(obs.snowType);
    final isPending = !obs.isEnriched; // pas encore passé par l'IA

    // Marqueur en forme de flocon — clin d'œil à Hey Snowy.
    // Disque plein coloré avec un flocon blanc centré pour TES obs (= "à moi"),
    // contre un anneau coloré avec flocon coloré pour les obs Community.
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Halo discret pour qu'on repère le pin dans le décor topo
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.18),
              shape: BoxShape.circle,
            ),
          ),
          // Cœur du pin : disque plein coloré, bord blanc.
          // Si l'IA n'a pas encore traité l'observation, on affiche un disque
          // blanc avec bord gris + flocon gris (pour signaler "en cours").
          Container(
            width: 22, height: 22,
            decoration: BoxDecoration(
              color: isPending ? WSColors.snowWhite : color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isPending ? WSColors.stoneGray : WSColors.snowWhite,
                width: 2,
              ),
            ),
            child: Icon(
              Icons.ac_unit,
              size: 13,
              color: isPending ? WSColors.stoneGray : WSColors.snowWhite,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pin pour une obs **communauté**.
/// Anneau coloré (fond blanc + bord coloré) avec flocon coloré au centre.
/// Visuellement distinct du _ObservationMarker (disque plein) pour qu'on
/// reconnaisse au premier coup d'œil que ce n'est pas une obs perso.
class _CommunityMarker extends StatelessWidget {
  final Observation obs;
  final VoidCallback onTap;
  const _CommunityMarker({required this.obs, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = SnowPalette.colorForUserType(obs.snowType);
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
          ),
          Container(
            width: 20, height: 20,
            decoration: BoxDecoration(
              color: WSColors.snowWhite,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2.5),
            ),
            child: Icon(Icons.ac_unit, size: 11, color: color),
          ),
        ],
      ),
    );
  }
}

// ─── Bottom sheet de détail ──────────────────────────────────────────────────

class _ObservationDetailSheet extends StatelessWidget {
  final Observation obs;
  /// Controller pour les actions (édition, suppression).
  /// Null = mode lecture seule (cas obs communauté).
  final SnowController? controller;
  final bool readOnly;

  const _ObservationDetailSheet({
    required this.obs,
    this.controller,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = SnowPalette.colorForUserType(obs.snowType);
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
              if (!readOnly) ...[
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
                    await controller?.deleteObservation(obs);
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              ],
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
  final CommunityController communityController;
  final _ObsViewState viewState;

  const _SnowActionPanel({
    required this.controller,
    required this.communityController,
    required this.viewState,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(
          [controller, communityController, viewState]),
      builder: (context, _) {
        // start() est idempotent → safe à chaque rebuild
        controller.start();
        communityController.start();

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
              // ─── Chip filtres (fenêtre temporelle + types) ──────────────
              _FilterChip(viewState: viewState),
              const SizedBox(height: WSSpacing.sm),

              // ─── Toggle : Mes / Communauté / Toutes ─────────────────────
              // Les compteurs reflètent l'effet des filtres en cours pour
              // que l'utilisateur voie immédiatement combien d'obs passent.
              _ViewToggle(
                state: viewState,
                mineCount: viewState.apply(controller.observations).length,
                commCount: viewState.apply(communityController.filtered).length,
              ),
              const SizedBox(height: WSSpacing.sm),

              _StatusLine(controller: controller),
              const SizedBox(height: WSSpacing.sm),
              _HandsFreeToggle(controller: controller),
              const SizedBox(height: WSSpacing.sm),

              // ─── Deux boutons : Saisie rapide + Vocale ──────────────────
              Row(
                children: [
                  Expanded(
                    child: _QuickButton(),
                  ),
                  const SizedBox(width: WSSpacing.sm),
                  Expanded(
                    flex: 2,
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

/// Toggle 3 segments : Mes obs / Communauté / Toutes (par défaut).
/// Affiche le nombre d'obs dans chaque segment pour donner un retour.
class _ViewToggle extends StatelessWidget {
  final _ObsViewState state;
  final int mineCount;
  final int commCount;

  const _ViewToggle({
    required this.state,
    required this.mineCount,
    required this.commCount,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ObsViewFilter>(
      segments: [
        ButtonSegment(
          value: ObsViewFilter.mine,
          label: Text('Mes ($mineCount)'),
          icon: const Icon(Icons.person_outline, size: 16),
        ),
        ButtonSegment(
          value: ObsViewFilter.community,
          label: Text('Comm. ($commCount)'),
          icon: const Icon(Icons.people_outline, size: 16),
        ),
        const ButtonSegment(
          value: ObsViewFilter.all,
          label: Text('Toutes'),
          icon: Icon(Icons.layers_outlined, size: 16),
        ),
      ],
      selected: {state.filter},
      onSelectionChanged: (s) => state.filter = s.first,
      style: SegmentedButton.styleFrom(
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        visualDensity: VisualDensity.compact,
      ),
      showSelectedIcon: false,
    );
  }
}

/// Bouton "Saisie rapide" : ouvre le bottom sheet pour créer une obs au point
/// GPS actuel sans audio. Plus petit que le bouton micro principal.
class _QuickButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => QuickObservationSheet.show(context),
      icon: const Icon(Icons.add_location_alt_outlined, size: 20),
      label: const Text('Rapide'),
      style: OutlinedButton.styleFrom(
        foregroundColor: WSColors.glacierBlue,
        side: const BorderSide(color: WSColors.glacierBlue, width: 1.0),
        minimumSize: const Size(0, WSTouch.bigAction - 8),
        padding: const EdgeInsets.symmetric(
          horizontal: WSSpacing.sm,
          vertical: WSSpacing.md,
        ),
        textStyle:
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Chip qui résume les filtres actifs (fenêtre temporelle + types).
/// Tap → ouvre une bottom sheet pour modifier les filtres.
///
/// Affichage : "J-7 · Tous types" ou "J-3 · 4 types" ou "Tout · Tous types".
class _FilterChip extends StatelessWidget {
  final _ObsViewState viewState;
  const _FilterChip({required this.viewState});

  @override
  Widget build(BuildContext context) {
    final days = viewState.windowDays;
    final n = viewState.selectedTypes.length;

    final windowLabel = switch (days) {
      0 => 'Tout',
      1 => 'J',
      _ => 'J-$days',
    };
    final typesLabel = n == 0 ? 'Tous types' : '$n type${n > 1 ? "s" : ""}';

    final isFiltering = days != 0 || n > 0;

    return InkWell(
      onTap: () => _ObsFilterSheet.show(context, viewState),
      borderRadius: BorderRadius.circular(WSRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: WSSpacing.md,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: isFiltering
              ? WSColors.glacierBlue.withOpacity(0.10)
              : WSColors.glacierLight,
          borderRadius: BorderRadius.circular(WSRadius.pill),
          border: Border.all(
            color: isFiltering
                ? WSColors.glacierBlue.withOpacity(0.4)
                : WSColors.glacierMid,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_list,
              size: 14,
              color: isFiltering ? WSColors.glacierBlue : WSColors.stoneGray,
            ),
            const SizedBox(width: 6),
            Text(
              '$windowLabel  ·  $typesLabel',
              style: WSText.micro.copyWith(
                color: isFiltering
                    ? WSColors.glacierBlue
                    : WSColors.slateDark,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down,
              size: 14,
              color: isFiltering ? WSColors.glacierBlue : WSColors.stoneGray,
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet de filtres : fenêtre temporelle + multi-select des types.
class _ObsFilterSheet extends StatelessWidget {
  final _ObsViewState viewState;
  const _ObsFilterSheet({required this.viewState});

  static const _windowOptions = <(int, String)>[
    (1,  'J'),
    (3,  'J-3'),
    (7,  'J-7'),
    (14, 'J-14'),
    (30, 'J-30'),
    (0,  'Tout'),
  ];

  static const _allTypes = <String>[
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

  static Future<void> show(BuildContext context, _ObsViewState state) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ObsFilterSheet(viewState: state),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: viewState,
      builder: (context, _) => Container(
        decoration: const BoxDecoration(
          color: WSColors.snowWhite,
          borderRadius: BorderRadius.vertical(top: Radius.circular(WSRadius.lg)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              WSSpacing.lg, WSSpacing.md, WSSpacing.lg, WSSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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

                // ─── Fenêtre temporelle ─────────────────────────────────
                Text(
                  'Période',
                  style: WSText.heading.copyWith(fontSize: 16),
                ),
                const SizedBox(height: WSSpacing.xs),
                Text(
                  'Afficher les observations des derniers jours.',
                  style: WSText.micro.copyWith(color: WSColors.stoneGray),
                ),
                const SizedBox(height: WSSpacing.md),
                Wrap(
                  spacing: WSSpacing.sm,
                  runSpacing: WSSpacing.sm,
                  children: _windowOptions.map((opt) {
                    final days = opt.$1;
                    final label = opt.$2;
                    final sel = viewState.windowDays == days;
                    return _SmallChip(
                      label: label,
                      selected: sel,
                      onTap: () => viewState.setWindowDays(days),
                    );
                  }).toList(),
                ),

                const SizedBox(height: WSSpacing.lg),
                const Divider(color: WSColors.glacierMid, height: 1),
                const SizedBox(height: WSSpacing.md),

                // ─── Types de neige ─────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Types de neige',
                      style: WSText.heading.copyWith(fontSize: 16),
                    ),
                    if (viewState.selectedTypes.isNotEmpty)
                      TextButton(
                        onPressed: viewState.clearTypeFilter,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Effacer',
                          style: WSText.micro.copyWith(
                            color: WSColors.glacierBlue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: WSSpacing.xs),
                Text(
                  viewState.selectedTypes.isEmpty
                      ? 'Aucun filtre : tous les types sont affichés.'
                      : 'Seuls les types cochés seront affichés.',
                  style: WSText.micro.copyWith(color: WSColors.stoneGray),
                ),
                const SizedBox(height: WSSpacing.md),
                Wrap(
                  spacing: WSSpacing.sm,
                  runSpacing: WSSpacing.sm,
                  children: _allTypes.map((t) {
                    final color = SnowPalette.colorForUserType(t);
                    final sel = viewState.isTypeSelected(t);
                    return _SmallChip(
                      label: t,
                      selected: sel,
                      color: color,
                      onTap: () => viewState.toggleType(t),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Chip réutilisable pour la sheet (fenêtre + types).
class _SmallChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;

  const _SmallChip({
    required this.label,
    required this.selected,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = color ?? WSColors.glacierBlue;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(WSRadius.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: WSSpacing.md,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          color: selected ? accent : WSColors.glacierLight,
          borderRadius: BorderRadius.circular(WSRadius.lg),
          border: Border.all(
            color: selected ? accent : WSColors.glacierMid,
            width: selected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (color != null && !selected) ...[
              Container(
                width: 9, height: 9,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: WSText.body.copyWith(
                fontSize: 13,
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
      label: Text(rec ? 'Stop' : 'Obs vocale'),
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
