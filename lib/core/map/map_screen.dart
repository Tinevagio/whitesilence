import 'dart:math' show Point;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../gps/gps_service.dart';
import '../module_registry.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../../shared/settings/settings_screen.dart';
import 'cached_tile_provider.dart';
import 'map_module_overlay.dart';
import 'map_viewport.dart';

/// MapScreen partagée — l'UNIQUE carte de WhiteSilence.
///
/// Tous les modules viennent y greffer leurs overlays via [MapModuleOverlay].
/// Cette classe ne sait rien de Munter, des avalanches ou des observations :
/// elle ne gère que :
///   - le fond de carte OpenTopoMap
///   - la position GPS de l'utilisateur
///   - le routage des taps vers le module actif
///   - le pipeline d'overlays
class WSMapScreen extends StatefulWidget {
  final ModuleId activeModule;
  final List<MapModuleOverlay> overlays;
  final ValueChanged<ModuleId> onModuleChanged;

  const WSMapScreen({
    super.key,
    required this.activeModule,
    required this.overlays,
    required this.onModuleChanged,
  });

  @override
  State<WSMapScreen> createState() => _WSMapScreenState();
}

class _WSMapScreenState extends State<WSMapScreen> {
  final MapController _mapCtrl = MapController();
  final GpsService _gps = GpsService();
  bool _hasCenteredOnUser = false;

  // Overlay actif suivi en tant que Listenable — on rebuild quand son état change
  // (notamment isDrawing pour le module Conditions).
  MapModuleOverlay? _listenedActiveOverlay;

  // Options de geste de base — la carte est figée au nord, pas de rotation.
  static const _defaultInteractionOptions = InteractionOptions(
    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
    rotationThreshold: 100,
  );
  // Quand un overlay fournit un dragHandler, on désactive pan/zoom pour ne pas
  // capter le geste de drag du dessin.
  static const _drawModeInteractionOptions = InteractionOptions(
    flags: InteractiveFlag.none,
  );

  @override
  void initState() {
    super.initState();
    _gps.addListener(_onGps);
    _refreshListenedOverlay();
  }

  @override
  void didUpdateWidget(WSMapScreen old) {
    super.didUpdateWidget(old);
    if (old.activeModule != widget.activeModule ||
        !identical(old.overlays, widget.overlays)) {
      _refreshListenedOverlay();
    }
  }

  @override
  void dispose() {
    _gps.removeListener(_onGps);
    _listenedActiveOverlay?.removeListener(_onOverlayChanged);
    super.dispose();
  }

  /// Désabonne l'ancien overlay actif et abonne le nouveau.
  void _refreshListenedOverlay() {
    final next = _findActiveOverlay();
    if (identical(next, _listenedActiveOverlay)) return;
    _listenedActiveOverlay?.removeListener(_onOverlayChanged);
    _listenedActiveOverlay = next;
    _listenedActiveOverlay?.addListener(_onOverlayChanged);
  }

  MapModuleOverlay? _findActiveOverlay() {
    for (final o in widget.overlays) {
      if (o.id == widget.activeModule) return o;
    }
    return null;
  }

  void _onOverlayChanged() {
    if (mounted) setState(() {});
  }

  void _onGps() {
    if (!mounted) return;
    if (!_hasCenteredOnUser && _gps.lastLatLng != null) {
      _mapCtrl.move(_gps.lastLatLng!, 13.0);
      _hasCenteredOnUser = true;
    }
    setState(() {});
  }

  void _recenter() {
    if (_gps.lastLatLng != null) {
      _mapCtrl.move(_gps.lastLatLng!, _mapCtrl.camera.zoom);
    }
  }

  void _handleMapTap(TapPosition tapPos, LatLng latLng) {
    final active = _findActiveOverlay();
    active?.onMapTap(context, tapPos, latLng);
  }

