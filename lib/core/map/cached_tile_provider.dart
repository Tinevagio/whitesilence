// lib/core/map/cached_tile_provider.dart
//
// Provider de tuiles avec cache disque persistant.
//
// Stratégie :
//   - À chaque demande de tuile, on regarde d'abord dans
//     getApplicationDocumentsDirectory()/tile_cache/{z}/{x}/{y}.png
//   - Si présent : on retourne le fichier local (instantané, marche offline)
//   - Sinon : on télécharge via HTTP, on écrit sur disque, puis on retourne
//
// Le cache grossit indéfiniment à l'usage. Pour le moment on n'a pas de LRU
// ni de cap de taille — c'est intentionnel : sur un téléphone moderne, même
// quelques GB de tuiles topo c'est gérable, et l'utilisateur peut toujours
// vider via Réglages Android → Apps → WhiteSilence → Stockage → Vider le
// cache (ou bien on ajoutera un bouton "Vider le cache" dans WS plus tard).
//
// Note pour l'avenir : si on veut un Niveau 2 (préchargement par bbox), on
// ajoutera juste une méthode statique `preloadTile(z, x, y, url)` qui réutilise
// la même logique de sauvegarde. La structure de répertoires est déjà bonne.

import 'dart:async';
import 'dart:io';
import 'dart:ui' show Codec, ImmutableBuffer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// TileProvider qui persiste les tuiles téléchargées sur disque.
///
/// Compatible avec `flutter_map: ^7.x`. Sous-classe `TileProvider`, redéfinit
/// `getImage(coords, options)` pour retourner un `ImageProvider` qui pointe
/// soit vers un fichier local, soit vers le réseau (avec sauvegarde après).
class CachedTileProvider extends TileProvider {
  CachedTileProvider({super.headers});

  /// Cache en mémoire du chemin du dossier root pour ne pas l'interroger à
  /// chaque tuile. Résolu paresseusement au premier appel.
  static String? _cacheRoot;

  static Future<String> _getCacheRoot() async {
    if (_cacheRoot != null) return _cacheRoot!;
    final dir = await getApplicationDocumentsDirectory();
    _cacheRoot = '${dir.path}/tile_cache';
    return _cacheRoot!;
  }

  /// Chemin local d'une tuile (sans garantie qu'elle existe).
  static Future<File> _tileFile(int z, int x, int y) async {
    final root = await _getCacheRoot();
    return File('$root/$z/$x/$y.png');
  }

  @override
  ImageProvider getImage(TileCoordinates coords, TileLayer options) {
    final url = getTileUrl(coords, options);
    return _CachedNetworkImage(
      url: url,
      z: coords.z,
      x: coords.x,
      y: coords.y,
      headers: headers,
    );
  }

  /// Pour debug / Réglages : taille totale du cache en bytes.
  /// Lourd à calculer si le cache est grand (parcourt tout l'arbre).
  static Future<int> cacheSizeBytes() async {
    final root = await _getCacheRoot();
    final dir = Directory(root);
    if (!await dir.exists()) return 0;
    int total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {}
      }
    }
    return total;
  }

  /// Pour debug / Réglages : vide tout le cache.
  static Future<void> clearCache() async {
    final root = await _getCacheRoot();
    final dir = Directory(root);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}

/// ImageProvider qui sert depuis le disque ou télécharge + cache.
///
/// On implémente `ImageProvider<Object>` parce que flutter_map utilise une clé
/// opaque ; un MemoryImage/FileImage standard ne suffit pas — il faut gérer
/// la résolution async (fichier dispo ? sinon HTTP).
class _CachedNetworkImage extends ImageProvider<_CachedNetworkImage> {
  final String url;
  final int z, x, y;
  final Map<String, String>? headers;

  _CachedNetworkImage({
    required this.url,
    required this.z,
    required this.x,
    required this.y,
    this.headers,
  });

  @override
  Future<_CachedNetworkImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _CachedNetworkImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(decode),
      scale: 1.0,
      debugLabel: 'CachedTile($z/$x/$y)',
    );
  }

  Future<Codec> _loadAsync(ImageDecoderCallback decode) async {
    final file = await CachedTileProvider._tileFile(z, x, y);

    // 1. Si on a déjà la tuile sur disque, on la sert directement.
    if (await file.exists()) {
      try {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          final buffer = await ImmutableBuffer.fromUint8List(bytes);
          return decode(buffer);
        }
      } catch (e) {
        debugPrint('[tileCache] erreur lecture $z/$x/$y: $e — re-download');
      }
    }

    // 2. Sinon, on télécharge et on sauvegarde.
    try {
      final response = await http.get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode} pour $url');
      }
      final bytes = response.bodyBytes;

      // Écriture sur disque en best-effort (on ne fait pas planter le rendu
      // si l'écriture rate).
      try {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: false);
      } catch (e) {
        debugPrint('[tileCache] erreur écriture $z/$x/$y: $e');
      }

      final buffer = await ImmutableBuffer.fromUint8List(bytes);
      return decode(buffer);
    } catch (e) {
      // Pas de réseau ET pas de cache → on propage l'erreur. flutter_map
      // affichera un placeholder vide pour cette tuile.
      throw Exception('Tile $z/$x/$y indisponible : $e');
    }
  }

  @override
  bool operator ==(Object other) {
    return other is _CachedNetworkImage &&
        other.url == url &&
        other.z == z &&
        other.x == x &&
        other.y == y;
  }

  @override
  int get hashCode => Object.hash(url, z, x, y);
}
