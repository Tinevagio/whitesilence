// lib/modules/ideas/ideas_overlay.dart
//
// Overlay du module Idées sur la WSMapScreen.
//
// Composition :
//   - buildMapLayers : pins numérotés sur les sommets retournés
//   - buildActionPanel : header replié/déplié avec résumé filtres + bouton
//   - buildBottomSheet : carousel horizontal des cards (au-dessus de la carte)

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../core/map/map_module_overlay.dart';
import '../../core/module_registry.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import 'ideas_controller.dart';
import 'models/idea.dart';
import 'widgets/idea_card.dart';
import 'widgets/idea_detail_sheet.dart';
import 'widgets/idea_pin.dart';
import 'widgets/ideas_filters_sheet.dart';

class IdeasModuleOverlay extends MapModuleOverlay {
  final IdeasController controller = IdeasController();

  IdeasModuleOverlay() {
    // Répercute les notifs au shell pour rebuild
    controller.addListener(notifyListeners);
  }

  @override
  ModuleId get id => ModuleId.ideas;

  @override
  List<Widget> buildMapLayers(BuildContext context) {
    // Idempotent : ping cold start backend + chargement métadonnées
    controller.start();
    return [
      _IdeaPinsLayer(controller: controller),
    ];
  }

  @override
  Widget? buildActionPanel(BuildContext context) {
    return _IdeasActionPanel(controller: controller);
  }

  @override
  Widget? buildBottomSheet(BuildContext context) {
    // Carousel horizontal des cards (au-dessus de la carte).
    // N'apparaît que si on a des résultats.
    return _IdeasCardsCarousel(controller: controller);
  }
}

// ─── Layer : pins sur la carte ───────────────────────────────────────────────

