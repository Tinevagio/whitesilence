// lib/modules/time/widgets/hgt_coverage_layer.dart
//
// Affiche sur la carte les tuiles HGT 1°×1° couvrant la zone visible.
// - Tuiles installées : remplissage vert très léger + label vert "✓ N45E006"
// - Tuiles manquantes : contour orange + label cliquable "Tap → télécharger"
// - Tuiles en cours de téléchargement : barre de progression
//
// Différence avec TimeToGo : on couvre la zone VISIBLE de la carte
// (via MapViewport partagé), pas juste 3×3 autour du GPS. L'utilisateur peut
// donc naviguer où il veut et voir ce qui est dispo.
//
// Pour éviter de surcharger la carte aux faibles zooms, on limite l'affichage
// à un certain niveau de zoom minimal.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/elevation/hgt_downloader.dart';
import '../../../core/elevation/hgt_provider.dart';
import '../../../core/map/map_viewport.dart';
import '../../../core/theme/colors.dart';

/// Zoom minimal pour afficher la couverture HGT.
/// En-dessous, on couvrirait trop de tuiles et la carte deviendrait illisible.
const _minZoomForCoverage = 8.0;

/// Nombre maximum de tuiles affichées en une fois, par sécurité.
const _maxTilesShown = 60;

class HgtCoverageLayer extends StatefulWidget {
  const HgtCoverageLayer({super.key});

  @override
  State<HgtCoverageLayer> createState() => _HgtCoverageLayerState();
}

class _HgtCoverageLayerState extends State<HgtCoverageLayer> {
  // Toutes les tuiles installées sur l'appareil (refresh périodique)
  Set<String> _installed = <String>{};
  // Téléchargements en cours
  final Map<String, DownloadProgress> _downloading = {};

  @override
  void initState() {
    super.initState();
    _refreshInstalled();
  }

  Future<void> _refreshInstalled() async {
    final list = await HgtElevationProvider.installedTiles();
    if (!mounted) return;
    setState(() => _installed = list.toSet());
  }

