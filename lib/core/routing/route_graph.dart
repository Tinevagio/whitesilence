// lib/core/routing/route_graph.dart
//
// Graphe de routage en Dart pur.
//
// Charge une ou plusieurs tuiles .wsr (format défini ci-dessous, produit par
// tools/build_graph.py), les fusionne en un graphe unique dédupliqué par
// identifiant OSM, et exécute un A* pondéré par profil.
//
// ── Format binaire .wsr (little-endian) ───────────────────────────────────────
//   0   : 4 octets  magic 'WSR1'
//   4   : uint8     version (=1)
//   5   : uint8     réservé
//   6   : uint16    réservé
//   8   : uint32    nodeCount
//   12  : uint32    edgeCount        (arêtes dirigées, CSR)
//   16  : int64  [nodeCount]    osmId       (dédup inter-tuiles)
//   ... : int32  [nodeCount]    latMicro    (round(lat * 1e6))
//   ... : int32  [nodeCount]    lngMicro
//   ... : uint32 [nodeCount+1]  csrStart    (offsets CSR)
//   ... : uint32 [edgeCount]    targetLocal (index local de nœud cible)
//   ... : float32[edgeCount]    distM
//   ... : uint8  [edgeCount]    category    (cf. WayCategory)
//
// Les nœuds de bord (référencés par une arête mais géographiquement dans une
// tuile voisine) sont inclus dans chaque tuile qui les référence, avec leur
// vrai osmId → la fusion les déduplique automatiquement.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

import 'route_provider.dart';

const double _earthRadiusM = 6371000.0;
const double _microDeg = 1e6;

// ─── Tuile brute (vues sur les octets) ────────────────────────────────────────

class RawTile {
  final Int64List osmId;
  final Int32List latMicro;
  final Int32List lngMicro;
  final Uint32List csrStart;
  final Uint32List target;
  final Float32List dist;
  final Uint8List cat;

  RawTile({
    required this.osmId,
    required this.latMicro,
    required this.lngMicro,
    required this.csrStart,
    required this.target,
    required this.dist,
    required this.cat,
  });

  int get nodeCount => osmId.length;
  int get edgeCount => target.length;

  /// Parse les octets d'un fichier .wsr. Lève [FormatException] si invalide.
  static RawTile parse(Uint8List bytes) {
    final bd = bytes.buffer.asByteData(bytes.offsetInBytes);

    if (bytes.length < 16 ||
        bytes[0] != 0x57 || // 'W'
        bytes[1] != 0x53 || // 'S'
        bytes[2] != 0x52 || // 'R'
        bytes[3] != 0x31) { // '1'
      throw const FormatException('WSR: magic invalide');
    }
    final version = bytes[4];
    if (version != 1) {
      throw FormatException('WSR: version non supportée ($version)');
    }

    final nodeCount = bd.getUint32(8, Endian.little);
    final edgeCount = bd.getUint32(12, Endian.little);

    var off = 16;
    final osmId = Int64List(nodeCount);
    for (var i = 0; i < nodeCount; i++) {
      osmId[i] = bd.getInt64(off, Endian.little);
      off += 8;
    }
    final latMicro = Int32List(nodeCount);
    for (var i = 0; i < nodeCount; i++) {
      latMicro[i] = bd.getInt32(off, Endian.little);
      off += 4;
    }
    final lngMicro = Int32List(nodeCount);
    for (var i = 0; i < nodeCount; i++) {
      lngMicro[i] = bd.getInt32(off, Endian.little);
      off += 4;
    }
    final csrStart = Uint32List(nodeCount + 1);
    for (var i = 0; i <= nodeCount; i++) {
      csrStart[i] = bd.getUint32(off, Endian.little);
      off += 4;
    }
    final target = Uint32List(edgeCount);
    for (var i = 0; i < edgeCount; i++) {
      target[i] = bd.getUint32(off, Endian.little);
      off += 4;
    }
    final dist = Float32List(edgeCount);
    for (var i = 0; i < edgeCount; i++) {
      dist[i] = bd.getFloat32(off, Endian.little);
      off += 4;
    }
    final cat = Uint8List(edgeCount);
    for (var i = 0; i < edgeCount; i++) {
      cat[i] = bd.getUint8(off);
      off += 1;
    }

    return RawTile(
      osmId: osmId,
      latMicro: latMicro,
      lngMicro: lngMicro,
      csrStart: csrStart,
      target: target,
      dist: dist,
      cat: cat,
    );
  }
}

// ─── Arête fusionnée ──────────────────────────────────────────────────────────

