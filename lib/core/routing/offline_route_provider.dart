// lib/core/routing/offline_route_provider.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import 'route_graph.dart';
import 'route_provider.dart';

class OfflineRouteProvider implements RouteProvider {
  static final Map<String, RawTile?> _tileCache = {};

  @override
  Future<bool> covers(LatLng point) async {
    final tile = await _loadTile(point.latitude.floor(), point.longitude.floor());
    return tile != null;
  }

  @override
  Future<RouteResult?> route(
      LatLng start, LatLng end, RouteProfile profile) async {
    final graph = await _buildGraphForBbox(start, end);
    if (graph.isEmpty) {
      debugPrint('Routing: aucune tuile pour la zone demandée');
      return null;
    }
    final result = graph.route(start, end, profile);
    if (result == null) {
      debugPrint('Routing: aucun chemin trouvé (${profile.name})');
    }
    return result;
  }

  Future<RouteGraph> _buildGraphForBbox(LatLng a, LatLng b) async {
    final minLat = (a.latitude < b.latitude ? a.latitude : b.latitude).floor() - 1;
    final maxLat = (a.latitude > b.latitude ? a.latitude : b.latitude).floor() + 1;
    final minLng = (a.longitude < b.longitude ? a.longitude : b.longitude).floor() - 1;
    final maxLng = (a.longitude > b.longitude ? a.longitude : b.longitude).floor() + 1;

    final graph = RouteGraph();
    for (var lat = minLat; lat <= maxLat; lat++) {
      for (var lng = minLng; lng <= maxLng; lng++) {
        final tile = await _loadTile(lat, lng);
        if (tile != null) graph.mergeTile(tile);
      }
    }
    return graph;
  }

  // ── Chargement disque ──────────────────────────────────────────────────────

  static Future<RawTile?> _loadTile(int lat, int lng) async {
    final key = tileKey(lat, lng);
    if (_tileCache.containsKey(key)) {
      debugPrint('Routing: $key — cache (${_tileCache[key] == null ? "absent" : "présent"})');
      return _tileCache[key];
    }

    final file = await _tileFile(key);
    debugPrint('Routing: cherche ${file.path}');
    if (!await file.exists()) {
      _tileCache[key] = null;
      debugPrint('Routing: $key absent sur disque');
      return null;
    }
    try {
      final bytes = await file.readAsBytes();
      final tile = RawTile.parse(Uint8List.fromList(bytes));
      _tileCache[key] = tile;
      debugPrint('Routing: $key chargé — '
          '${tile.nodeCount} nœuds / ${tile.edgeCount} arêtes ✓');
      return tile;
    } catch (e) {
      _tileCache[key] = null;
      debugPrint('Routing: $key illisible ($e)');
      return null;
    }
  }

  static String tileKey(int lat, int lng) {
    final latStr = lat >= 0
        ? 'N${lat.abs().toString().padLeft(2, '0')}'
        : 'S${lat.abs().toString().padLeft(2, '0')}';
    final lngStr = lng >= 0
        ? 'E${lng.abs().toString().padLeft(3, '0')}'
        : 'W${lng.abs().toString().padLeft(3, '0')}';
    return '$latStr$lngStr';
  }

  static Future<File> _tileFile(String key) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/routing/$key.wsr');
  }

  // ── Gestion ────────────────────────────────────────────────────────────────

  /// Vide le cache en mémoire — force la relecture du disque au prochain calcul.
  /// À appeler après installation de nouvelles tuiles, ou en debug.
  static void clearCache() => _tileCache.clear();

  static Future<bool> isAvailable(double lat, double lng) async {
    final file = await _tileFile(tileKey(lat.floor(), lng.floor()));
    return file.exists();
  }

  static Future<List<String>> installedTiles() async {
    final dir = await getApplicationDocumentsDirectory();
    final rDir = Directory('${dir.path}/routing');
    if (!await rDir.exists()) return [];
    return rDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.wsr'))
        .map((f) => f.uri.pathSegments.last.replaceAll('.wsr', ''))
        .toList();
  }

  static Future<void> deleteTile(String key) async {
    _tileCache.remove(key);
    final file = await _tileFile(key);
    if (await file.exists()) await file.delete();
  }

  static void invalidateCache(String key) => _tileCache.remove(key);
}