  Future<void> _download(String tile) async {
    if (_downloading.containsKey(tile) || _installed.contains(tile)) return;

    setState(() {
      _downloading[tile] = const DownloadProgress(
        status: DownloadStatus.downloading,
        progress: 0,
      );
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Téléchargement $tile…'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
    }

    await HgtDownloader.downloadTile(tile, onProgress: (p) {
      if (mounted) setState(() => _downloading[tile] = p);
    });

    final prog = _downloading[tile];
    final ok = prog?.status == DownloadStatus.done;
    if (ok) {
      HgtElevationProvider.invalidateCache(tile);
      _installed.add(tile);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? '✓ $tile installé'
            : '✗ Échec téléchargement $tile'),
        backgroundColor: ok ? WSColors.powderGreen : WSColors.avalancheRed,
        behavior: SnackBarBehavior.floating,
      ));
      setState(() => _downloading.remove(tile));
    }
  }

  @override
  Widget build(BuildContext context) {
    // On écoute les bounds de la carte via le ValueNotifier partagé.
    return ValueListenableBuilder<LatLngBounds?>(
      valueListenable: MapViewport().bounds,
      builder: (context, bounds, _) {
        return ValueListenableBuilder<double?>(
          valueListenable: MapViewport().zoom,
          builder: (context, zoom, __) {
            if (bounds == null) return const SizedBox.shrink();
            if (zoom != null && zoom < _minZoomForCoverage) {
              // Trop dézoomé : on n'affiche rien (sinon trop de tuiles)
              return const SizedBox.shrink();
            }
            return _buildLayers(bounds);
          },
        );
      },
    );
  }

  Widget _buildLayers(LatLngBounds bounds) {
    final tiles = _tilesIntersecting(bounds);
    if (tiles.isEmpty) return const SizedBox.shrink();

    final polygons  = <Polygon>[];
    final polylines = <Polyline>[];
    final markers   = <Marker>[];

    for (final tile in tiles) {
      final corners = _tileBounds(tile);
      if (corners == null) continue;
      final installed   = _installed.contains(tile);
      final downloading = _downloading[tile];
      final isDownloading = downloading != null &&
          (downloading.status == DownloadStatus.downloading ||
              downloading.status == DownloadStatus.extracting);

      if (installed) {
        polygons.add(Polygon(
          points:            corners,
          color:             WSColors.powderGreen.withOpacity(0.06),
          borderColor:       WSColors.powderGreen.withOpacity(0.55),
          borderStrokeWidth: 1.2,
        ));
      } else {
        polylines.add(Polyline(
          points:      corners + [corners.first],
          color:       isDownloading
              ? WSColors.glacierBlue.withOpacity(0.85)
              : WSColors.sunOrange.withOpacity(0.85),
          strokeWidth: isDownloading ? 2.5 : 1.3,
        ));
      }

      final m = _tileMarker(
        tile,
        installed: installed,
        downloading: downloading,
      );
      if (m != null) markers.add(m);
    }

    return Stack(children: [
      PolygonLayer(polygons: polygons),
      PolylineLayer(polylines: polylines),
      MarkerLayer(markers: markers),
    ]);
  }

  Marker? _tileMarker(
    String tile, {
    required bool installed,
    required DownloadProgress? downloading,
  }) {
    final center = _tileCenter(tile);
    if (center == null) return null;

    final isDownloading = downloading != null &&
        (downloading.status == DownloadStatus.downloading ||
            downloading.status == DownloadStatus.extracting);

    return Marker(
      point:  center,
      width:  170,
      height: 36,
      child: GestureDetector(
        onTap: installed || isDownloading ? null : () => _download(tile),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: WSColors.snowWhite.withOpacity(0.94),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: installed
                  ? WSColors.powderGreen
                  : isDownloading
                      ? WSColors.glacierBlue
                      : WSColors.sunOrange,
              width: 1.2,
            ),
          ),
          child: isDownloading
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                    width: 12, height: 12,
                    child: CircularProgressIndicator(
                      value: downloading.progress,
                      strokeWidth: 1.6,
                      color: WSColors.glacierBlue,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$tile ${(downloading.progress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontSize: 11,
                      color: WSColors.glacierBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ])
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    installed ? Icons.check_circle : Icons.download,
                    size: 12,
                    color: installed
                        ? WSColors.powderGreen
                        : WSColors.sunOrange,
                  ),
                  const SizedBox(width: 5),
                  Flexible(child: Text(
                    installed ? tile : 'Tap → $tile',
                    style: TextStyle(
                      fontSize: 11,
                      color: installed
                          ? WSColors.powderGreen
                          : WSColors.sunOrange,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  )),
                ]),
        ),
      ),
    );
  }

  // ── Utilitaires tile <-> bounds ──────────────────────────────────────────

  /// Liste les tuiles 1°×1° qui intersectent les bounds donnés.
  /// Cappé à _maxTilesShown pour éviter de surcharger.
  static List<String> _tilesIntersecting(LatLngBounds bounds) {
    final laMin = bounds.southWest.latitude.floor();
    final laMax = bounds.northEast.latitude.floor();
    final loMin = bounds.southWest.longitude.floor();
    final loMax = bounds.northEast.longitude.floor();

    final result = <String>[];
    for (int la = laMin; la <= laMax; la++) {
      for (int lo = loMin; lo <= loMax; lo++) {
        result.add(_keyFromInts(la, lo));
        if (result.length >= _maxTilesShown) return result;
      }
    }
    return result;
  }

  static String _keyFromInts(int la, int lo) {
    final latStr = la >= 0
        ? 'N${la.abs().toString().padLeft(2, '0')}'
        : 'S${la.abs().toString().padLeft(2, '0')}';
    final lngStr = lo >= 0
        ? 'E${lo.abs().toString().padLeft(3, '0')}'
        : 'W${lo.abs().toString().padLeft(3, '0')}';
    return '$latStr$lngStr';
  }

  static List<LatLng>? _tileBounds(String tile) {
    try {
      final la = int.parse(tile.substring(1, 3)) * (tile[0] == 'S' ? -1 : 1);
      final lo = int.parse(tile.substring(4, 7)) * (tile[3] == 'W' ? -1 : 1);
      return [
        LatLng(la.toDouble(),  lo.toDouble()),
        LatLng(la.toDouble(),  lo + 1.0),
        LatLng(la + 1.0,       lo + 1.0),
        LatLng(la + 1.0,       lo.toDouble()),
      ];
    } catch (_) {
      return null;
    }
  }

  static LatLng? _tileCenter(String tile) {
    try {
      final la = int.parse(tile.substring(1, 3)) * (tile[0] == 'S' ? -1 : 1);
      final lo = int.parse(tile.substring(4, 7)) * (tile[3] == 'W' ? -1 : 1);
      return LatLng(la + 0.5, lo + 0.5);
    } catch (_) {
      return null;
    }
  }
}
