// lib/core/offline/offline_zone_manager.dart
//
// Gestionnaire unifié des tuiles hors-ligne.
// Chaque tuile 1°×1° peut avoir :
//   - des données d'altitude  (.hgt  — SRTM1, isochrones)
//   - des données de routage  (.wsr  — OSM, itinéraires)
// ou les deux, ou aucune.
//
// Ce manager orchestre les deux téléchargements en parallèle et expose
// un état consolidé par clé de tuile.

import 'package:flutter/foundation.dart';

import '../elevation/hgt_downloader.dart';
import '../elevation/hgt_provider.dart';
import '../routing/offline_route_provider.dart';
import '../routing/routing_tile_downloader.dart';

// ── État d'une tuile ──────────────────────────────────────────────────────────

enum TileDataType { hgt, wsr }

class TileState {
  final bool hgtInstalled;
  final bool wsrInstalled;
  final bool wsrAvailable; // tuile WSR générée et disponible sur Supabase

  const TileState({
    this.hgtInstalled = false,
    this.wsrInstalled = false,
    this.wsrAvailable = false,
  });

  bool get fullyInstalled =>
      hgtInstalled && (wsrInstalled || !wsrAvailable);
  bool get anyInstalled => hgtInstalled || wsrInstalled;

  TileState copyWith({
    bool? hgtInstalled,
    bool? wsrInstalled,
    bool? wsrAvailable,
  }) =>
      TileState(
        hgtInstalled: hgtInstalled ?? this.hgtInstalled,
        wsrInstalled: wsrInstalled ?? this.wsrInstalled,
        wsrAvailable: wsrAvailable ?? this.wsrAvailable,
      );
}

// ── Progression d'un téléchargement ──────────────────────────────────────────

enum ZoneDownloadStatus { idle, downloading, done, error }

class ZoneDownloadState {
  final ZoneDownloadStatus status;
  final double hgtProgress;  // 0.0 → 1.0
  final double wsrProgress;  // 0.0 → 1.0
  final String? error;

  const ZoneDownloadState({
    this.status = ZoneDownloadStatus.idle,
    this.hgtProgress = 0.0,
    this.wsrProgress = 0.0,
    this.error,
  });

  /// Progression globale : moyenne des deux composantes actives.
  double get totalProgress {
    if (hgtProgress > 0 && wsrProgress > 0) {
      return (hgtProgress + wsrProgress) / 2;
    }
    return hgtProgress > 0 ? hgtProgress * 0.5 : wsrProgress * 0.5;
  }
}

// ── Tuiles WSR disponibles sur Supabase ───────────────────────────────────────
//
// Liste des tuiles pour lesquelles un fichier .wsr a été généré et uploadé.
// À mettre à jour après chaque run de build_graph.py + upload_tiles.py.
// Future amélioration : fetch d'un manifest.json depuis Supabase.

const Set<String> wsrAvailableTiles = {
  'N44E005', 'N44E006',
  'N45E005', 'N45E006',
  'N44E004',
  'N45E004',
  'N45E007',
  'N46E004',
  'N46E005',
  'N46E006',
  'N46E007',
  // Ajoute ici les tuiles au fur et à mesure que tu les génères :
  // 'N44E007', 'N45E007', 'N42E000', 'N42E001', ...
};

// ── Manager ───────────────────────────────────────────────────────────────────

class OfflineZoneManager extends ChangeNotifier {
  // tileKey → état
  final Map<String, TileState> _states = {};
  // tileKey → progression en cours
  final Map<String, ZoneDownloadState> _downloads = {};

  bool _loading = true;
  bool get loading => _loading;

  Map<String, TileState> get states => Map.unmodifiable(_states);
  Map<String, ZoneDownloadState> get downloads =>
      Map.unmodifiable(_downloads);

  ZoneDownloadState? downloadOf(String key) => _downloads[key];
  TileState stateOf(String key) =>
      _states[key] ??
      TileState(wsrAvailable: wsrAvailableTiles.contains(key));

  // ── Chargement initial ────────────────────────────────────────────────────

