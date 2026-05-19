// lib/core/elevation/hgt_downloader.dart
//
// Téléchargement de tuiles HGT depuis AWS Terrain Tiles (Skadi).
// Migré depuis TimeToGo sans changement de logique.

import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

// ── Massifs alpins disponibles ────────────────────────────────────────────────

class HgtMassif {
  final String name;
  final String tile;
  final String description;
  final double centerLat;
  final double centerLng;

  const HgtMassif({
    required this.name,
    required this.tile,
    required this.description,
    required this.centerLat,
    required this.centerLng,
  });

  static const List<HgtMassif> alpinesMassifs = [
    HgtMassif(name: 'Mont-Blanc / Chamonix',   tile: 'N45E006', description: 'Chamonix, Argentière, Contamines', centerLat: 45.85, centerLng: 6.85),
    HgtMassif(name: 'Belledonne / Chartreuse', tile: 'N45E005', description: 'Grenoble, Chamrousse, Prabert',    centerLat: 45.20, centerLng: 5.85),
    HgtMassif(name: 'Écrins / Oisans',         tile: 'N44E005', description: 'Alpe d\'Huez, La Grave, Briançon', centerLat: 44.90, centerLng: 6.10),
    HgtMassif(name: 'Vanoise Est',             tile: 'N45E006', description: 'Tignes, Val-d\'Isère, Bonneval',   centerLat: 45.45, centerLng: 6.90),
    HgtMassif(name: 'Gran Paradiso / Aoste',   tile: 'N45E007', description: 'Haute-Maurienne, Val d\'Aoste',   centerLat: 45.50, centerLng: 7.20),
    HgtMassif(name: 'Mercantour',              tile: 'N43E006', description: 'Alpes-Maritimes, Vésubie',         centerLat: 44.10, centerLng: 7.10),
    HgtMassif(name: 'Pyrénées Centrales',      tile: 'N42E000', description: 'Gavarnie, Vignemale, Cauterets',   centerLat: 42.80, centerLng: 0.10),
    HgtMassif(name: 'Pyrénées Orientales',     tile: 'N42E001', description: 'Canigou, Font-Romeu, Carlit',      centerLat: 42.60, centerLng: 2.00),
    HgtMassif(name: 'Jura / Vosges',           tile: 'N47E006', description: 'Crêt de la Neige, Ballon d\'Alsace', centerLat: 46.80, centerLng: 6.20),
    HgtMassif(name: 'Massif Central N',        tile: 'N45E002', description: 'Puy de Dôme, Cantal',              centerLat: 45.50, centerLng: 2.80),
  ];
}

enum DownloadStatus { idle, downloading, extracting, done, error }

class DownloadProgress {
  final DownloadStatus status;
  final double progress;
  final String? error;
  const DownloadProgress({required this.status, this.progress = 0.0, this.error});
}

class HgtDownloader {
  static String _skadiUrl(String tile) {
    final latPart = tile.substring(0, 3); // ex: "N45"
    return 'https://elevation-tiles-prod.s3.amazonaws.com/skadi/$latPart/$tile.hgt.gz';
  }

  static Future<void> downloadTile(
    String tile, {
    required void Function(DownloadProgress) onProgress,
  }) async {
    debugPrint('HGT: début téléchargement $tile');

    final dir    = await getApplicationDocumentsDirectory();
    final hgtDir = Directory('${dir.path}/hgt');
    await hgtDir.create(recursive: true);
    final destFile = File('${hgtDir.path}/$tile.hgt');

    onProgress(const DownloadProgress(status: DownloadStatus.downloading, progress: 0));

    final url     = _skadiUrl(tile);
    final gzBytes = await _download(
      url,
      onProgress: (p) => onProgress(
        DownloadProgress(status: DownloadStatus.downloading, progress: p * 0.9)),
    );

    if (gzBytes == null) {
      onProgress(const DownloadProgress(
        status: DownloadStatus.error,
        error: 'Téléchargement échoué — vérifiez votre connexion WiFi',
      ));
      return;
    }

    onProgress(const DownloadProgress(status: DownloadStatus.extracting, progress: 0.92));

    try {
      final hgtBytes = GZipDecoder().decodeBytes(gzBytes);

      final expected = 3601 * 3601 * 2;
      if (hgtBytes.length != expected) {
        throw Exception('Taille inattendue : ${hgtBytes.length} vs $expected bytes');
      }

      await destFile.writeAsBytes(hgtBytes);
      debugPrint('HGT: $tile installé ✓');
      onProgress(const DownloadProgress(status: DownloadStatus.done, progress: 1.0));
    } catch (e) {
      onProgress(DownloadProgress(
        status: DownloadStatus.error,
        error: 'Décompression échouée : $e',
      ));
    }
  }

  static Future<Uint8List?> _download(
    String url, {
    required void Function(double) onProgress,
  }) async {
    try {
      final request  = http.Request('GET', Uri.parse(url));
      final response = await http.Client().send(request)
          .timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) return null;

      final total    = response.contentLength ?? 0;
      var   received = 0;
      final chunks   = <List<int>>[];

      await for (final chunk in response.stream) {
        chunks.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress(received / total);
      }

      return Uint8List.fromList(chunks.expand((c) => c).toList());
    } catch (e) {
      debugPrint('HGT: erreur réseau : $e');
      return null;
    }
  }
}
