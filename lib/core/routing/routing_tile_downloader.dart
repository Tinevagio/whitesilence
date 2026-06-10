// lib/core/routing/routing_tile_downloader.dart
//
// Téléchargement de tuiles de routage .wsr depuis Supabase Storage.
// Calque exact de HgtDownloader — mêmes types DownloadProgress/DownloadStatus,
// même signature onProgress.
//
// Les tuiles sont hébergées dans le bucket Supabase `routing-tiles`,
// en accès public. URL publique :
//   https://<project>.supabase.co/storage/v1/object/public/routing-tiles/<KEY>.wsr
//
// Configure SUPABASE_ROUTING_BASE_URL dans ton .env (ou directement ici
// en dur si tu préfères — pas de secret dans cette URL, elle est publique).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'offline_route_provider.dart';

// ── Zones de routage disponibles ──────────────────────────────────────────────

class RoutingZone {
  /// Clé OSM de la tuile principale (ex: 'N45E005'). Si la zone couvre
  /// plusieurs tuiles, elles sont toutes listées dans [tiles].
  final String name;
  final String description;
  final List<String> tiles; // tuiles .wsr à télécharger pour cette zone
  final double sizeMb;      // taille totale indicative

  const RoutingZone({
    required this.name,
    required this.description,
    required this.tiles,
    required this.sizeMb,
  });

  /// Identifiant unique de la zone (premier tile).
  String get id => tiles.first;

  static const List<RoutingZone> alpineZones = [
    RoutingZone(
      name: 'Belledonne · Chartreuse',
      description: 'Grenoble, Chamrousse, Prabert, Chartreuse',
      tiles: ['N45E005'],
      sizeMb: 30,
    ),
    RoutingZone(
      name: 'Mont-Blanc · Aravis',
      description: 'Chamonix, Contamines, Megève, Aravis',
      tiles: ['N45E006'],
      sizeMb: 14,
    ),
    RoutingZone(
      name: 'Écrins · Oisans',
      description: 'Alpe d\'Huez, La Grave, Briançon',
      tiles: ['N44E005'],
      sizeMb: 18,
    ),
    RoutingZone(
      name: 'Vanoise · Gran Paradiso',
      description: 'Tignes, Val-d\'Isère, Bonneval, Haute-Maurienne',
      tiles: ['N45E007'],
      sizeMb: 12,
    ),
    RoutingZone(
      name: 'Mercantour · Alpes-Maritimes',
      description: 'Vésubie, Tinée, Ubaye',
      tiles: ['N43E006', 'N44E006'],
      sizeMb: 22,
    ),
    RoutingZone(
      name: 'Pyrénées Centrales',
      description: 'Gavarnie, Vignemale, Cauterets',
      tiles: ['N42E000'],
      sizeMb: 10,
    ),
    RoutingZone(
      name: 'Pyrénées Orientales',
      description: 'Canigou, Font-Romeu, Carlit',
      tiles: ['N42E001'],
      sizeMb: 8,
    ),
  ];
}

// ── Progression (même API que HgtDownloader) ──────────────────────────────────

enum DownloadStatus { idle, downloading, done, error }

class DownloadProgress {
  final DownloadStatus status;
  final double progress; // 0.0 → 1.0
  final String? error;
  const DownloadProgress({
    required this.status,
    this.progress = 0.0,
    this.error,
  });
}

// ── Downloader ────────────────────────────────────────────────────────────────

class RoutingTileDownloader {
  /// URL de base du bucket Supabase (sans slash final).
  /// Exemple : https://xxxx.supabase.co/storage/v1/object/public/routing-tiles
  static String get _baseUrl {
    try {
      return dotenv.env['SUPABASE_ROUTING_BASE_URL'] ??
          _fallbackUrl;
    } catch (_) {
      return _fallbackUrl;
    }
  }

  // À remplacer par l'URL réelle de ton projet Supabase.
  static const String _fallbackUrl =
      'https://VOTRE_PROJET.supabase.co/storage/v1/object/public/routing-tiles';