  Future<void> load() async {
    _loading = true;
    notifyListeners();

    final hgtInstalled = (await HgtElevationProvider.installedTiles()).toSet();
    final wsrInstalled = (await OfflineRouteProvider.installedTiles()).toSet();

    // Calcule l'union de toutes les tuiles pertinentes à afficher.
    final allKeys = <String>{
      ...hgtInstalled,
      ...wsrInstalled,
      ...wsrAvailableTiles,
      // Tuiles HGT connues (depuis HgtMassif)
      ...HgtMassif.alpinesMassifs.map((m) => m.tile),
    };

    for (final key in allKeys) {
      _states[key] = TileState(
        hgtInstalled: hgtInstalled.contains(key),
        wsrInstalled: wsrInstalled.contains(key),
        wsrAvailable: wsrAvailableTiles.contains(key),
      );
    }

    _loading = false;
    notifyListeners();
  }

  // ── Téléchargement ────────────────────────────────────────────────────────

  Future<void> downloadTile(String key) async {
    final state = stateOf(key);
    if (_downloads.containsKey(key)) return; // déjà en cours

    _downloads[key] = const ZoneDownloadState(
      status: ZoneDownloadStatus.downloading,
    );
    notifyListeners();

    double hgtProg = state.hgtInstalled ? 1.0 : 0.0;
    double wsrProg = (!state.wsrAvailable || state.wsrInstalled) ? 1.0 : 0.0;

    void refresh() {
      _downloads[key] = ZoneDownloadState(
        status: ZoneDownloadStatus.downloading,
        hgtProgress: hgtProg,
        wsrProgress: wsrProg,
      );
      notifyListeners();
    }

    // Lance HGT et WSR en parallèle.
    final futures = <Future>[];

    if (!state.hgtInstalled) {
      futures.add(
        HgtDownloader.downloadTile(
          key,
          onProgress: (p) {
            hgtProg = p.progress;
            refresh();
          },
        ).then((_) {
          hgtProg = 1.0;
          _states[key] = stateOf(key).copyWith(hgtInstalled: true);
          HgtElevationProvider.invalidateCache(key);
        }),
      );
    }

    if (state.wsrAvailable && !state.wsrInstalled) {
      futures.add(
        RoutingTileDownloader.downloadSingleTile(
          key,
          onProgress: (p) {
            wsrProg = p;
            refresh();
          },
        ).then((success) {
          wsrProg = 1.0;
          if (success) {
            _states[key] = stateOf(key).copyWith(wsrInstalled: true);
            OfflineRouteProvider.invalidateCache(key);
          }
        }),
      );
    }

    try {
      await Future.wait(futures);
      _downloads[key] = const ZoneDownloadState(
        status: ZoneDownloadStatus.done,
        hgtProgress: 1.0,
        wsrProgress: 1.0,
      );
    } catch (e) {
      _downloads[key] = ZoneDownloadState(
        status: ZoneDownloadStatus.error,
        error: '$e',
      );
      debugPrint('OfflineZoneManager: erreur $key : $e');
    }

    notifyListeners();
    // Retire la progression après un délai (laisser l'UI afficher "done").
    await Future.delayed(const Duration(seconds: 2));
    _downloads.remove(key);
    notifyListeners();
  }

  // ── Suppression ───────────────────────────────────────────────────────────

  Future<void> deleteTile(String key, {bool hgt = true, bool wsr = true}) async {
    if (hgt && stateOf(key).hgtInstalled) {
      await HgtElevationProvider.deleteTile(key);
    }
    if (wsr && stateOf(key).wsrInstalled) {
      await OfflineRouteProvider.deleteTile(key);
    }
    await load(); // recharge l'état complet
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Clé d'une tuile depuis des coordonnées géographiques.
  static String keyFromLatLng(double lat, double lng) {
    final iLat = lat.floor();
    final iLng = lng.floor();
    final latStr = iLat >= 0
        ? 'N${iLat.abs().toString().padLeft(2, '0')}'
        : 'S${iLat.abs().toString().padLeft(2, '0')}';
    final lngStr = iLng >= 0
        ? 'E${iLng.abs().toString().padLeft(3, '0')}'
        : 'W${iLng.abs().toString().padLeft(3, '0')}';
    return '$latStr$lngStr';
  }

  /// Coordonnées SW d'une tuile depuis sa clé.
  static (double lat, double lng) swFromKey(String key) {
    final latSign = key[0] == 'N' ? 1 : -1;
    final lngSign = key[3] == 'E' ? 1 : -1;
    final lat = latSign * double.parse(key.substring(1, 3));
    final lng = lngSign * double.parse(key.substring(4));
    return (lat, lng);
  }
}