  void _handleMapLongPress(TapPosition tapPos, LatLng latLng) {
    final active = _findActiveOverlay();
    active?.onMapLongPress(context, tapPos, latLng);
  }

  /// Pousse les bounds visibles dans le singleton MapViewport pour que les
  /// layers/overlays intéressés s'y abonnent. Appelé à chaque event de
  /// mouvement de carte (pan, zoom, rendu initial).
  void _onMapEvent(MapEvent event) {
    final cam = event.camera;
    MapViewport().update(
      bounds: cam.visibleBounds,
      zoom: cam.zoom,
    );
  }

  /// Convertit une position pixel (locale au widget de la carte) en LatLng
  /// via le MapController. Renvoie null si la carte n'est pas encore prête.
  LatLng? _pixelToLatLng(Offset pixel) {
    try {
      // flutter_map 7.x : pointToLatLng prend un Point<num> de dart:math.
      // (v8+ prend un Offset, mais on est sur v7.)
      return _mapCtrl.camera.pointToLatLng(Point(pixel.dx, pixel.dy));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapLayers = <Widget>[
      // Fond de carte topographique avec cache disque persistant.
      // Les tuiles téléchargées restent dispo offline (cf. CachedTileProvider).
      TileLayer(
        urlTemplate: 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'app.whitesilence',
        maxZoom: 17,
        tileProvider: CachedTileProvider(),
      ),
    ];

    // Empilement des overlays — uniquement les modules activés
    for (final overlay in widget.overlays) {
      mapLayers.addAll(overlay.buildMapLayers(context));
    }

    // Position de l'utilisateur — toujours par dessus
    if (_gps.lastLatLng != null) {
      mapLayers.add(_userPositionLayer(_gps.lastLatLng!));
    }

    final activeOverlay = _findActiveOverlay();
    final actionPanel   = activeOverlay?.buildActionPanel(context);
    final bottomSheet   = activeOverlay?.buildBottomSheet(context);
    final topChrome     = activeOverlay?.buildTopChrome(context);
    final dragHandler   = activeOverlay?.dragHandler;
    final isDragging    = dragHandler != null;

    // Si l'overlay actif fournit des options custom, on les prend ;
    // sinon, si on est en mode drag, on désactive les gestes carte ;
    // sinon, options par défaut (carte figée au nord).
    final interactionOpts = activeOverlay?.interactionOptions
        ?? (isDragging
            ? _drawModeInteractionOptions
            : _defaultInteractionOptions);

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapCtrl,
          options: MapOptions(
            initialCenter: const LatLng(45.92, 6.87), // Chamonix par défaut
            initialZoom: 13,
            minZoom: 5,
            maxZoom: 17,
            onTap: _handleMapTap,
            onLongPress: _handleMapLongPress,
            onMapEvent: _onMapEvent,
            interactionOptions: interactionOpts,
          ),
          children: mapLayers,
        ),

        // GestureDetector de dessin — superposé à la carte UNIQUEMENT quand
        // un overlay actif fournit un dragHandler. La carte sous-jacente a
        // ses gestes désactivés via _drawModeInteractionOptions, donc pas
        // de conflit pan/drag.
        if (isDragging)
          Positioned.fill(
            child: _DragCanvas(
              onStart: (offset) {
                final p = _pixelToLatLng(offset);
                if (p != null) dragHandler.onDragStart(p);
              },
              onUpdate: (offset) {
                final p = _pixelToLatLng(offset);
                if (p != null) dragHandler.onDragUpdate(p);
              },
              onEnd: (offset) {
                final p = _pixelToLatLng(offset);
                if (p != null) dragHandler.onDragEnd(p);
              },
            ),
          ),

        // Bandeau du haut : logo WS à gauche, chip module au centre,
        // bouton GPS à droite. Tous alignés verticalement sur la même ligne
        // (sous la status bar). Plus lisible que d'avoir le bouton GPS qui
        // flotte plus bas où il se confond avec la carto topo.
        //
        // Juste en dessous, on insère le `topChrome` éventuel du module
        // actif (ex: slider d'heure pour Conditions). Permet à un module
        // d'avoir des contrôles toujours visibles, séparés de l'action
        // panel du bas.
        Positioned(
          top: MediaQuery.of(context).padding.top + WSSpacing.sm,
          left: WSSpacing.md,
          right: WSSpacing.md,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const _LogoBadge(),
                  const SizedBox(width: WSSpacing.sm),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _TopChip(activeModule: widget.activeModule),
                    ),
                  ),
                  const SizedBox(width: WSSpacing.sm),
                  _TopBarButton(
                    icon: Icons.my_location,
                    tooltip: 'Recentrer sur ma position',
                    onTap: _recenter,
                  ),
                ],
              ),
              if (topChrome != null) ...[
                const SizedBox(height: WSSpacing.sm),
                topChrome,
              ],
            ],
          ),
        ),

        // Boussole (statique pour l'instant — la carte est figée au nord).
        // On la positionne au-dessus de la zone bottomSheet+actionPanel,
        // donc on lui réserve une marge conservatrice.
        Positioned(
          bottom: actionPanel != null
              ? (bottomSheet != null ? 280 : 96)
              : WSSpacing.md,
          right: WSSpacing.md,
          child: const _Compass(),
        ),

        // Zone du bas : carousel (bottom sheet du module) au-dessus +
        // action panel en bas, dans une Column unique.
        if (actionPanel != null || bottomSheet != null)
          Positioned(
            bottom: WSSpacing.md,
            left: WSSpacing.md,
            right: WSSpacing.md,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (bottomSheet != null) bottomSheet,
                if (bottomSheet != null && actionPanel != null)
                  const SizedBox(height: WSSpacing.sm),
                if (actionPanel != null) actionPanel,
              ],
            ),
          ),
      ],
    );
  }

  Widget _userPositionLayer(LatLng pos) {
    return MarkerLayer(
      markers: [
        Marker(
          point: pos,
          width: 24,
          height: 24,
          child: const _UserPositionDot(),
        ),
      ],
    );
  }
}

