// lib/modules/conditions/conditions_overlay.dart
//
// Overlay du module Conditions sur la WSMapScreen.
//
// - Layers :
//     * CircleMarkerLayer pour la grille (couleur = condition à l'heure sel.)
//     * (rien d'autre ici — le chip BERA est dans l'action panel, pas un layer)
// - Tap court : récupère le détail du point et ouvre le bottom sheet
// - Action panel : statut + slider d'heure + chip BERA + bouton refresh

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/gps/gps_service.dart';
import '../../core/map/map_module_overlay.dart';
import '../../core/module_navigator.dart';
import '../../core/module_registry.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/snow_palette.dart';
import 'bera_detail_screen.dart';
import 'conditions_date_chip.dart';
import '../../core/theme/typography.dart';
import 'condition_detail_sheet.dart';
import 'conditions_controller.dart';
import 'models/condition_code.dart';
import 'models/point_conditions.dart';

/// État global du drag du slider d'heure.
/// Le slider est rendu en haut de la carte (sortie du panel pour éviter
/// les problèmes de doigt qui dérape pendant le drag). L'action panel
/// observe cet état pour se masquer pendant le drag, libérant ainsi
/// l'espace de la carte pour voir les points évoluer.
final ValueNotifier<bool> _hourSliderDragging = ValueNotifier(false);

class ConditionsModuleOverlay extends MapModuleOverlay {
  final ConditionsController controller = ConditionsController();

  ConditionsModuleOverlay() {
    // On répercute les notifications du controller pour que la WSMapScreen
    // (qui écoute l'overlay) rebuild quand le mode dessin change.
    controller.addListener(notifyListeners);
  }

  @override
  ModuleId get id => ModuleId.conditions;

  /// En mode dessin : on désactive tous les gestes de la carte pour que le
  /// _DragCanvas posé par-dessus capte le drag sans conflit.
  @override
  InteractionOptions? get interactionOptions =>
      controller.isDrawing ? const InteractionOptions(flags: InteractiveFlag.none) : null;

  /// Quand on est en mode dessin, on expose un handler qui route vers le
  /// controller. Sinon null → pas de _DragCanvas posé.
  @override
  MapDragHandler? get dragHandler =>
      controller.isDrawing ? _ConditionsDragHandler(controller) : null;

  @override
  List<Widget> buildMapLayers(BuildContext context) {
    // start() est idempotent
    controller.start();

    // Si une autre partie de l'app (typiquement Idées via ModuleNavigator)
    // a demandé d'afficher Conditions sur une bbox précise, on la consomme
    // ici. Fire-and-forget : le fetch tournera en background.
    final pending = ModuleNavigator().pendingConditionsBbox;
    if (pending != null) {
      controller.fetchGrid(pending.sw, pending.ne, force: true);
      controller.fetchBeraFor(LatLng(
        (pending.sw.latitude  + pending.ne.latitude)  / 2,
        (pending.sw.longitude + pending.ne.longitude) / 2,
      ));
    }

    return [
      // Heatmap d'enneigement EN PREMIER (sous tout le reste) — c'est un
      // calque de fond qui colore la zone sans masquer les points.
      _SnowHeatmapLayer(controller: controller),
      _GridLayer(controller: controller),
      _AvalancheLayer(controller: controller),
      _BestWindowLayer(controller: controller),
      _DrawnBboxLayer(controller: controller),
    ];
  }

  @override
  bool onMapTap(BuildContext context, TapPosition tapPosition, LatLng latLng) {
    // En mode dessin, le _DragCanvas capte les events — on ne devrait pas
    // arriver ici. Sécurité.
    if (controller.isDrawing) return true;
    _openDetail(context, latLng);
    return true; // tap consommé
  }

  Future<void> _openDetail(BuildContext context, LatLng latLng) async {
    final messenger = ScaffoldMessenger.of(context);
    final point = await controller.fetchPointDetail(latLng);
    if (point == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Aucune donnée pour ce point'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ConditionDetailSheet(
        point: point,
        selectedHour: controller.selectedHourUtc,
      ),
    );
  }

  @override
  Widget? buildActionPanel(BuildContext context) {
    return _ConditionsActionPanel(
      controller: controller,
      onFetchHere: () => _fetchHere(context),
    );
  }

  /// Top chrome : chip de sélection de date toujours visible + slider d'heure
  /// quand on a une grille chargée.
  ///
  /// Le chip de date est **toujours** affiché (même sans grille) car c'est un
  /// paramètre de planification : l'utilisateur peut vouloir choisir une date
  /// future avant de demander les conditions ("je veux savoir samedi").
  ///
  /// Le slider d'heure n'apparaît qu'une fois la grille fetchée (sinon il n'a
  /// rien à animer).
  @override
  Widget? buildTopChrome(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final children = <Widget>[
          ConditionsDateChip(controller: controller),
        ];
        if (controller.grid != null) {
          children.add(const SizedBox(height: WSSpacing.xs));
          children.add(ConditionsHourSlider(controller: controller));
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
      },
    );
  }

  /// Fetch la grille pour une zone de ~5 km autour de la position GPS courante.
  /// (Plus tard on synchronisera avec le viewport visible de la carte.)
  Future<void> _fetchHere(BuildContext context) async {
    final gps = GpsService().lastLatLng;
    if (gps == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Position GPS indisponible'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    const halfDeg = 0.025; // ~2.5 km à 45°N
    final sw = LatLng(gps.latitude - halfDeg, gps.longitude - halfDeg);
    final ne = LatLng(gps.latitude + halfDeg, gps.longitude + halfDeg);
    await controller.fetchGrid(sw, ne, force: true);
    await controller.fetchBeraFor(gps);
  }
}

