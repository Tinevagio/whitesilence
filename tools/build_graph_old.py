#!/usr/bin/env python3
# tools/build_graph.py
#
# Préprocesseur : convertit un extrait OpenStreetMap (.osm.pbf) en tuiles
# de routage .wsr 1°x1° consommées par WhiteSilence (lib/core/routing/).
#
# ── Installation ──────────────────────────────────────────────────────────────
#   pip install osmium
#
# ── Données ───────────────────────────────────────────────────────────────────
#   Télécharge un extrait depuis Geofabrik, p.ex. Rhône-Alpes :
#   https://download.geofabrik.de/europe/france/rhone-alpes-latest.osm.pbf
#
# ── Usage ─────────────────────────────────────────────────────────────────────
#   python3 build_graph.py rhone-alpes-latest.osm.pbf ./out_tiles
#
#   Puis pousse les .wsr produits dans <documents>/routing/ du device
#   (bundle d'assets, téléchargement in-app, adb push…).
#
# ── Format .wsr (little-endian) ───────────────────────────────────────────────
#   Voir l'en-tête de lib/core/routing/route_graph.dart — identique.

import sys
import os
import math
import struct
from collections import defaultdict

import osmium

# Catégories — DOIT correspondre à enum WayCategory côté Dart.
CAT_PATH    = 0  # footway / path / bridleway
CAT_TRACK   = 1  # track
CAT_SKITOUR = 2  # piste:type=skitour
CAT_ROAD    = 3  # route ouverte
CAT_STEPS   = 4  # steps
CAT_OTHER   = 5  # autre franchissable

# Highways qu'on ignore complètement (trop grandes / non pédestres).
SKIP_HIGHWAYS = {
    "motorway", "motorway_link", "trunk", "trunk_link",
    "primary", "primary_link", "construction", "proposed", "raceway",
}

ROAD_HIGHWAYS = {
    "residential", "unclassified", "service", "tertiary", "tertiary_link",
    "secondary", "secondary_link", "living_street", "road", "pedestrian",
    "cycleway",
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
    """Renvoie (category, keep). keep=False -> way ignoré."""
    piste = tags.get("piste:type")
    if piste and "skitour" in piste:
        return CAT_SKITOUR, True

    hw = tags.get("highway")
    if hw is None:
        # Pas de highway mais peut être une piste ski référencée autrement.
        return CAT_OTHER, False
    if hw in SKIP_HIGHWAYS:
        return CAT_OTHER, False
    if hw in ("footway", "path", "bridleway", "cycleway"):
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
    def __init__(self):
        super().__init__()
        # node osmId -> (lat, lon)
        self.nodes = {}
        # arêtes dirigées : (from_osm, to_osm, dist_m, category)
        self.edges = []

    def way(self, w):
        cat, keep = categorize(w.tags)
        if not keep:
            return
        # Accès interdit ?
        if w.tags.get("access") in ("private", "no"):
            return

        coords = []
        for n in w.nodes:
            if not n.location.valid():
                continue
            coords.append((n.ref, n.location.lat, n.location.lon))

        for i in range(len(coords) - 1):
            (id_a, la, loa) = coords[i]
            (id_b, lb, lob) = coords[i + 1]
            d = haversine(la, loa, lb, lob)
            if d <= 0:
                continue
            self.nodes[id_a] = (la, loa)
            self.nodes[id_b] = (lb, lob)
            # Bidirectionnel : on émet les deux sens (les sentiers se parcourent
            # dans les deux directions ; le profil ski peut interdire la
            # catégorie mais pas le sens).
            self.edges.append((id_a, id_b, d, cat))
            self.edges.append((id_b, id_a, d, cat))


def tile_key(lat_floor, lng_floor):
    la = ("N%02d" % abs(lat_floor)) if lat_floor >= 0 else ("S%02d" % abs(lat_floor))
    lo = ("E%03d" % abs(lng_floor)) if lng_floor >= 0 else ("W%03d" % abs(lng_floor))
    return la + lo


def write_tile(path, node_ids, node_coord, adj):
    """Écrit une tuile .wsr. node_ids = liste ordonnée d'osmId présents."""
    local_index = {oid: i for i, oid in enumerate(node_ids)}
    n = len(node_ids)

    # CSR
    csr_start = [0] * (n + 1)
    targets, dists, cats = [], [], []
    for i, oid in enumerate(node_ids):
        out = adj.get(oid, ())
        for (to_osm, d, cat) in out:
            # La cible doit exister dans la tuile (incluse comme nœud de bord).
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
        f.write(struct.pack("<BBH", 1, 0, 0))   # version, réservé, réservé
        f.write(struct.pack("<II", n, e))       # nodeCount, edgeCount
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
    if len(sys.argv) != 3:
        print("Usage: python3 build_graph.py <input.osm.pbf> <out_dir>")
        sys.exit(1)
    pbf, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)

    print("Lecture du PBF (avec index de localisation)…")
    b = GraphBuilder()
    # locations=True charge les coordonnées des nœuds référencés par les ways.
    b.apply_file(pbf, locations=True, idx="flex_mem")
    print(f"  {len(b.nodes)} nœuds, {len(b.edges)} arêtes dirigées")

    # Adjacence par osmId source.
    adj = defaultdict(list)
    for (a, c, d, cat) in b.edges:
        adj[a].append((c, d, cat))

    # Affectation des nœuds aux tuiles + inclusion des nœuds de bord :
    # pour chaque arête, le nœud SOURCE appartient à sa tuile géographique,
    # et le nœud CIBLE est inclus dans CETTE tuile aussi (nœud de bord).
    tile_nodes = defaultdict(set)   # tile_key -> set(osmId)
    for src, outs in adj.items():
        slat, slon = b.nodes[src]
        key = tile_key(math.floor(slat), math.floor(slon))
        tile_nodes[key].add(src)
        for (to_osm, _, _) in outs:
            tile_nodes[key].add(to_osm)  # nœud de bord

    print(f"Écriture de {len(tile_nodes)} tuiles dans {out_dir}…")
    for key, ids in sorted(tile_nodes.items()):
        node_ids = sorted(ids)
        path = os.path.join(out_dir, key + ".wsr")
        n, e = write_tile(path, node_ids, b.nodes, adj)
        print(f"  {key}.wsr — {n} nœuds / {e} arêtes")

    print("Terminé.")


if __name__ == "__main__":
    main()
