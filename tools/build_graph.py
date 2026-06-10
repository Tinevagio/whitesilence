#!/usr/bin/env python3
# tools/build_graph.py
#
# Préprocesseur : convertit un extrait OSM (.osm.pbf) en tuiles .wsr 1°x1°.
#
# ── Installation ──────────────────────────────────────────────────────────────
#   pip install osmium
#
# ── Usage ─────────────────────────────────────────────────────────────────────
#   # Toute la zone du .pbf :
#   python3 build_graph.py rhone-alpes.osm.pbf ./out_tiles
#
#   # Restreint à une bbox (RECOMMANDÉ pour les gros fichiers) :
#   python3 build_graph.py rhone-alpes.osm.pbf ./out_tiles 45.0,5.6,45.5,6.3
#                                                           lat_min,lon_min,lat_max,lon_max
#
#   Exemples de bbox utiles :
#     Chartreuse + Belledonne   : 45.0,5.6,45.5,6.3
#     Vanoise                   : 45.2,6.5,45.6,7.1
#     Aravis + Mont-Blanc       : 45.8,6.3,46.1,6.9
#
# ── Format .wsr (little-endian) ───────────────────────────────────────────────
#   Voir lib/core/routing/route_graph.dart (format identique).

import sys
import os
import math
import struct
from collections import defaultdict

import osmium

CAT_PATH    = 0
CAT_TRACK   = 1
CAT_SKITOUR = 2
CAT_ROAD    = 3
CAT_STEPS   = 4
CAT_OTHER   = 5

SKIP_HIGHWAYS = {
    "motorway", "motorway_link", "trunk", "trunk_link",
    "primary", "primary_link", "construction", "proposed", "raceway",
}
ROAD_HIGHWAYS = {
    "residential", "unclassified", "service", "tertiary", "tertiary_link",
    "secondary", "secondary_link", "living_street", "road", "pedestrian", "cycleway",
}

EARTH_R = 6371000.0


def haversine(lat1, lon1, lat2, lon2):
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (math.sin(dlat / 2) ** 2
         + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2))
         * math.sin(dlon / 2) ** 2)
    return EARTH_R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def categorize(tags):
    piste = tags.get("piste:type")
    if piste and "skitour" in piste:
        return CAT_SKITOUR, True
    hw = tags.get("highway")
    if hw is None:
        return CAT_OTHER, False
    if hw in SKIP_HIGHWAYS:
        return CAT_OTHER, False
    if hw in ("footway", "path", "bridleway"):
        return CAT_PATH, True
    if hw == "track":
        return CAT_TRACK, True
    if hw == "steps":
        return CAT_STEPS, True
    if hw in ROAD_HIGHWAYS:
        return CAT_ROAD, True
    if hw in ("trail", "via_ferrata"):
        return CAT_PATH, True
    return CAT_OTHER, True


class GraphBuilder(osmium.SimpleHandler):
    def __init__(self, bbox=None):
        """
        bbox : (lat_min, lon_min, lat_max, lon_max) ou None pour tout garder.
        Un way est gardé si AU MOINS UN nœud est dans la bbox.
        """
        super().__init__()
        self.bbox = bbox
        self.nodes = {}
        self.edges = []
        self._way_count = 0

    def _in_bbox(self, lat, lon):
        if self.bbox is None:
            return True
        la0, lo0, la1, lo1 = self.bbox
        return la0 <= lat <= la1 and lo0 <= lon <= lo1

    def way(self, w):
        cat, keep = categorize(w.tags)
        if not keep:
            return
        if w.tags.get("access") in ("private", "no"):
            return

        coords = []
        for n in w.nodes:
            if not n.location.valid():
                continue
            coords.append((n.ref, n.location.lat, n.location.lon))

        # Filtre bbox : ignore le way si aucun nœud n'est dans la zone.
        if self.bbox is not None:
            if not any(self._in_bbox(la, lo) for _, la, lo in coords):
                return

        for i in range(len(coords) - 1):
            (id_a, la, loa) = coords[i]
            (id_b, lb, lob) = coords[i + 1]
            d = haversine(la, loa, lb, lob)
            if d <= 0:
                continue
            self.nodes[id_a] = (la, loa)
            self.nodes[id_b] = (lb, lob)
            self.edges.append((id_a, id_b, d, cat))
            self.edges.append((id_b, id_a, d, cat))

        self._way_count += 1
        if self._way_count % 50000 == 0:
            print(f"  … {self._way_count} ways traités, {len(self.nodes)} nœuds")


