#!/bin/sh
# Teste rápido no console v0.1.1/v0.1.2 sem regravar o pendrive:
#   curl -sL https://raw.githubusercontent.com/claytonaquino/console-godot/main/os/fix-gpu.sh | sudo sh
if [ ! -d /sys/module/nvidia_drm ]; then
    echo "O driver NVIDIA não está carregado; nada a fazer."
    exit 1
fi
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/20-console-nvidia.conf <<'XEOF'
Section "Files"
    ModulePath "/usr/lib/nvidia/nvidia"
    ModulePath "/usr/lib/nvidia"
    ModulePath "/usr/lib/xorg/modules"
EndSection

Section "Device"
    Identifier "NVIDIA"
    Driver     "nvidia"
    Option     "NoLogo" "true"
EndSection
XEOF
echo nvidia-470 > /run/console-gpu
echo "Configuração gravada. Reiniciando a parte gráfica..."
sleep 2
pkill -x Xorg