class _IdeaPinsLayer extends StatelessWidget {
  final IdeasController controller;
  const _IdeaPinsLayer({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // On affiche les pins des idées EFFECTIVEMENT visibles (post-filtre
        // des masqués), pour qu'index pin = index card côté carousel.
        final ideas = controller.displayedIdeas;
        if (ideas.isEmpty) return const SizedBox.shrink();
        return MarkerLayer(
          markers: [
            for (int i = 0; i < ideas.length; i++)
              Marker(
                point: ideas[i].latLng,
                width: 44, height: 44,
                alignment: Alignment.center,
                child: IdeaPin(
                  index: i + 1,
                  selected: controller.selectedIndex == i,
                  onTap: () => controller.selectIdea(i),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─── Action panel : header replié/déplié ────────────────────────────────────

class _IdeasActionPanel extends StatefulWidget {
  final IdeasController controller;
  const _IdeasActionPanel({required this.controller});

  @override
  State<_IdeasActionPanel> createState() => _IdeasActionPanelState();
}

class _IdeasActionPanelState extends State<_IdeasActionPanel> {
  bool _collapsed = false;

  void _openFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => IdeasFiltersSheet(controller: widget.controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
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
              // Header (toujours visible)
              InkWell(
                onTap: () => setState(() => _collapsed = !_collapsed),
                borderRadius: BorderRadius.circular(WSRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.lightbulb_outline,
                          size: 18, color: WSColors.slateDark),
                      const SizedBox(width: WSSpacing.sm),
                      const Text('Idées', style: WSText.title),
                      const SizedBox(width: WSSpacing.sm),
                      if (_collapsed)
                        Expanded(
                          child: _CollapsedSummary(controller: controller),
                        ),
                      if (!_collapsed) const Spacer(),
                      Icon(
                        _collapsed ? Icons.expand_less : Icons.expand_more,
                        size: 24,
                        color: WSColors.slateDark,
                      ),
                    ],
                  ),
                ),
              ),
              if (!_collapsed) ...[
                const SizedBox(height: WSSpacing.sm),
                // Résumé filtres
                Text(controller.filter.compactSummary,
                  style: WSText.micro.copyWith(color: WSColors.stoneGray)),
                const SizedBox(height: WSSpacing.sm),
                // Status + alertes météo globales
                _StatusLine(controller: controller),
                if (controller.lastResponse != null &&
                    controller.lastResponse!.weatherAlerts.isNotEmpty) ...[
                  const SizedBox(height: WSSpacing.sm),
                  for (final a in controller.lastResponse!.weatherAlerts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(a, style: WSText.micro),
                    ),
                ],
                const SizedBox(height: WSSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openFilters,
                        icon: const Icon(Icons.tune, size: 18),
                        label: const Text('Filtres'),
                      ),
                    ),
                    const SizedBox(width: WSSpacing.sm),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: controller.status == IdeasStatus.loading
                            ? null
                            : controller.search,
                        icon: controller.status == IdeasStatus.loading
                            ? const SizedBox(
                                width: 14, height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.8,
                                  valueColor: AlwaysStoppedAnimation(
                                      WSColors.snowWhite),
                                ),
                              )
                            : const Icon(Icons.search, size: 18),
                        label: Text(controller.lastResponse == null
                            ? 'Trouver'
                            : 'Relancer'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Résumé compact pour l'état replié.
class _CollapsedSummary extends StatelessWidget {
  final IdeasController controller;
  const _CollapsedSummary({required this.controller});

  @override
  Widget build(BuildContext context) {
    final n = controller.displayedIdeas.length;
    final text = n > 0
        ? '$n résultat${n > 1 ? "s" : ""}'
        : controller.filter.compactSummary;
    return Text(
      text,
      style: WSText.micro.copyWith(
          color: WSColors.stoneGray, fontWeight: FontWeight.w500),
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _StatusLine extends StatelessWidget {
  final IdeasController controller;
  const _StatusLine({required this.controller});

  @override
  Widget build(BuildContext context) {
    String text;
    Color color = WSColors.stoneGray;
    IconData icon = Icons.info_outline;

    switch (controller.status) {
      case IdeasStatus.idle:
        text = 'Configure les filtres et lance la recherche.';
        break;
      case IdeasStatus.warming:
        text = 'Backend en cours de réveil…';
        color = WSColors.glacierBlue;
        icon = Icons.cloud_sync_outlined;
        break;
      case IdeasStatus.metadataLoading:
        text = 'Chargement des massifs disponibles…';
        color = WSColors.glacierBlue;
        break;
      case IdeasStatus.loading:
        text = 'Recherche en cours (peut prendre 1-2 min)…';
        color = WSColors.glacierBlue;
        icon = Icons.search;
        break;
      case IdeasStatus.ready:
        final nBackend = controller.lastResponse?.ideas.length ?? 0;
        final nShown = controller.displayedIdeas.length;
        final saison = controller.lastResponse?.saison ?? '';
        if (nShown == 0 && nBackend > 0) {
          // Backend a trouvé des idées mais elles sont toutes masquées
          text = 'Toutes les idées trouvées sont masquées. '
                 'Active "Voir les sorties masquées" dans les filtres.';
          color = WSColors.sunOrange;
          icon = Icons.visibility_off;
        } else {
          text = '$nShown idée${nShown > 1 ? "s" : ""} pour $saison';
          color = WSColors.powderGreen;
          icon = Icons.check_circle_outline;
        }
        break;
      case IdeasStatus.empty:
        text = 'Aucun itinéraire ne correspond à tes filtres.';
        color = WSColors.sunOrange;
        icon = Icons.search_off;
        break;
      case IdeasStatus.error:
        text = controller.errorMessage ?? 'Erreur inconnue';
        color = WSColors.avalancheRed;
        icon = Icons.error_outline;
        break;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: WSSpacing.sm),
        Expanded(child: Text(text,
            style: WSText.caption.copyWith(color: color))),
      ],
    );
  }
}

// ─── Carousel horizontal des cards ──────────────────────────────────────────

class _IdeasCardsCarousel extends StatefulWidget {
  final IdeasController controller;
  const _IdeasCardsCarousel({required this.controller});

  @override
  State<_IdeasCardsCarousel> createState() => _IdeasCardsCarouselState();
}

class _IdeasCardsCarouselState extends State<_IdeasCardsCarousel> {
  PageController? _pageCtrl;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _pageCtrl?.dispose();
    super.dispose();
  }

  /// Quand le controller change la sélection (tap sur un pin), on scrolle
  /// le carousel pour faire apparaître la card correspondante.
  void _onControllerChanged() {
    final idx = widget.controller.selectedIndex;
    if (idx < 0) return;
    final ctrl = _pageCtrl;
    if (ctrl == null || !ctrl.hasClients) return;
    final currentPage = ctrl.page?.round() ?? 0;
    if (currentPage != idx) {
      ctrl.animateToPage(
        idx,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
  }

  void _openDetail(Idea idea) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => IdeaDetailSheet(idea: idea),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final ideas = widget.controller.displayedIdeas;
        if (ideas.isEmpty) return const SizedBox.shrink();
        _pageCtrl ??= PageController(
          viewportFraction: 0.86,
          initialPage: widget.controller.selectedIndex.clamp(0, ideas.length - 1),
        );

        return SizedBox(
          height: 165,
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: ideas.length,
            onPageChanged: widget.controller.selectIdea,
            itemBuilder: (context, i) => IdeaCard(
              idea: ideas[i],
              index: i + 1,
              selected: widget.controller.selectedIndex == i,
              onTap: () => _openDetail(ideas[i]),
            ),
          ),
        );
      },
    );
  }
}
