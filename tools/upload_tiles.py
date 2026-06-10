#!/usr/bin/env python3
# tools/upload_tiles.py
#
# Upload des tuiles .wsr vers Supabase Storage (bucket 'routing-tiles').
#
# ── Prérequis ─────────────────────────────────────────────────────────────────
#   pip install supabase
#
# ── Configuration ─────────────────────────────────────────────────────────────
#   Crée un fichier .env à la racine du projet (ou exporte les variables) :
#     SUPABASE_URL=https://xxxx.supabase.co
#     SUPABASE_SERVICE_KEY=eyJh...   (clé service, pas la clé anon)
#
#   Dans Supabase Dashboard :
#   1. Storage → New bucket → nom : 'routing-tiles' → Public : OUI
#   2. Settings → API → copie l'URL et la service_role key
#
# ── Usage ─────────────────────────────────────────────────────────────────────
#   python3 tools/upload_tiles.py ./out_tiles
#   python3 tools/upload_tiles.py ./out_tiles N45E005.wsr   # une seule tuile

import os
import sys
from pathlib import Path

try:
    from supabase import create_client
except ImportError:
    print("pip install supabase")
    sys.exit(1)

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass  # sans python-dotenv, on lit les vars d'environnement directement

BUCKET = "routing-tiles"


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 tools/upload_tiles.py <tiles_dir> [fichier.wsr ...]")
        sys.exit(1)

    tiles_dir = Path(sys.argv[1])
    if not tiles_dir.exists():
        print(f"Dossier introuvable : {tiles_dir}")
        sys.exit(1)

    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_KEY")
    if not url or not key:
        print("SUPABASE_URL et SUPABASE_SERVICE_KEY doivent être définis.")
        print("  export SUPABASE_URL=https://xxxx.supabase.co")
        print("  export SUPABASE_SERVICE_KEY=eyJh...")
        sys.exit(1)

    client = create_client(url, key)

    # Sélection des fichiers à uploader
    if len(sys.argv) >= 3:
        files = [tiles_dir / f for f in sys.argv[2:]]
    else:
        files = sorted(tiles_dir.glob("*.wsr"))

    if not files:
        print(f"Aucun .wsr trouvé dans {tiles_dir}")
        sys.exit(1)

    print(f"Upload de {len(files)} tuile(s) vers bucket '{BUCKET}'…\n")

    for path in files:
        if not path.exists():
            print(f"  ✗ {path.name} introuvable")
            continue

        size_mb = path.stat().st_size / 1_048_576
        print(f"  → {path.name} ({size_mb:.1f} MB)… ", end="", flush=True)

        with open(path, "rb") as f:
            data = f.read()

        try:
            # upsert=True : écrase si déjà présent
            client.storage.from_(BUCKET).upload(
                path=path.name,
                file=data,
                file_options={
                    "content-type": "application/octet-stream",
                    "upsert": "true",
                },
            )
            print("✓")
        except Exception as e:
            print(f"✗ erreur : {e}")

    print("\nTerminé.")
    print(f"\nURL publique des tuiles :")
    print(f"  {url}/storage/v1/object/public/{BUCKET}/<KEY>.wsr")
    print(f"\nMets cette URL dans ton .env Flutter :")
    print(f"  SUPABASE_ROUTING_BASE_URL={url}/storage/v1/object/public/{BUCKET}")


if __name__ == "__main__":
    main()
