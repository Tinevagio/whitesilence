// lib/modules/route/route_overlay.dart
//
// Overlay carte du module Itinéraire. Respecte le contrat MapModuleOverlay.
//
// - buildMapLayers : trace la polyline + marqueurs départ/arrivée
// - onMapTap       : délègue au RouteController (pose A puis B)
// - buildActionPanel : carte de stats (distance, D+, D-, temps) + bouton reset
//
// ⚠️ Ce fichier suppose un ModuleId.route ajouté au registre (voir note
// d'intégration). Si tu préfères greffer dans le module Temps existant,
// reprends la logique de buildMapLayers / onMapTap dans ton TimeOverlay.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/map/map_module_overlay.dart';
import '../../core/module_registry.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import 'route_controller.dart';

class RouteOverlay extends MapModuleOverlay {
  final RouteController _ctrl = RouteController();

  RouteOverlay() {
    _ctrl.addListener(notifyListeners);
  }

  @override
  ModuleId get id => ModuleId.route; // cf. note d'intégration

  @override
  void dispose() {
    _ctrl.removeListener(notifyListeners);
    super.dispose();
  }

  // ── Layers carte ───────────────────────────────────────────────────────────

  @override
  List<Widget> buildMapLayers(BuildContext context) {
    final layers = <Widget>[];

    if (_ctrl.tracePoints.length >= 2) {
      layers.add(PolylineLayer(
        polylines: [
          Polyline(
            points: _ctrl.tracePoints,
            strokeWidth: 5,
            color: WSColors.glacierBlue.withOpacity(0.9),
            borderStrokeWidth: 1.5,
            borderColor: Colors.white.withOpacity(0.8),
          ),
        ],
      ));
    }

    final markers = <Marker>[];
    if (_ctrl.start != null) {
      markers.add(_pin(_ctrl.start!, Icons.trip_origin, WSColors.glacierBlue));
    }
    if (_ctrl.end != null) {
      markers.add(_pin(_ctrl.end!, Icons.place, Colors.redAccent));
    }
    if (markers.isNotEmpty) {
      layers.add(MarkerLayer(markers: markers));
    }
    return layers;
  }

  Marker _pin(LatLng p, IconData icon, Color color) => Marker(
        point: p,
        width: 36,
        height: 36,
        alignment: Alignment.topCenter,
        child: Icon(icon, color: color, size: 32),
      );

  // ── Interaction ────────────────────────────────────────────────────────────

  @override
  bool onMapTap(BuildContext context, TapPosition tapPosition, LatLng latLng) {
    _ctrl.onTap(latLng);
    return true; // on intercepte
  }

  // ── Panneau d'action ─────────────────────────────────────────────────────

  @override
  Widget? buildActionPanel(BuildContext context) {
    switch (_ctrl.phase) {
      case RoutePhase.idle:
        return _hint('Touche un point de départ sur la carte');
      case RoutePhase.awaitingEnd:
        return _hint('Touche le point d\'arrivée');
      case RoutePhase.computing:
        return _hint('Calcul de l\'itinéraire…', spinner: true);
      case RoutePhase.error:
        return _panel(
          child: Text(
            _ctrl.message ?? 'Erreur',
            style: const TextStyle(color: Colors.redAccent),
          ),
          onReset: _ctrl.reset,
        );
      case RoutePhase.ready:
        return _statsPanel(context);
    }
  }

  Widget _statsPanel(BuildContext context) {
    final s = _ctrl.stats!;
    return _panel(
      onReset: _ctrl.reset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _stat(Icons.straighten, s.distanceLabel),
              _stat(Icons.trending_up, '+${s.elevGainM.round()} m'),
              _stat(Icons.trending_down, '-${s.elevLossM.round()} m'),
              _stat(Icons.schedule, s.durationLabel),
            ],
          ),
          if (_ctrl.message != null) ...[
            const SizedBox(height: WSSpacing.sm),
            Text(
              _ctrl.message!,
              style: TextStyle(
                fontSize: 11,
                color: WSColors.stoneGray,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String value) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: WSColors.glacierBlue),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      );

  Widget _hint(String text, {bool spinner = false}) => _panel(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (spinner) ...[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: WSSpacing.sm),
            ],
            Flexible(child: Text(text)),
          ],
        ),
      );

  Widget _panel({required Widget child, VoidCallback? onReset}) => Container(
        padding: const EdgeInsets.all(WSSpacing.md),
        decoration: BoxDecoration(
          color: WSColors.snowWhite,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(blurRadius: 12, color: Colors.black26),
          ],
        ),
        child: Row(
          children: [
            Expanded(child: child),
            if (onReset != null)
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: onReset,
                tooltip: 'Nouvel itinéraire',
              ),
          ],
        ),
      );
}