class _UserPositionDot extends StatelessWidget {
  const _UserPositionDot();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: WSColors.glacierBlue.withOpacity(0.2),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: WSColors.glacierBlue,
            shape: BoxShape.circle,
            border: Border.all(color: WSColors.snowWhite, width: 2),
          ),
        ),
      ),
    );
  }
}

/// Logo WhiteSilence (montagne + monogramme WS) en haut à gauche de la carte.
/// Affiche l'identité de l'app, et tap → ouvre les Réglages (raccourci utile).
class _LogoBadge extends StatelessWidget {
  const _LogoBadge();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WSColors.snowWhite.withOpacity(0.94),
      borderRadius: BorderRadius.circular(WSRadius.md),
      child: InkWell(
        onTap: () {
          // Tap sur le logo → ouvre les Réglages (raccourci utile depuis n'importe
          // où dans l'app).
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          );
        },
        borderRadius: BorderRadius.circular(WSRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: WSSpacing.sm,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(WSRadius.md),
            border: Border.all(color: WSColors.glacierMid, width: 0.5),
          ),
          child: Image.asset(
            'assets/images/logo_mountain.png',
            height: 28,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

class _TopChip extends StatelessWidget {
  final ModuleId activeModule;
  const _TopChip({required this.activeModule});

  @override
  Widget build(BuildContext context) {
    final info = ModuleRegistry.catalog.firstWhere((m) => m.id == activeModule);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WSSpacing.md,
        vertical: WSSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: WSColors.snowWhite.withOpacity(0.94),
        borderRadius: BorderRadius.circular(WSRadius.md),
        border: Border.all(color: WSColors.glacierMid, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(info.icon, size: 16, color: WSColors.glacierBlue),
          const SizedBox(width: WSSpacing.sm),
          Text(
            info.label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: WSColors.slateDark,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bouton compact aligné avec le _LogoBadge et le _TopChip dans le bandeau
/// du haut. Hauteur 40dp (identique au logo : padding vertical 6 +
/// contenu 28). Plus opaque qu'un bouton flottant carte pour rester
/// lisible sur fond topo coloré.
class _TopBarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _TopBarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: WSColors.snowWhite,
        borderRadius: BorderRadius.circular(WSRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(WSRadius.md),
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(WSRadius.md),
              border: Border.all(color: WSColors.glacierMid, width: 0.5),
            ),
            child: Icon(icon, size: 22, color: WSColors.slateDark),
          ),
        ),
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MapButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WSColors.snowWhite.withOpacity(0.94),
      borderRadius: BorderRadius.circular(WSRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(WSRadius.md),
        child: Container(
          width: WSTouch.iconButton,
          height: WSTouch.iconButton,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(WSRadius.md),
            border: Border.all(color: WSColors.glacierMid, width: 0.5),
          ),
          child: Icon(icon, size: 26, color: WSColors.slateDark),
        ),
      ),
    );
  }
}

