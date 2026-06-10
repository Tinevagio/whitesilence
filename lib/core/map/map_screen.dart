import 'dart:math' show Point;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../gps/gps_service.dart';
import '../module_registry.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../../shared/help/help_screen.dart';
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
///   - le bandeau d'avertissement GPS (permission refusée / GPS éteint)
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

  void _onMapEvent(MapEvent event) {
    final cam = event.camera;
    MapViewport().update(
      bounds: cam.visibleBounds,
      zoom: cam.zoom,
    );
  }

  LatLng? _pixelToLatLng(Offset pixel) {
    try {
      return _mapCtrl.camera.pointToLatLng(Point(pixel.dx, pixel.dy));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapLayers = <Widget>[
      TileLayer(
        urlTemplate: 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'app.whitesilence',
        maxZoom: 17,
        tileProvider: CachedTileProvider(),
      ),
    ];

    for (final overlay in widget.overlays) {
      mapLayers.addAll(overlay.buildMapLayers(context));
    }

    if (_gps.lastLatLng != null) {
      mapLayers.add(_userPositionLayer(_gps.lastLatLng!));
    }

    final activeOverlay = _findActiveOverlay();
    final actionPanel   = activeOverlay?.buildActionPanel(context);
    final bottomSheet   = activeOverlay?.buildBottomSheet(context);
    final topChrome     = activeOverlay?.buildTopChrome(context);
    final dragHandler   = activeOverlay?.dragHandler;
    final isDragging    = dragHandler != null;

    final interactionOpts = activeOverlay?.interactionOptions
        ?? (isDragging
            ? _drawModeInteractionOptions
            : _defaultInteractionOptions);

    // Hauteur du bandeau du haut (status bar + padding + row + éventuel topChrome)
    // pour positionner le bandeau GPS juste en dessous sans overlap.
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final topBarHeight = statusBarHeight + WSSpacing.sm + 40; // row height = 40
    final topChromeExtra = topChrome != null ? WSSpacing.sm + 48.0 : 0.0;
    final gpsBannerTop = topBarHeight + topChromeExtra + WSSpacing.sm;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapCtrl,
          options: MapOptions(
            initialCenter: const LatLng(45.92, 6.87),
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

        // Bandeau du haut : logo + chip module + bouton GPS
        Positioned(
          top: statusBarHeight + WSSpacing.sm,
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
                    icon: Icons.help_outline,
                    tooltip: 'Comment ça marche ?',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const HelpScreen(),
                        fullscreenDialog: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: WSSpacing.xs),
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

        // ── Bandeau GPS ──────────────────────────────────────────────────────
        //
        // Affiché uniquement quand la permission est refusée définitivement
        // (permanentlyDenied) ou quand le GPS système est éteint.
        // Dans les deux cas, un bouton oriente l'utilisateur vers les Réglages.
        //
        // Cas typique : bêta-testeur qui avait l'ancienne version bugguée,
        // le dialogue n'a jamais été affiché, Android a enregistré un refus
        // implicite → permanentlyDenied. Il ne peut pas débloquer autrement
        // que depuis les Réglages Android.
        if (_gps.isPermissionDeniedForever || _gps.serviceDisabled)
          Positioned(
            top: gpsBannerTop,
            left: WSSpacing.md,
            right: WSSpacing.md,
            child: _GpsBanner(
              isDeniedForever: _gps.isPermissionDeniedForever,
              onOpenSettings: _gps.isPermissionDeniedForever
                  ? () => _gps.openAppSettings()
                  : () => _gps.openLocationSettings(),
            ),
          ),

        Positioned(
          bottom: actionPanel != null
              ? (bottomSheet != null ? 280 : 96)
              : WSSpacing.md,
          right: WSSpacing.md,
          child: const _Compass(),
        ),

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

// ── Bandeau GPS ──────────────────────────────────────────────────────────────

/// Bandeau d'avertissement affiché quand le GPS est inaccessible.
/// Deux cas distincts avec des messages et actions différents :
///   - [isDeniedForever] : permission refusée définitivement par Android.
///     → bouton "Autoriser" ouvre les réglages de l'app.
///   - GPS système éteint (serviceDisabled dans GpsService).
///     → bouton "Activer" ouvre les réglages de localisation système.
class _GpsBanner extends StatelessWidget {
  final bool isDeniedForever;
  final VoidCallback onOpenSettings;

  const _GpsBanner({
    required this.isDeniedForever,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final message = isDeniedForever
        ? 'Position GPS non autorisée'
        : 'GPS désactivé sur ce téléphone';
    final buttonLabel = isDeniedForever ? 'Autoriser' : 'Activer';

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: WSSpacing.md,
          vertical: WSSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: WSColors.slateDark.withOpacity(0.92),
          borderRadius: BorderRadius.circular(WSRadius.md),
          border: Border.all(
            color: WSColors.avalancheRed.withOpacity(0.6),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.location_off,
              size: 18,
              color: WSColors.avalancheRed,
            ),
            const SizedBox(width: WSSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 13,
                  color: WSColors.snowWhite,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: WSSpacing.sm),
            GestureDetector(
              onTap: onOpenSettings,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: WSSpacing.md,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: WSColors.glacierBlue,
                  borderRadius: BorderRadius.circular(WSRadius.sm),
                ),
                child: Text(
                  buttonLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: WSColors.snowWhite,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Widgets existants inchangés ──────────────────────────────────────────────

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

class _LogoBadge extends StatelessWidget {
  const _LogoBadge();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WSColors.snowWhite.withOpacity(0.94),
      borderRadius: BorderRadius.circular(WSRadius.md),
      child: InkWell(
        onTap: () {
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

    final needleNorth = ui.Path()
      ..moveTo(cx, cy - 13)
      ..lineTo(cx - 4, cy)
      ..lineTo(cx + 4, cy)
      ..close();
    canvas.drawPath(
      needleNorth,
      Paint()..color = WSColors.avalancheRed..style = PaintingStyle.fill,
    );

    final needleSouth = ui.Path()
      ..moveTo(cx, cy + 13)
      ..lineTo(cx - 4, cy)
      ..lineTo(cx + 4, cy)
      ..close();
    canvas.drawPath(
      needleSouth,
      Paint()..color = WSColors.stoneGray..style = PaintingStyle.fill,
    );

    canvas.drawCircle(
      Offset(cx, cy),
      1.6,
      Paint()..color = WSColors.slateDark,
    );

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
      onTapDown:   (d) => onStart(d.localPosition),
      onTapUp:     (d) => onEnd(d.localPosition),
      child: const SizedBox.expand(),
    );
  }
}