def tile_key(lat_floor, lng_floor):
    la = ("N%02d" % abs(lat_floor)) if lat_floor >= 0 else ("S%02d" % abs(lat_floor))
    lo = ("E%03d" % abs(lng_floor)) if lng_floor >= 0 else ("W%03d" % abs(lng_floor))
    return la + lo


def write_tile(path, node_ids, node_coord, adj):
    local_index = {oid: i for i, oid in enumerate(node_ids)}
    n = len(node_ids)
    csr_start = [0] * (n + 1)
    targets, dists, cats = [], [], []
    for i, oid in enumerate(node_ids):
        for (to_osm, d, cat) in adj.get(oid, ()):
            ti = local_index.get(to_osm)
            if ti is None:
                continue
            targets.append(ti)
            dists.append(d)
            cats.append(cat)
        csr_start[i + 1] = len(targets)
    e = len(targets)
    with open(path, "wb") as f:
        f.write(b"WSR1")
        f.write(struct.pack("<BBH", 1, 0, 0))
        f.write(struct.pack("<II", n, e))
        for oid in node_ids:
            f.write(struct.pack("<q", oid))
        for oid in node_ids:
            lat, _ = node_coord[oid]
            f.write(struct.pack("<i", round(lat * 1e6)))
        for oid in node_ids:
            _, lon = node_coord[oid]
            f.write(struct.pack("<i", round(lon * 1e6)))
        for v in csr_start:
            f.write(struct.pack("<I", v))
        for t in targets:
            f.write(struct.pack("<I", t))
        for d in dists:
            f.write(struct.pack("<f", d))
        f.write(bytes(cats))
    return n, e


def main():
    if len(sys.argv) < 3:
        print("Usage: python3 build_graph.py <input.osm.pbf> <out_dir> [lat_min,lon_min,lat_max,lon_max]")
        print("  bbox ex (Chartreuse+Belledonne) : 45.0,5.6,45.5,6.3")
        print("  bbox ex (Vanoise)               : 45.2,6.5,45.6,7.1")
        print("  bbox ex (Aravis+Mont-Blanc)     : 45.8,6.3,46.1,6.9")
        sys.exit(1)

    pbf, out_dir = sys.argv[1], sys.argv[2]
    bbox = None
    if len(sys.argv) >= 4:
        parts = [float(x) for x in sys.argv[3].split(",")]
        bbox = tuple(parts)
        print(f"Filtre bbox : lat {bbox[0]}–{bbox[2]}, lon {bbox[1]}–{bbox[3]}")

    os.makedirs(out_dir, exist_ok=True)

    print("Lecture du PBF (avec index de localisation)…")
    b = GraphBuilder(bbox=bbox)
    b.apply_file(pbf, locations=True, idx="sparse_file_array,locations.idx")
    print(f"  {len(b.nodes)} nœuds, {len(b.edges)} arêtes dirigées")

    adj = defaultdict(list)
    for (a, c, d, cat) in b.edges:
        adj[a].append((c, d, cat))

    tile_nodes = defaultdict(set)
    for src, outs in adj.items():
        slat, slon = b.nodes[src]
        key = tile_key(math.floor(slat), math.floor(slon))
        tile_nodes[key].add(src)
        for (to_osm, _, _) in outs:
            tile_nodes[key].add(to_osm)

    print(f"Écriture de {len(tile_nodes)} tuiles dans {out_dir}…")
    for key, ids in sorted(tile_nodes.items()):
        node_ids = sorted(ids)
        path = os.path.join(out_dir, key + ".wsr")
        n, e = write_tile(path, node_ids, b.nodes, adj)
        print(f"  {key}.wsr — {n} nœuds / {e} arêtes")

    print("Terminé.")
    # Nettoie l'index disque temporaire
    idx_file = "locations.idx"
    if os.path.exists(idx_file):
        os.remove(idx_file)
        print(f"  (index temporaire {idx_file} supprimé)")


if __name__ == "__main__":
    main()
