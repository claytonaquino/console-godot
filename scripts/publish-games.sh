#!/bin/bash
# Empacota os jogos exportados (build/games) e gera o catálogo da Loja:
#   <saída>/jogos/catalog.json
#   <saída>/jogos/<id>-<versão>.tar.gz
# Uso: scripts/publish-games.sh <pasta_de_saída> <url_base_dos_arquivos>
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:?pasta de saída}
BASE_URL=${2:?url base}
mkdir -p "$OUT/jogos"
python3 - "$ROOT/build/games" "$OUT/jogos" "$BASE_URL" <<'PY'
import hashlib, json, os, sys, tarfile, datetime
games_dir, out_dir, base = sys.argv[1:4]
catalog = {"updated": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "games": []}
for gid in sorted(os.listdir(games_dir)):
    gdir = os.path.join(games_dir, gid)
    manifest = os.path.join(gdir, "game.json")
    if not os.path.isfile(manifest):
        continue
    data = json.load(open(manifest, encoding="utf-8"))
    version = data.get("version", "0.0.0")
    name = f"{gid}-{version}.tar.gz"
    path = os.path.join(out_dir, name)
    with tarfile.open(path, "w:gz") as tar:
        tar.add(gdir, arcname=gid)
    sha = hashlib.sha256(open(path, "rb").read()).hexdigest()
    catalog["games"].append({
        "id": data.get("id", gid), "title": data.get("title", gid),
        "description": data.get("description", ""), "color": data.get("color", "#2a6f97"),
        "version": version, "url": f"{base}/jogos/{name}",
        "sha256": sha, "size": os.path.getsize(path),
    })
    print(f"{gid} {version} {os.path.getsize(path)//1048576} MB")
json.dump(catalog, open(os.path.join(out_dir, "catalog.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