// ─── Drag handler (mode dessin de bbox) ──────────────────────────────────────

class _ConditionsDragHandler implements MapDragHandler {
  final ConditionsController controller;
  _ConditionsDragHandler(this.controller);

  @override
  void onDragStart(LatLng start) => controller.onDrawStart(start);
  @override
  void onDragUpdate(LatLng current) => controller.onDrawUpdate(current);
  @override
  void onDragEnd(LatLng end) => controller.onDrawEnd(end);
}

// ─── Layer rectangle dessiné ─────────────────────────────────────────────────

/// Affiche le rectangle pendant ET après le dessin, tant qu'on a une grille.
/// Pendant le dessin : un rectangle pointillé. Après : un rectangle plein
/// très discret pour marquer la zone analysée.
class _DrawnBboxLayer extends StatelessWidget {
  final ConditionsController controller;
  const _DrawnBboxLayer({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final box = controller.drawnBbox;
        if (box == null) return const SizedBox.shrink();

        final isDrawing = controller.isDrawing;
        final points = [
          box.sw,
          LatLng(box.sw.latitude, box.ne.longitude),
          box.ne,
          LatLng(box.ne.latitude, box.sw.longitude),
        ];

        return PolygonLayer(polygons: [
          Polygon(
            points: points,
            color: WSColors.glacierBlue.withOpacity(isDrawing ? 0.10 : 0.04),
            borderColor: WSColors.glacierBlue.withOpacity(isDrawing ? 0.9 : 0.5),
            borderStrokeWidth: isDrawing ? 2.0 : 1.0,
          ),
        ]);
      },
    );
  }
}

// ─── Layer grille ────────────────────────────────────────────────────────────

class _GridLayer extends StatelessWidget {
  final ConditionsController controller;
  const _GridLayer({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // On affiche TOUS les points cumulés (toutes les bbox dessinées
        // dans la session), pas seulement ceux de la dernière fetch.
        final points = controller.accumulatedPoints;
        if (points.isEmpty) return const SizedBox.shrink();

        final hour = controller.selectedHourUtc;
        // Taille alignée avec le frontend Netlify (.sm en CSS = 11px de
        // diamètre soit 5.5px de rayon). Pas de scale au zoom : la densité
        // de la grille (500m) reste lisible sur tous les niveaux usuels.
        const radiusPx = 5.5;

        // Bord blanc semi-transparent → détache chaque point du fond topo
        // (sinon les marrons/oranges se confondent avec les courbes de niveau).
        // Reprise du style .sm Netlify : border:1.5px solid rgba(255,255,255,.75).
        final circles = <CircleMarker>[
          for (final p in points)
            CircleMarker(
              point: p.latLng,
              radius: radiusPx,
              color: _colorFor(p, hour),
              borderColor: Colors.white.withOpacity(0.75),
              borderStrokeWidth: 1.5,
            ),
        ];
        return CircleLayer(circles: circles);
      },
    );
  }

  Color _colorFor(PointConditions p, int hour) {
	  // Priorité 1 : "Pas de neige" — interpolation BERA déjà côté client.
	  // On l'évalue AVANT la condition normale car le backend peut renvoyer
	  // n'importe quel code (typiquement OLD_PACKED ou UNDEFINED) pour les
	  // points sous la limite d'enneigement, ce qui est trompeur.
	  if (p.isNoSnow) return SnowPalette.noSnowColor;

	  final h = p.conditionAt(hour);
	  if (h == null) return WSColors.glacierMid.withOpacity(0.4);
	  final meta = ConditionMeta.forCode(h.condition);
	  return meta.color;
	}
}

// ─── Layer avalanche ─────────────────────────────────────────────────────────

/// Affiche les cônes de propagation d'avalanche en rouge sur la carte,
/// ainsi que les zones de départ (points). Visible uniquement si
/// `controller.avalancheVisible` est true.
class _AvalancheLayer extends StatelessWidget {
  final ConditionsController controller;
  const _AvalancheLayer({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.avalancheVisible) return const SizedBox.shrink();
        final av = controller.avalanche;
        if (av == null) return const SizedBox.shrink();

        // Cônes de propagation : polygones colorés selon le niveau BERA
        // de la zone de départ (palette officielle Météo France).
        //   1 = jaune, 2 = orange clair, 3 = orange foncé, 4 = rouge, 5 = rouge foncé.
        // L'opacité de fond reste modulée légèrement par `severity` pour
        // donner du relief visuel quand plusieurs cônes du même risque se
        // chevauchent — mais c'est la couleur qui porte l'information de niveau.
        final polygons = <Polygon>[
          for (final cone in av.cones)
            Polygon(
              points:            cone.ring,
              color:             WSColors.beraColor(cone.risque)
                  .withOpacity(0.22 + (cone.severity.clamp(0, 1) * 0.18)),
              borderColor:       WSColors.beraColor(cone.risque)
                  .withOpacity(0.75),
              borderStrokeWidth: 1.0,
            ),
        ];

        // Zones de départ : marqueurs colorés selon le BERA aussi.
        final markers = <Marker>[
          for (final z in av.startZones)
            Marker(
              point:  z.point,
              width:  16,
              height: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: WSColors.beraColor(z.risque),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: WSColors.snowWhite,
                    width: 1.5,
                  ),
                ),
              ),
            ),
        ];

        return Stack(children: [
          PolygonLayer(polygons: polygons),
          MarkerLayer(markers: markers),
        ]);
      },
    );
  }
}