  static String _tileUrl(String key) => '$_baseUrl/$key.wsr';

  /// Télécharge toutes les tuiles d'une [zone] et les installe dans
  /// `app_flutter/routing/`. Appelle [onProgress] avec la progression globale.
  static Future<void> downloadZone(
    RoutingZone zone, {
    required void Function(DownloadProgress) onProgress,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final routingDir = Directory('${dir.path}/routing');
    await routingDir.create(recursive: true);

    final total = zone.tiles.length;
    for (var i = 0; i < total; i++) {
      final key = zone.tiles[i];
      final tileProgress = i / total;

      final success = await _downloadTile(
        key,
        destFile: File('${routingDir.path}/$key.wsr'),
        onProgress: (p) => onProgress(DownloadProgress(
          status: DownloadStatus.downloading,
          progress: tileProgress + p / total,
        )),
      );

      if (!success) {
        onProgress(DownloadProgress(
          status: DownloadStatus.error,
          error: 'Téléchargement de $key échoué — vérifiez votre connexion',
        ));
        return;
      }

      // Invalide le cache en mémoire pour cette tuile.
      OfflineRouteProvider.invalidateCache(key);
      debugPrint('Routing: $key installé ✓');
    }

    onProgress(const DownloadProgress(status: DownloadStatus.done, progress: 1.0));
  }

  /// Télécharge une tuile unique par sa clé (ex: 'N45E005').
  /// Utilisé par OfflineZoneManager pour le téléchargement unifié.
  /// Renvoie true si succès.
  static Future<bool> downloadSingleTile(
    String key, {
    required void Function(double progress) onProgress,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final routingDir = Directory('${dir.path}/routing');
    await routingDir.create(recursive: true);
    final success = await _downloadTile(
      key,
      destFile: File('${routingDir.path}/$key.wsr'),
      onProgress: onProgress,
    );
    if (success) {
      OfflineRouteProvider.invalidateCache(key);
      debugPrint('Routing: $key installé ✓');
    }
    return success;
  }

  static Future<bool> _downloadTile(
    String key, {
    required File destFile,
    required void Function(double) onProgress,
  }) async {
    final url = _tileUrl(key);
    debugPrint('Routing: téléchargement $url');

    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await http.Client()
          .send(request)
          .timeout(const Duration(minutes: 5));

      if (response.statusCode != 200) {
        debugPrint('Routing: HTTP ${response.statusCode} pour $key');
        return false;
      }

      final total = response.contentLength ?? 0;
      var received = 0;
      final chunks = <List<int>>[];

      await for (final chunk in response.stream) {
        chunks.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress(received / total);
      }

      final bytes = Uint8List.fromList(chunks.expand((c) => c).toList());
      await destFile.writeAsBytes(bytes);
      return true;
    } catch (e) {
      debugPrint('Routing: erreur réseau $key : $e');
      return false;
    }
  }

  /// Supprime toutes les tuiles d'une zone.
  static Future<void> deleteZone(RoutingZone zone) async {
    for (final key in zone.tiles) {
      await OfflineRouteProvider.deleteTile(key);
    }
  }

  /// Vérifie si toutes les tuiles d'une zone sont installées.
  static Future<bool> isInstalled(RoutingZone zone) async {
    for (final key in zone.tiles) {
      if (!await OfflineRouteProvider.isAvailable(
        // on passe lat/lng fictifs — isAvailable teste juste l'existence du fichier
        _latFromKey(key).toDouble(),
        _lngFromKey(key).toDouble(),
      )) return false;
    }
    return true;
  }

  // Extrait lat/lng entiers depuis une clé comme 'N45E005'.
  static int _latFromKey(String key) {
    final sign = key[0] == 'N' ? 1 : -1;
    return sign * int.parse(key.substring(1, 3));
  }

  static int _lngFromKey(String key) {
    final sign = key[3] == 'E' ? 1 : -1;
    return sign * int.parse(key.substring(4));
  }
}
