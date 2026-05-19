// lib/modules/conditions/services/snow_heatmap.dart
//
// Génération d'une image bitmap représentant l'enneigement (cm de neige)
// sur la zone visible, par interpolation IDW (Inverse Distance Weighting).
//
// L'image résultante est affichée en `OverlayImageLayer` de flutter_map,
// avec un slider d'opacité dans l'action panel.
//
// Performance : ~50-200ms pour générer une image 400×400 avec ~100 points.
// On utilise compute() pour ne pas bloquer le thread UI.

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/point_conditions.dart';
import 'snow_interpolation.dart';

/// Résultat d'une heatmap : bytes PNG + bbox + échelle de valeurs.
/// Les bytes PNG peuvent être directement nourris à MemoryImage pour
/// l'OverlayImageLayer.
class SnowHeatmap {
  final Uint8List pngBytes;
  /// Bbox de l'image : sud-ouest et nord-est en LatLng.
  final LatLng sw;
  final LatLng ne;
  /// Échelle min/max des valeurs en cm (utile pour la légende).
  final double snowMinCm;
  final double snowMaxCm;

  const SnowHeatmap({
    required this.pngBytes,
    required this.sw,
    required this.ne,
    required this.snowMinCm,
    required this.snowMaxCm,
  });
}

class SnowHeatmapBuilder {
  SnowHeatmapBuilder._();

  static const int _imgSize = 400;

  /// Génère une heatmap pour les points donnés.
  /// Retourne null si moins de 2 points avec enneigement exploitable.
  static Future<SnowHeatmap?> build(List<PointConditions> points) async {
    if (points.length < 2) return null;

    // ── 1. Calcul des valeurs et bbox ─────────────────────────────────────
    final lats = points.map((p) => p.lat).toList();
    final lons = points.map((p) => p.lon).toList();
    final latMin = lats.reduce((a, b) => a < b ? a : b);
    final latMax = lats.reduce((a, b) => a > b ? a : b);
    final lonMin = lons.reduce((a, b) => a < b ? a : b);
    final lonMax = lons.reduce((a, b) => a > b ? a : b);

    if (latMax - latMin < 0.001 || lonMax - lonMin < 0.001) {
      // bbox dégénérée
      return null;
    }

    // Coordonnées pixel + valeur de neige par point
    final pts = <_PtData>[];
    for (final p in points) {
      final snow = SnowInterpolation.interpolate(p);
      if (snow == null) continue;
      pts.add(_PtData(
        cx: ((p.lon - lonMin) / (lonMax - lonMin)) * _imgSize,
        cy: ((latMax - p.lat) / (latMax - latMin)) * _imgSize,
        snow: snow.toDouble(),
      ));
    }
    if (pts.length < 2) return null;

    // Échelle dynamique sur les valeurs > 0
    final positiveSnow = pts.map((p) => p.snow).where((v) => v > 0).toList();
    final snowMin =
        positiveSnow.isEmpty ? 0.0 : positiveSnow.reduce((a, b) => a < b ? a : b);
    final snowMax = positiveSnow.isEmpty
        ? 100.0
        : positiveSnow.reduce((a, b) => a > b ? a : b);

    // ── 2. Rendu IDW dans un Uint8List RGBA ───────────────────────────────
    // On déporte ça en isolate via compute() pour ne pas freezer l'UI.
    final params = _RenderParams(pts: pts, snowMin: snowMin, snowMax: snowMax);
    final bytes = await compute(_renderHeatmapBytes, params);

    // ── 3. Encodage en PNG bytes (pour MemoryImage) ────────────────────────
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bytes,
      _imgSize,
      _imgSize,
      ui.PixelFormat.rgba8888,
      (img) => completer.complete(img),
    );
    final image = await completer.future;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (byteData == null) return null;
    final pngBytes = byteData.buffer.asUint8List();

    return SnowHeatmap(
      pngBytes:  pngBytes,
      sw:        LatLng(latMin, lonMin),
      ne:        LatLng(latMax, lonMax),
      snowMinCm: snowMin,
      snowMaxCm: snowMax,
    );
  }
}

/// Données passées à l'isolate de rendu (immutable, sérialisables).
class _RenderParams {
  final List<_PtData> pts;
  final double snowMin;
  final double snowMax;
  const _RenderParams({
    required this.pts,
    required this.snowMin,
    required this.snowMax,
  });
}

class _PtData {
  final double cx;
  final double cy;
  final double snow;
  const _PtData({required this.cx, required this.cy, required this.snow});
}

/// Génère les bytes RGBA de l'image par IDW.
/// Tourne dans un isolate, donc pas d'accès au framework Flutter ici.
Uint8List _renderHeatmapBytes(_RenderParams params) {
  const W = 400;
  const H = 400;
  final bytes = Uint8List(W * H * 4);
  final pts = params.pts;
  final snowMin = params.snowMin;
  final snowMax = params.snowMax;

  for (int py = 0; py < H; py++) {
    for (int px = 0; px < W; px++) {
      double wSum = 0;
      double vSum = 0;
      for (final p in pts) {
        final dx = px - p.cx;
        final dy = py - p.cy;
        final d2 = dx * dx + dy * dy;
        if (d2 < 0.5) {
          wSum = 1;
          vSum = p.snow;
          break;
        }
        // Puissance 1.5 — équilibre lissage / précision
        final w = 1.0 / (d2 * 1.2247); // ≈ d^1.5
        wSum += w;
        vSum += w * p.snow;
      }
      final snow = wSum > 0 ? vSum / wSum : 0.0;
      final rgba = _snowDepthColor(snow, snowMin, snowMax);
      final idx = (py * W + px) * 4;
      bytes[idx]     = rgba[0];
      bytes[idx + 1] = rgba[1];
      bytes[idx + 2] = rgba[2];
      bytes[idx + 3] = rgba[3];
    }
  }
  return bytes;
}

/// Couleur d'un pixel selon la quantité de neige.
/// Beige → bleu clair → bleu moyen → bleu foncé.
/// Identique au gradient du frontend V7.
List<int> _snowDepthColor(double cm, double snowMin, double snowMax) {
  if (cm <= 0) return [244, 241, 236, 0];
  final range = (snowMax - snowMin).clamp(1, double.infinity);
  final t = ((cm - snowMin) / range).clamp(0.0, 1.0);
  const stops = [
    [244, 241, 236],
    [168, 213, 240],
    [44, 110, 138],
    [26, 63, 82],
  ];
  final seg = t * (stops.length - 1);
  final i = seg.floor().clamp(0, stops.length - 2);
  final f = seg - i;
  final r = (stops[i][0] + f * (stops[i + 1][0] - stops[i][0])).round();
  final g = (stops[i][1] + f * (stops[i + 1][1] - stops[i][1])).round();
  final b = (stops[i][2] + f * (stops[i + 1][2] - stops[i][2])).round();
  final a = (40 + t * 180).round();
  return [r, g, b, a];
}