// ─── Layer best-window ───────────────────────────────────────────────────────

/// Affiche pour chaque point de la grille best-window soit l'heure idéale
/// poudreuse (jusqu'à ...), soit l'heure idéale moquette, soit les deux en
/// mosaïque. Couleur du marqueur = code couleur horaire.
class _BestWindowLayer extends StatelessWidget {
  final ConditionsController controller;
  const _BestWindowLayer({required this.controller});

  /// Couleur poudre selon l'heure : bleu foncé (tôt, 0h) → bleu clair (12h).
  /// Cohérent avec les tons froids attendus pour la neige fraîche.
  /// Port du frontend Netlify V7 `powderColor()`.
  static Color _powderColor(int hour) {
    final t = (hour.clamp(0, 12) / 12.0);
    final r = (10  + t * (126 - 10 )).round();
    final g = (46  + t * (200 - 46 )).round();
    final b = (92  + t * (227 - 92 )).round();
    return Color.fromARGB(255, r, g, b);
  }

  /// Couleur moquette selon l'heure : jaune doré (matin, 5h) → orange brun
  /// (fin d'après-midi, 18h). Tons chauds cohérents avec le soleil qui
  /// transforme la neige.
  /// Port du frontend Netlify V7 `springColor()`.
  static Color _springColor(int hour) {
    final t = (((hour - 5).clamp(0, 13)) / 13.0).clamp(0.0, 1.0);
    final r = (245 + t * (192 - 245)).round();
    final g = (200 + t * (82  - 200)).round();
    final b = (66  + t * (26  - 66 )).round();
    return Color.fromARGB(255, r, g, b);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.bestWindowVisible) return const SizedBox.shrink();
        final bw = controller.bestWindow;
        if (bw == null || bw.points.isEmpty) return const SizedBox.shrink();

        final mode = controller.bestWindowMode;
        final markers = <Marker>[];

        // Le mode "both" superpose les deux infos par point. Pour ne pas
        // surcharger visuellement, on n'affiche le label texte qu'en mode
        // simple (powder OU spring), pas en mode "both" où la couleur du
        // pin suffit (gain de lisibilité).
        final showLabel = mode != BestWindowMode.both;

        for (final p in bw.points) {
          if (!p.hasAnyWindow) continue;

          // Choix de l'heure à afficher selon le mode courant.
          int? labelHour;
          Color? color;
          bool isSpring = false;

          switch (mode) {
            case BestWindowMode.powder:
              if (p.powderUntilHour != null) {
                labelHour = p.powderUntilHour;
                color = _powderColor(labelHour!);
              }
              break;
            case BestWindowMode.spring:
              if (p.springOptimalHour != null) {
                labelHour = p.springOptimalHour;
                color = _springColor(labelHour!);
                isSpring = true;
              }
              break;
            case BestWindowMode.both:
              // En mode both : on ajoute DEUX marqueurs côte à côte pour ce
              // point — un poudre (bleu), un moquette (orange). Cela
              // demande une boucle séparée, pas le même flux que les modes
              // simples.
              if (p.powderUntilHour != null) {
                markers.add(_buildMarker(
                  point: p.point,
                  hour: p.powderUntilHour!,
                  color: _powderColor(p.powderUntilHour!),
                  showLabel: false,
                  isSmall: true,
                  isSpring: false,
                ));
              }
              if (p.springOptimalHour != null) {
                markers.add(_buildMarker(
                  point: p.point,
                  hour: p.springOptimalHour!,
                  color: _springColor(p.springOptimalHour!),
                  showLabel: false,
                  isSmall: true,
                  isSpring: true,
                ));
              }
              continue; // skip le code commun ci-dessous
          }

          if (labelHour == null || color == null) continue;
          markers.add(_buildMarker(
            point: p.point,
            hour: labelHour,
            color: color,
            showLabel: showLabel,
            isSmall: false,
            isSpring: isSpring,
          ));
        }

