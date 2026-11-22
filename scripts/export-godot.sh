#!/bin/bash
# Exporta o launcher e todos os jogos (pasta games/) para build/.
# Baixa o Godot e os modelos de exportação na primeira vez (~1,3 GB, fica em .cache/).
set -euo pipefail

GODOT_VERSION=${GODOT_VERSION:-4.7.2}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CACHE="$ROOT/.cache/godot-$GODOT_VERSION"
GODOT=${GODOT:-$CACHE/godot}
TEMPLATES="$HOME/.local/share/godot/export_templates/$GODOT_VERSION.stable"
URL="https://github.com/godotengine/godot/releases/download/$GODOT_VERSION-stable"

mkdir -p "$CACHE"
if [ ! -x "$GODOT" ]; then
    echo ">> Baixando Godot $GODOT_VERSION..."
    curl -fL -o "$CACHE/godot.zip" "$URL/Godot_v$GODOT_VERSION-stable_linux.x86_64.zip"
    unzip -o -q "$CACHE/godot.zip" -d "$CACHE"
    mv "$CACHE/Godot_v$GODOT_VERSION-stable_linux.x86_64" "$GODOT"
    rm -f "$CACHE/godot.zip"
fi
if [ ! -f "$TEMPLATES/linux_release.x86_64" ]; then
    echo ">> Baixando modelos de exportação (só a parte Linux é guardada)..."
    curl -fL -o "$CACHE/templates.tpz" "$URL/Godot_v$GODOT_VERSION-stable_export_templates.tpz"
    mkdir -p "$TEMPLATES"
    unzip -o -j -q "$CACHE/templates.tpz" templates/linux_release.x86_64 templates/linux_debug.x86_64 templates/version.txt -d "$TEMPLATES"
    rm -f "$CACHE/templates.tpz"
fi

export_project() {  # pasta_do_projeto  arquivo_de_saída
    local dir=$1 out=$2
    mkdir -p "$(dirname "$out")"
    echo ">> Exportando $(basename "$dir")..."
    "$GODOT" --headless --path "$dir" --import >/dev/null 2>&1 || true
    "$GODOT" --headless --path "$dir" --export-release "Linux" "$out" 2>&1 | grep -iE "error" || true
    [ -x "$out" ] || { echo "ERRO: exportação falhou para $dir" >&2; exit 1; }
}

export_project "$ROOT/launcher" "$ROOT/build/launcher/console-launcher.x86_64"

rm -rf "$ROOT/build/games"
for game in "$ROOT"/games/*/; do
    [ -f "$game/project.godot" ] && [ -f "$game/game.json" ] || continue
    id=$(basename "$game")
    exe=$(sed -n 's/.*"exec" *: *"\([^"]*\)".*/\1/p' "$game/game.json")
    export_project "$game" "$ROOT/build/games/$id/${exe:-$id.x86_64}"
    # game.json vai com a versão do project.godot (config/version), usada pela Loja.
    version=$(sed -n 's/^config\/version="\(.*\)"/\1/p' "$game/project.godot")
    python3 - "$game/game.json" "$ROOT/build/games/$id/game.json" "${version:-0.0.0}" <<'PY'
import json, sys
src, dst, version = sys.argv[1:4]
data = json.load(open(src, encoding="utf-8"))
data["version"] = version
json.dump(data, open(dst, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
    [ -f "$game/cover.png" ] && cp "$game/cover.png" "$ROOT/build/games/$id/"
done
echo ">> Pronto: $ROOT/build"
