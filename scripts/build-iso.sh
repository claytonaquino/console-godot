#!/bin/bash
# Gera a imagem do pendrive (ISO híbrida) com Debian live-build.
# Precisa rodar num Debian/Ubuntu com internet (ou no GitHub Actions).
#
#   sudo apt install live-build curl unzip
#   sudo ./scripts/build-iso.sh              # imagem completa
#   sudo ./scripts/build-iso.sh --sem-nvidia # sem o driver NVIDIA 470 (menor)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK="$ROOT/.work/live"
OUT="$ROOT/out"
NVIDIA=1
for arg in "$@"; do
    case "$arg" in
        --sem-nvidia) NVIDIA=0 ;;
        *) echo "opção desconhecida: $arg" >&2; exit 2 ;;
    esac
done

if [ "$(id -u)" != 0 ]; then
    exec sudo -E "$0" "$@"
fi
command -v lb >/dev/null || { echo "Instale o live-build: sudo apt install live-build" >&2; exit 1; }

# 1) Executáveis Godot (exporta se ainda não existirem)
if [ ! -x "$ROOT/build/launcher/console-launcher.x86_64" ]; then
    if [ -n "${SUDO_USER:-}" ]; then
        sudo -u "$SUDO_USER" "$ROOT/scripts/export-godot.sh"
    else
        "$ROOT/scripts/export-godot.sh"
    fi
fi

# 2) Pasta de trabalho do live-build (o cache de pacotes é reaproveitado)
mkdir -p "$WORK"
cd "$WORK"
lb clean >/dev/null 2>&1 || true
rm -rf auto config
cp -a "$ROOT/os/auto" "$ROOT/os/config" .
# Garante permissões de execução (podem se perder se o zip passar pelo Windows)
chmod +x auto/* config/hooks/normal/* config/includes.chroot/opt/console/bin/*
mkdir -p config/includes.chroot/opt/console/launcher config/includes.chroot/opt/console/games
cp "$ROOT/build/launcher/console-launcher.x86_64" config/includes.chroot/opt/console/launcher/
cp -a "$ROOT"/build/games/. config/includes.chroot/opt/console/games/
if [ "$NVIDIA" = 0 ]; then
    rm -f config/hooks/normal/0100-nvidia-470.hook.chroot
fi

# 3) Gera a imagem
lb config
lb build

VERSION=$(cat "$ROOT/os/config/includes.chroot/opt/console/VERSION")
mkdir -p "$OUT"
ISO="$OUT/console-godot-$VERSION-$(date +%Y%m%d).iso"
mv -f live-image-amd64.hybrid.iso "$ISO"
[ -n "${SUDO_USER:-}" ] && chown "$SUDO_USER" "$ISO"
echo
echo ">> Imagem pronta: $ISO ($(du -h "$ISO" | cut -f1))"
echo ">> Grave no pendrive com o Rufus portátil, em modo DD."