        return MarkerLayer(markers: markers);
      },
    );
  }

  /// Construit un marker : un rond coloré + (optionnel) une étiquette
  /// "HHh" en-dessous. Style inspiré du frontend Netlify V7.
  static Marker _buildMarker({
    required LatLng point,
    required int hour,
    required Color color,
    required bool showLabel,
    required bool isSmall,
    required bool isSpring,
  }) {
    final dotSize = isSmall ? 8.0 : 14.0;
    // Hauteur du marker = rond + (label sous le rond si affiché)
    final markerHeight = showLabel ? dotSize + 18 : dotSize;
    final markerWidth  = showLabel ? 40.0 : dotSize;

    return Marker(
      point: point,
      width: markerWidth,
      height: markerHeight,
      // Ancrage : le rond doit pointer la position exacte. Avec un label en
      // dessous, l'anchor reste au centre du rond (haut du widget).
      alignment: showLabel ? Alignment.topCenter : Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              color: color.withOpacity(isSpring ? 0.85 : 0.75),
              shape: BoxShape.circle,
              border: Border.all(
                color: isSpring
                    ? WSColors.slateDark.withOpacity(0.5)
                    : WSColors.snowWhite,
                width: 1.2,
              ),
            ),
          ),
          if (showLabel) ...[
            const SizedBox(height: 2),
            // Étiquette "HHh" avec un petit fond blanc semi-opaque pour
            // rester lisible sur fond de carte coloré.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: WSColors.snowWhite.withOpacity(0.88),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                '${hour.toString().padLeft(2, "0")}h',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: WSColors.slateDark,
                  height: 1.0,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Layer heatmap d'enneigement ─────────────────────────────────────────────

/// Affiche la heatmap d'enneigement comme une OverlayImage sur la carte,
/// avec l'opacité contrôlée par le slider de l'action panel.
class _SnowHeatmapLayer extends StatelessWidget {
  final ConditionsController controller;
  const _SnowHeatmapLayer({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.snowHeatmapVisible) return const SizedBox.shrink();
        final hm = controller.snowHeatmap;
        if (hm == null) return const SizedBox.shrink();
        return OverlayImageLayer(
          overlayImages: [
            OverlayImage(
              bounds:        LatLngBounds(hm.sw, hm.ne),
              imageProvider: MemoryImage(hm.pngBytes),
              opacity:       controller.snowHeatmapOpacity,
              gaplessPlayback: true,
            ),
          ],
        );
      },
    );
  }
}

// ─── Action panel ────────────────────────────────────────────────────────────

class _ConditionsActionPanel extends StatefulWidget {
  final ConditionsController controller;
  final VoidCallback onFetchHere;

  const _ConditionsActionPanel({
    required this.controller,
    required this.onFetchHere,
  });

  @override
  State<_ConditionsActionPanel> createState() => _ConditionsActionPanelState();
}

class _ConditionsActionPanelState extends State<_ConditionsActionPanel> {
  /// État replié/déplié. Persiste durant la session uniquement.
  /// Volontairement pas sauvé en préférences : à chaque retour sur le module
  /// on repart avec le panel ouvert, c'est plus clair.
  bool _collapsed = false;