class _Edge {
  final int to;          // index de nœud fusionné
  final double distM;
  final WayCategory cat;
  const _Edge(this.to, this.distM, this.cat);
}

// ─── Graphe fusionné + routage ────────────────────────────────────────────────

class RouteGraph {
  // Coordonnées des nœuds fusionnés.
  final List<double> _lat = [];
  final List<double> _lng = [];
  // Adjacence : pour chaque nœud, ses arêtes sortantes.
  final List<List<_Edge>> _adj = [];
  // osmId → index fusionné (dédup inter-tuiles).
  final Map<int, int> _osmToIdx = {};

  // Index spatial en grille pour le plus-proche-nœud.
  static const double _cellDeg = 0.005; // ≈ 500 m
  final Map<int, List<int>> _grid = {};

  bool get isEmpty => _adj.isEmpty;
  int get nodeCount => _adj.length;

  /// Fusionne une tuile dans le graphe. Idempotent sur les nœuds partagés
  /// (mêmes osmId).
  void mergeTile(RawTile tile) {
    // Résolution local → fusionné pour cette tuile.
    final localToMerged = Int32List(tile.nodeCount);
    for (var i = 0; i < tile.nodeCount; i++) {
      final id = tile.osmId[i];
      var idx = _osmToIdx[id];
      if (idx == null) {
        idx = _adj.length;
        _osmToIdx[id] = idx;
        _lat.add(tile.latMicro[i] / _microDeg);
        _lng.add(tile.lngMicro[i] / _microDeg);
        _adj.add(<_Edge>[]);
        _indexNode(idx);
      }
      localToMerged[i] = idx;
    }

    // Arêtes CSR.
    for (var u = 0; u < tile.nodeCount; u++) {
      final mu = localToMerged[u];
      final start = tile.csrStart[u];
      final end = tile.csrStart[u + 1];
      for (var e = start; e < end; e++) {
        final mv = localToMerged[tile.target[e]];
        _adj[mu].add(_Edge(
          mv,
          tile.dist[e],
          wayCategoryFromByte(tile.cat[e]),
        ));
      }
    }
  }

  // ── Index spatial ──────────────────────────────────────────────────────────

  int _cellKey(double lat, double lng) {
    final cx = (lng / _cellDeg).floor();
    final cy = (lat / _cellDeg).floor();
    // Combinaison stable dans un int (suffisant pour les latitudes terrestres).
    return (cy + 100000) * 1000000 + (cx + 100000);
  }

  void _indexNode(int idx) {
    final key = _cellKey(_lat[idx], _lng[idx]);
    (_grid[key] ??= <int>[]).add(idx);
  }

  /// Index du nœud le plus proche de [p], ou -1 si le graphe est vide.
  /// Cherche dans la cellule de [p] puis dans les anneaux concentriques
  /// jusqu'à trouver au moins un candidat.
  int nearestNode(LatLng p) {
    if (isEmpty) return -1;
    final cx = (p.longitude / _cellDeg).floor();
    final cy = (p.latitude / _cellDeg).floor();

    int best = -1;
    double bestD = double.infinity;

    for (var ring = 0; ring <= 20; ring++) {
      for (var dy = -ring; dy <= ring; dy++) {
        for (var dx = -ring; dx <= ring; dx++) {
          // Ne scanner que le périmètre de l'anneau courant.
          if (ring > 0 && dx.abs() != ring && dy.abs() != ring) continue;
          final key = (cy + dy + 100000) * 1000000 + (cx + dx + 100000);
          final cell = _grid[key];
          if (cell == null) continue;
          for (final idx in cell) {
            final d = _haversine(
              p.latitude, p.longitude, _lat[idx], _lng[idx]);
            if (d < bestD) {
              bestD = d;
              best = idx;
            }
          }
        }
      }
      // Si on a trouvé quelque chose et qu'on a scanné au moins un anneau
      // de marge, on peut s'arrêter (le vrai plus proche est très probablement
      // dans le rayon couvert).
      if (best != -1 && ring >= 1) break;
    }
    return best;
  }

  // ── A* ───────────────────────────────────────────────────────────────────

