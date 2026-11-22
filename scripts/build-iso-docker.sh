#!/bin/bash
# Gera a ISO dentro de um container Debian 12 (útil no GitHub Actions ou
# em qualquer Linux com Docker). O container precisa de --privileged
# porque o live-build monta /proc, /sys e /dev no chroot.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
docker run --rm --privileged -v "$ROOT:/src" -w /src debian:bookworm bash -c '
    set -e
    apt-get update -q
    apt-get install -y -q live-build curl unzip ca-certificates fontconfig
    ./scripts/build-iso.sh "$@"
' bash "$@"