  ConditionsController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    // Observation de l'état global du drag du slider d'heure (qui vit en
    // haut de la carte, en topChrome). Pendant le drag, on masque
    // ENTIÈREMENT le panel pour libérer la carte. Le slider reste
    // accessible en haut, donc le doigt ne dérape pas.
    return ValueListenableBuilder<bool>(
      valueListenable: _hourSliderDragging,
      builder: (context, dragging, _) {
        // Quand dragging=true : on retourne un SizedBox vide pour que
        // l'espace soit libéré (le `actionPanel` du WSMapScreen disparaît
        // complètement, on voit la carte intégralement).
        // Quand dragging=false : on rebuild le panel normalement.
        if (dragging) return const SizedBox.shrink();
        return _buildPanel(context);
      },
    );
  }

  Widget _buildPanel(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // Si on est en mode dessin, on remplace tout le panel par une
        // instruction claire + un bouton Annuler. Le chevron est désactivé
        // dans ce mode : on veut que l'utilisateur termine son geste.
        if (controller.isDrawing) {
          return _DrawingBanner(controller: controller);
        }

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
              // Header : toujours visible. Tap n'importe où (ou sur le
              // chevron) replie/déplie. Quand replié, on affiche un résumé
              // compact à droite du titre pour garder l'info utile à l'œil.
              _PanelHeader(
                controller: controller,
                collapsed: _collapsed,
                onToggle: () => setState(() => _collapsed = !_collapsed),
              ),
              if (!_collapsed) ...[
                const SizedBox(height: WSSpacing.sm),
                _StatusRow(controller: controller),
                const SizedBox(height: WSSpacing.sm),
                // Slider d'heure : volontairement absent ici, il est rendu
                // en haut de la carte via `buildTopChrome`. Plus aucune
                // duplication, et plus de problème de doigt qui dérape
                // pendant le drag.
                if (controller.bera != null) ...[
                  _BeraChip(controller: controller),
                  const SizedBox(height: WSSpacing.sm),
                ],
                if (controller.grid != null) ...[
                  _SnowHeatmapControls(controller: controller),
                  const SizedBox(height: WSSpacing.sm),
                ],
                if (controller.grid != null) ...[
                  _BestWindowControls(controller: controller),
                  const SizedBox(height: WSSpacing.sm),
                ],
                if (controller.grid != null) ...[
                  _AvalancheControls(controller: controller),
                  const SizedBox(height: WSSpacing.sm),
                ],
                Row(
                  children: [
                    Expanded(
                      child: controller.status == ConditionsStatus.loading
                          ? const _LoadingPill()
                          : FilledButton.icon(
                              onPressed: controller.startDrawing,
                              icon: const Icon(Icons.crop_free, size: 18),
                              label: Text(controller.accumulatedPoints.isEmpty
                                  ? 'Dessiner ma zone'
                                  : 'Ajouter une zone'),
                            ),
                    ),
                    if (controller.accumulatedPoints.isNotEmpty) ...[
                      const SizedBox(width: WSSpacing.sm),
                      IconButton.outlined(
                        icon: const Icon(Icons.layers_clear, size: 18),
                        tooltip: 'Effacer toutes les zones de la carte',
                        onPressed: controller.clearAccumulatedPoints,
                      ),
                    ],
                    if (controller.grid != null) ...[
                      const SizedBox(width: WSSpacing.sm),
                      IconButton.outlined(
                        icon: const Icon(Icons.refresh, size: 18),
                        tooltip: 'Rafraîchir la dernière zone',
                        onPressed: () {
                          final box = controller.drawnBbox;
                          if (box != null) {
                            controller.fetchGrid(box.sw, box.ne, force: true);
                          } else {
                            widget.onFetchHere();
                          }
                        },
                      ),
                    ],
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

/// Header du panel Conditions : titre + chevron pour replier/déplier.
/// Quand replié, affiche un résumé compact des indicateurs clés à droite
/// pour rester informatif sans prendre de place.
class _PanelHeader extends StatelessWidget {
  final ConditionsController controller;
  final bool collapsed;
  final VoidCallback onToggle;

  const _PanelHeader({
    required this.controller,
    required this.collapsed,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    // Construit le résumé compact à droite : risque BERA + nombre de points
    // cumulés (proxy "j'ai du contenu sur la carte"). Tout est optionnel,
    // on n'affiche que ce qui existe pour éviter le bruit.
    final summary = <Widget>[];
    if (collapsed) {
      final risque = controller.bera?.risqueBas;
      if (risque != null) {
        summary.add(_SummaryPill(
          icon: Icons.warning_amber_outlined,
          text: 'BERA $risque/5',
          color: _beraColor(risque),
        ));
      }
      final nbPoints = controller.accumulatedPoints.length;
      if (nbPoints > 0) {
        summary.add(const SizedBox(width: 6));
        summary.add(_SummaryPill(
          icon: Icons.scatter_plot_outlined,
          text: '$nbPoints pts',
          color: WSColors.glacierBlue,
        ));
      }
    }

    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(WSRadius.sm),
      child: Padding(
        // Padding minimal pour que la zone tactile reste confortable au gant
        // sans alourdir visuellement le header (déjà entouré du padding panel).
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const Icon(Icons.layers_outlined,
                size: 18, color: WSColors.slateDark),
            const SizedBox(width: WSSpacing.sm),
            const Text('Conditions', style: WSText.title),
            const SizedBox(width: WSSpacing.sm),
            // Résumé compact à droite quand replié
            ...summary,
            const Spacer(),
            Icon(
              collapsed ? Icons.expand_less : Icons.expand_more,
              size: 24,
              color: WSColors.slateDark,
            ),
          ],
        ),
      ),
    );
  }

  /// Couleur du chip BERA selon le niveau (palette officielle Météo France).
  /// Délègue à `WSColors.beraColor` pour cohérence avec le reste de l'app.
  Color _beraColor(int r) => WSColors.beraColor(r);
}

/// Petite pastille colorée pour le résumé replié du header.
class _SummaryPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _SummaryPill({
    required this.icon, required this.text, required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(WSRadius.pill),
        border: Border.all(color: color.withOpacity(0.35), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            text,
            style: WSText.micro.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bandeau affiché à la place de l'action panel quand on est en mode dessin.
class _DrawingBanner extends StatelessWidget {
  final ConditionsController controller;
  const _DrawingBanner({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        WSSpacing.lg, WSSpacing.md, WSSpacing.md, WSSpacing.md),
      decoration: BoxDecoration(
        color: WSColors.glacierBlue,
        borderRadius: BorderRadius.circular(WSRadius.lg),
      ),
      child: Row(
        children: [
          const Icon(Icons.touch_app, size: 18, color: WSColors.snowWhite),
          const SizedBox(width: WSSpacing.sm),
          Expanded(
            child: Text(
              'Glisse sur la carte pour dessiner ta zone',
              style: WSText.body.copyWith(color: WSColors.snowWhite),
            ),
          ),
          TextButton(
            onPressed: controller.cancelDrawing,
            style: TextButton.styleFrom(
              foregroundColor: WSColors.snowWhite,
            ),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final ConditionsController controller;
  const _StatusRow({required this.controller});

  @override
  Widget build(BuildContext context) {
    // Cas spécial : backend en cours de réveil → on l'indique discrètement
    if (controller.isWakingUp && controller.status != ConditionsStatus.loading) {
      return const Row(children: [
        SizedBox(
          width: 10, height: 10,
          child: CircularProgressIndicator(strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation(WSColors.glacierBlue)),
        ),
        SizedBox(width: WSSpacing.sm),
        Text('Backend en cours de réveil…', style: WSText.caption),
      ]);
    }

    switch (controller.status) {
      case ConditionsStatus.empty:
        return const Text(
          'Touche "Dessiner ma zone" pour récupérer les conditions',
          style: WSText.caption,
        );
      case ConditionsStatus.loading:
        return const Text('Récupération des conditions…', style: WSText.caption);
      case ConditionsStatus.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _friendlyError(controller.errorMessage),
              style: WSText.caption.copyWith(color: WSColors.avalancheRed),
            ),
            const SizedBox(height: WSSpacing.sm),
            OutlinedButton.icon(
              onPressed: controller.retry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Réessayer'),
              style: OutlinedButton.styleFrom(
                foregroundColor: WSColors.glacierBlue,
                side: const BorderSide(color: WSColors.glacierBlue, width: 0.5),
                padding: const EdgeInsets.symmetric(
                  horizontal: WSSpacing.md, vertical: 6,
                ),
                minimumSize: Size.zero,
              ),
            ),
          ],
        );
      case ConditionsStatus.ready:
        final fetched = controller.gridFetchedAt;
        final n = controller.grid?.points.length ?? 0;
        final ago = fetched == null
            ? ''
            : ' · il y a ${DateTime.now().difference(fetched).inMinutes} min';
        return Text('$n points$ago', style: WSText.caption);
      case ConditionsStatus.staleCache:
        return Text(
          'Donnée du cache (hors-ligne) — ${controller.errorMessage ?? ""}',
          style: WSText.caption.copyWith(color: WSColors.sunOrange),
        );
    }
  }

  /// Traduit les messages d'erreur techniques en quelque chose de lisible.
  static String _friendlyError(String? raw) {
    if (raw == null || raw.isEmpty) return 'Erreur inconnue';
    if (raw.contains('TimeoutException')) {
      return 'Le serveur a mis trop de temps à répondre. '
             'L\'instance gratuite peut être en train de se réveiller — réessaie.';
    }
    if (raw.contains('SocketException') || raw.contains('Erreur réseau')) {
      return 'Pas de connexion réseau.';
    }
    return raw;
  }
}

/// Slider d'heure UTC pour le module Conditions. Rendu en haut de la carte
/// via `buildTopChrome` plutôt que dans l'action panel — comme ça, pendant
/// le drag, c'est le panel du bas qui se masque et libère la carte sans
/// que le doigt ne dérape (le slider reste à sa position absolue).
/// Pousse l'état drag dans `_hourSliderDragging` pour que l'action panel
/// l'observe.
class ConditionsHourSlider extends StatelessWidget {
  final ConditionsController controller;
  const ConditionsHourSlider({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WSSpacing.md,
        vertical: WSSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: WSColors.snowWhite.withOpacity(0.96),
        borderRadius: BorderRadius.circular(WSRadius.lg),
        border: Border.all(color: WSColors.glacierMid, width: 0.5),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              '${controller.selectedHourUtc.toString().padLeft(2, "0")}h',
              style: WSText.caption.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              ),
              child: Slider(
                value: controller.selectedHourUtc.toDouble(),
                min: 0,
                max: 23,
                divisions: 23,
                label: '${controller.selectedHourUtc}h',
                activeColor: WSColors.glacierBlue,
                inactiveColor: WSColors.glacierMid,
                onChangeStart: (_) => _hourSliderDragging.value = true,
                onChangeEnd:   (_) => _hourSliderDragging.value = false,
                onChanged: (v) {
                  controller.selectedHourUtc = v.toInt();
                },
              ),
            ),
          ),
          Text('UTC', style: WSText.micro.copyWith(color: WSColors.stoneGray)),
        ],
      ),
    );
  }
}

class _BeraChip extends StatelessWidget {
  final ConditionsController controller;
  const _BeraChip({required this.controller});

  @override
  Widget build(BuildContext context) {
    final bera = controller.bera;
    if (bera == null) return const SizedBox.shrink();

    final risk = bera.displayRisk;
    final riskColor = _riskColor(risk);
    final riskTxt = risk == null ? '?' : '$risk/5';
    final massifName = bera.massifName;

    // Le chip devient tappable si on a un nom de massif : ouvre l'écran
    // détail BERA (récupère le bulletin complet depuis le repo public
    // ski-touring-live mis à jour quotidiennement).
    final canOpenDetail = massifName != null && massifName.trim().isNotEmpty;

    final inner = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(color: riskColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: WSSpacing.sm),
        Text(
          '${massifName ?? "Massif"}  ·  BERA $riskTxt',
          style: WSText.caption.copyWith(
            color: WSColors.slateDark,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (canOpenDetail) ...[
          const SizedBox(width: 4),
          Icon(Icons.chevron_right,
              size: 14, color: WSColors.slateDark.withOpacity(0.5)),
        ],
      ],
    );

    final container = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WSSpacing.md, vertical: WSSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: riskColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(WSRadius.md),
        border: Border.all(color: riskColor.withOpacity(0.4), width: 0.5),
      ),
      child: inner,
    );

    if (!canOpenDetail) return container;

    return InkWell(
      onTap: () => BeraDetailScreen.open(context, massifName),
      borderRadius: BorderRadius.circular(WSRadius.md),
      child: container,
    );
  }

  /// Couleur du chip BERA selon le niveau (palette officielle Météo France).
  /// Délègue à `WSColors.beraColor`. Gère `null` (retourne gris neutre).
  static Color _riskColor(int? r) {
    if (r == null) return WSColors.stoneGray;
    return WSColors.beraColor(r);
  }
}