  /// Cherche le plus court chemin pondéré entre [startIdx] et [goalIdx].
  /// Renvoie la liste d'index de nœuds (départ → arrivée) et la distance
  /// physique cumulée, ou `null` si aucun chemin.
  _Path? _aStar(int startIdx, int goalIdx, RouteProfile profile) {
    if (startIdx < 0 || goalIdx < 0) return null;
    if (startIdx == goalIdx) return _Path([startIdx], 0.0);

    final n = nodeCount;
    final gScore = Float64List(n)..fillRange(0, n, double.infinity);
    final dScore = Float64List(n)..fillRange(0, n, 0.0); // distance physique
    final cameFrom = Int32List(n)..fillRange(0, n, -1);
    final closed = Uint8List(n);

    final minW = profile.minWeight;
    final goalLat = _lat[goalIdx];
    final goalLng = _lng[goalIdx];
    double h(int i) =>
        _haversine(_lat[i], _lng[i], goalLat, goalLng) * minW;

    final open = _MinHeap();
    gScore[startIdx] = 0.0;
    open.push(startIdx, h(startIdx));

    while (!open.isEmpty) {
      final current = open.pop();
      if (current == goalIdx) {
        return _reconstruct(cameFrom, current, dScore);
      }
      if (closed[current] == 1) continue;
      closed[current] = 1;

      for (final e in _adj[current]) {
        final w = profile.weightOf(e.cat);
        if (w == null) continue; // catégorie interdite
        if (closed[e.to] == 1) continue;

        final tentative = gScore[current] + e.distM * w;
        if (tentative < gScore[e.to]) {
          cameFrom[e.to] = current;
          gScore[e.to] = tentative;
          dScore[e.to] = dScore[current] + e.distM;
          open.push(e.to, tentative + h(e.to));
        }
      }
    }
    return null;
  }

  _Path _reconstruct(Int32List cameFrom, int goal, Float64List dScore) {
    final rev = <int>[];
    var cur = goal;
    while (cur != -1) {
      rev.add(cur);
      cur = cameFrom[cur];
    }
    return _Path(rev.reversed.toList(), dScore[goal]);
  }

  // ── API publique ─────────────────────────────────────────────────────────

  /// Calcule un tracé entre deux points géographiques. Snappe chaque point
  /// sur le nœud du graphe le plus proche.
  RouteResult? route(LatLng start, LatLng end, RouteProfile profile) {
    final s = nearestNode(start);
    final g = nearestNode(end);
    if (s < 0 || g < 0) return null;

    final path = _aStar(s, g, profile);
    if (path == null) return null;

    final pts = <LatLng>[start];
    for (final idx in path.nodes) {
      pts.add(LatLng(_lat[idx], _lng[idx]));
    }
    pts.add(end);

    final snapStart =
        _haversine(start.latitude, start.longitude, _lat[s], _lng[s]);
    final snapEnd =
        _haversine(end.latitude, end.longitude, _lat[g], _lng[g]);

    return RouteResult(
      points: pts,
      distanceM: path.distanceM + snapStart + snapEnd,
      snapDistanceM: snapStart + snapEnd,
    );
  }

  // ── Géodésie ───────────────────────────────────────────────────────────────

  static double _haversine(
      double lat1, double lon1, double lat2, double lon2) {
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLon = (lon2 - lon1) * math.pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) *
            math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return _earthRadiusM * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}

class _Path {
  final List<int> nodes;
  final double distanceM;
  const _Path(this.nodes, this.distanceM);
}

// ─── Tas binaire min (clé = score f) ──────────────────────────────────────────
//
// Tas léger sans dépendance. On autorise les doublons (lazy deletion) :
// un nœud déjà fermé est ignoré au pop côté A*.

class _MinHeap {
  final List<int> _ids = [];
  final List<double> _prio = [];

  bool get isEmpty => _ids.isEmpty;

  void push(int id, double prio) {
    _ids.add(id);
    _prio.add(prio);
    var i = _ids.length - 1;
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (_prio[parent] <= _prio[i]) break;
      _swap(i, parent);
      i = parent;
    }
  }

  int pop() {
    final top = _ids[0];
    final lastId = _ids.removeLast();
    final lastPrio = _prio.removeLast();
    if (_ids.isNotEmpty) {
      _ids[0] = lastId;
      _prio[0] = lastPrio;
      var i = 0;
      final n = _ids.length;
      while (true) {
        final l = 2 * i + 1;
        final r = 2 * i + 2;
        var smallest = i;
        if (l < n && _prio[l] < _prio[smallest]) smallest = l;
        if (r < n && _prio[r] < _prio[smallest]) smallest = r;
        if (smallest == i) break;
        _swap(i, smallest);
        i = smallest;
      }
    }
    return top;
  }

  void _swap(int a, int b) {
    final ti = _ids[a];
    _ids[a] = _ids[b];
    _ids[b] = ti;
    final tp = _prio[a];
    _prio[a] = _prio[b];
    _prio[b] = tp;
  }
}
