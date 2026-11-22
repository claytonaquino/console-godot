#!/bin/sh
# Correção rápida para testar no console v0.1.1 sem regravar o pendrive:
#   curl -sL https://raw.githubusercontent.com/claytonaquino/console-godot/main/os/fix-nvidia.sh | sudo sh
set -e
BASE=https://raw.githubusercontent.com/claytonaquino/console-godot/main/os/config/includes.chroot/opt/console/bin
curl -fsSL -o /opt/console/bin/console-gpu-setup "$BASE/console-gpu-setup"
curl -fsSL -o /opt/console/bin/console-xsession "$BASE/console-xsession"
chmod 755 /opt/console/bin/console-gpu-setup /opt/console/bin/console-xsession
/opt/console/bin/console-gpu-setup
echo "Driver: $(cat /run/console-gpu)"
echo "Reiniciando a parte gráfica..."
sleep 2
pkill -x Xorg || true