class _LoadingPill extends StatelessWidget {
  const _LoadingPill();
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
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(WSColors.glacierBlue),
            ),
          ),
          SizedBox(width: WSSpacing.sm),
          Text('Chargement…',
              style: TextStyle(fontSize: 12, color: WSColors.glacierBlue)),
        ],
      ),
    );
  }
}

/// Bloc Avalanche dans l'action panel :
///   - Toggle "Afficher zones d'avalanche"
///   - Si actif : slider risque 1-5 (override) avec valeur BERA par défaut
class _AvalancheControls extends StatelessWidget {
  final ConditionsController controller;
  const _AvalancheControls({required this.controller});

  @override
  Widget build(BuildContext context) {
    final visible = controller.avalancheVisible;
    final bera = controller.bera;
    final realRisk = bera?.risqueBas ?? 3;
    final activeRisk = controller.riskOverride ?? realRisk;

    return Container(
      padding: const EdgeInsets.all(WSSpacing.sm),
      decoration: BoxDecoration(
        color: visible
            ? WSColors.avalancheRed.withOpacity(0.06)
            : WSColors.glacierLight,
        borderRadius: BorderRadius.circular(WSRadius.md),
        border: Border.all(
          color: visible
              ? WSColors.avalancheRed.withOpacity(0.4)
              : WSColors.glacierMid,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => controller.toggleAvalanche(),
            borderRadius: BorderRadius.circular(WSRadius.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    visible
                        ? Icons.warning_amber
                        : Icons.warning_amber_outlined,
                    size: 20,
                    color: visible
                        ? WSColors.avalancheRed
                        : WSColors.stoneGray,
                  ),
                  const SizedBox(width: WSSpacing.sm),
                  Expanded(
                    child: Text(
                      visible
                          ? 'Zones d\'avalanche affichées'
                          : 'Afficher zones d\'avalanche',
                      style: WSText.body.copyWith(
                        fontWeight: FontWeight.w500,
                        color: visible
                            ? WSColors.avalancheRed
                            : WSColors.slateDark,
                      ),
                    ),
                  ),
                  if (controller.avalancheLoading)
                    const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        valueColor: AlwaysStoppedAnimation(
                            WSColors.avalancheRed),
                      ),
                    )
                  else
                    IgnorePointer(
                      child: Switch(
                        value: visible,
                        activeColor: WSColors.avalancheRed,
                        onChanged: (_) {},
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (visible) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  'Risque BERA',
                  style: WSText.micro.copyWith(color: WSColors.stoneGray),
                ),
                const SizedBox(width: WSSpacing.sm),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: WSColors.avalancheRed,
                      thumbColor:       WSColors.avalancheRed,
                      overlayColor:
                          WSColors.avalancheRed.withOpacity(0.15),
                      inactiveTrackColor:
                          WSColors.avalancheRed.withOpacity(0.25),
                      trackHeight: 3,
                    ),
                    child: Slider(
                      min: 1, max: 5, divisions: 4,
                      value: activeRisk.clamp(1, 5).toDouble(),
                      onChanged: (v) {
                        final iv = v.round();
                        // null si on revient au risque réel (pas d'override)
                        controller.setRiskOverride(
                            iv == realRisk ? null : iv);
                      },
                    ),
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: Text(
                    '$activeRisk/5',
                    textAlign: TextAlign.right,
                    style: WSText.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: WSColors.avalancheRed,
                    ),
                  ),
                ),
              ],
            ),
            if (controller.riskOverride != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Override actif (réel : $realRisk/5) — tap risque pour reset',
                  style: WSText.micro.copyWith(color: WSColors.stoneGray),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Bloc Best-Window dans l'action panel :
///   - Toggle "Meilleur créneau (poudre/moquette)"
///   - Si actif : sélecteur de mode (poudre / moquette / les deux)
class _BestWindowControls extends StatelessWidget {
  final ConditionsController controller;
  const _BestWindowControls({required this.controller});

  @override
  Widget build(BuildContext context) {
    final visible = controller.bestWindowVisible;
    final mode    = controller.bestWindowMode;

    return Container(
      padding: const EdgeInsets.all(WSSpacing.sm),
      decoration: BoxDecoration(
        color: visible
            ? const Color(0xFFFFD166).withOpacity(0.10)
            : WSColors.glacierLight,
        borderRadius: BorderRadius.circular(WSRadius.md),
        border: Border.all(
          color: visible
              ? const Color(0xFFE8A93C)
              : WSColors.glacierMid,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => controller.toggleBestWindow(),
            borderRadius: BorderRadius.circular(WSRadius.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    visible ? Icons.wb_sunny : Icons.wb_sunny_outlined,
                    size: 20,
                    color: visible
                        ? const Color(0xFFE8A93C)
                        : WSColors.stoneGray,
                  ),
                  const SizedBox(width: WSSpacing.sm),
                  Expanded(
                    child: Text(
                      visible
                          ? 'Meilleur créneau affiché'
                          : 'Meilleur créneau poudre/moquette',
                      style: WSText.body.copyWith(
                        fontWeight: FontWeight.w500,
                        color: visible
                            ? const Color(0xFFA77D24)
                            : WSColors.slateDark,
                      ),
                    ),
                  ),
                  if (controller.bestWindowLoading)
                    const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        valueColor: AlwaysStoppedAnimation(
                            Color(0xFFE8A93C)),
                      ),
                    )
                  else
                    IgnorePointer(
                      child: Switch(
                        value: visible,
                        activeColor: const Color(0xFFE8A93C),
                        onChanged: (_) {},
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (visible) ...[
            const SizedBox(height: 4),
            // Sélecteur poudre / moquette / both
            Row(
              children: [
                Expanded(
                  child: _ModeChip(
                    label: 'Poudre',
                    icon: Icons.ac_unit,
                    selected: mode == BestWindowMode.powder,
                    onTap: () =>
                        controller.setBestWindowMode(BestWindowMode.powder),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _ModeChip(
                    label: 'Moquette',
                    icon: Icons.wb_sunny_outlined,
                    selected: mode == BestWindowMode.spring,
                    onTap: () =>
                        controller.setBestWindowMode(BestWindowMode.spring),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _ModeChip(
                    label: 'Les 2',
                    icon: Icons.dashboard_outlined,
                    selected: mode == BestWindowMode.both,
                    onTap: () =>
                        controller.setBestWindowMode(BestWindowMode.both),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Légende temporelle compacte
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(children: [
                Text('🌙 6h', style: TextStyle(fontSize: 10)),
                Spacer(),
                Text('☀ 12h', style: TextStyle(fontSize: 10)),
                Spacer(),
                Text('🌅 18h', style: TextStyle(fontSize: 10)),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _ModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(WSRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFE8A93C)
              : WSColors.snowWhite,
          borderRadius: BorderRadius.circular(WSRadius.sm),
          border: Border.all(
            color: selected
                ? const Color(0xFFE8A93C)
                : WSColors.glacierMid,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14,
              color: selected ? WSColors.snowWhite : WSColors.slateDark),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: selected ? WSColors.snowWhite : WSColors.slateDark,
            )),
          ],
        ),
      ),
    );
  }
}

/// Bloc heatmap d'enneigement dans l'action panel.
/// Toggle + slider d'opacité + min/max actuels.
class _SnowHeatmapControls extends StatelessWidget {
  final ConditionsController controller;
  const _SnowHeatmapControls({required this.controller});

  @override
  Widget build(BuildContext context) {
    final visible = controller.snowHeatmapVisible;
    final hm = controller.snowHeatmap;
    final loading = controller.snowHeatmapLoading;

    return Container(
      padding: const EdgeInsets.all(WSSpacing.sm),
      decoration: BoxDecoration(
        color: visible
            ? const Color(0xFF2C6E8A).withOpacity(0.08)
            : WSColors.glacierLight,
        borderRadius: BorderRadius.circular(WSRadius.md),
        border: Border.all(
          color: visible
              ? const Color(0xFF2C6E8A).withOpacity(0.45)
              : WSColors.glacierMid,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => controller.toggleSnowHeatmap(),
            borderRadius: BorderRadius.circular(WSRadius.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.layers_outlined,
                    size: 20,
                    color: visible
                        ? const Color(0xFF2C6E8A)
                        : WSColors.stoneGray,
                  ),
                  const SizedBox(width: WSSpacing.sm),
                  Expanded(
                    child: Text(
                      visible
                          ? 'Enneigement affiché'
                          : 'Carte d\'enneigement (BERA)',
                      style: WSText.body.copyWith(
                        fontWeight: FontWeight.w500,
                        color: visible
                            ? const Color(0xFF2C6E8A)
                            : WSColors.slateDark,
                      ),
                    ),
                  ),
                  if (loading)
                    const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        valueColor:
                            AlwaysStoppedAnimation(Color(0xFF2C6E8A)),
                      ),
                    )
                  else
                    IgnorePointer(
                      child: Switch(
                        value: visible,
                        activeColor: const Color(0xFF2C6E8A),
                        onChanged: (_) {},
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (visible && hm != null) ...[
            const SizedBox(height: 4),
            // Slider opacité
            Row(
              children: [
                const Icon(Icons.opacity, size: 14, color: WSColors.stoneGray),
                const SizedBox(width: WSSpacing.sm),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFF2C6E8A),
                      thumbColor:       const Color(0xFF2C6E8A),
                      overlayColor:
                          const Color(0xFF2C6E8A).withOpacity(0.15),
                      inactiveTrackColor:
                          const Color(0xFF2C6E8A).withOpacity(0.25),
                      trackHeight: 3,
                    ),
                    child: Slider(
                      min: 0, max: 1,
                      value: controller.snowHeatmapOpacity,
                      onChanged: controller.setSnowHeatmapOpacity,
                    ),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${(controller.snowHeatmapOpacity * 100).round()}%',
                    textAlign: TextAlign.right,
                    style: WSText.micro.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            // Légende min/max
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Container(
                    width: 12, height: 12,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F1EC),
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: WSColors.glacierMid, width: 0.3),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('${hm.snowMinCm.round()} cm',
                      style: WSText.micro),
                  const SizedBox(width: WSSpacing.sm),
                  Container(
                    width: 60, height: 6,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Color(0xFFF4F1EC),
                        Color(0xFFA8D5F0),
                        Color(0xFF2C6E8A),
                        Color(0xFF1A3F52),
                      ]),
                    ),
                  ),
                  const SizedBox(width: WSSpacing.sm),
                  Container(
                    width: 12, height: 12,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A3F52),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('${hm.snowMaxCm.round()} cm',
                      style: WSText.micro),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}