/// Boussole minimaliste — flèche rouge vers le Nord, "N" sur fond clair.
/// Statique pour l'instant : la carte étant bloquée au nord, elle pointe
/// toujours vers le haut. Plus tard on pourra la lier au cap GPS via le
/// magnétomètre pour qu'elle tourne avec l'orientation du téléphone.
class _Compass extends StatelessWidget {
  const _Compass();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: WSColors.snowWhite.withOpacity(0.94),
        shape: BoxShape.circle,
        border: Border.all(color: WSColors.glacierMid, width: 0.5),
      ),
      child: CustomPaint(painter: _CompassPainter()),
    );
  }
}

class _CompassPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Aiguille rouge (pointe vers le nord = haut)
    final needleNorth = ui.Path()
      ..moveTo(cx, cy - 13)
      ..lineTo(cx - 4, cy)
      ..lineTo(cx + 4, cy)
      ..close();
    canvas.drawPath(
      needleNorth,
      Paint()..color = WSColors.avalancheRed..style = PaintingStyle.fill,
    );

    // Aiguille grise (pointe vers le sud = bas)
    final needleSouth = ui.Path()
      ..moveTo(cx, cy + 13)
      ..lineTo(cx - 4, cy)
      ..lineTo(cx + 4, cy)
      ..close();
    canvas.drawPath(
      needleSouth,
      Paint()..color = WSColors.stoneGray..style = PaintingStyle.fill,
    );

    // Point central
    canvas.drawCircle(
      Offset(cx, cy),
      1.6,
      Paint()..color = WSColors.slateDark,
    );

    // Lettre "N" tout en haut, petite, discrète
    final tp = TextPainter(
      text: const TextSpan(
        text: 'N',
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w600,
          color: WSColors.slateDark,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, 2.5));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Widget transparent superposé à la carte qui capte les pan events.
/// Utilisé en mode "dessin" (bbox, polygone…) — la carte sous-jacente a ses
/// gestes désactivés via _drawModeInteractionOptions, donc on capte tout ici.
class _DragCanvas extends StatelessWidget {
  final void Function(Offset) onStart;
  final void Function(Offset) onUpdate;
  final void Function(Offset) onEnd;

  const _DragCanvas({
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart:  (d) => onStart(d.localPosition),
      onPanUpdate: (d) => onUpdate(d.localPosition),
      onPanEnd:    (d) => onEnd(d.localPosition),
      // Tap sans drag = on note juste le point comme début ET fin pour ne pas
      // rester en état "drag started but never finished".
      onTapDown:   (d) => onStart(d.localPosition),
      onTapUp:     (d) => onEnd(d.localPosition),
      child: const SizedBox.expand(),
    );
  }
}
