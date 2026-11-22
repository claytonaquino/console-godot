# Ao entrar automaticamente no tty1, o usuário "console" abre direto o launcher.
# Para usar só o terminal, entre em outro tty (Ctrl+Alt+F2).
if [ "$(id -un)" = "console" ] && [ -z "${DISPLAY:-}" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec /opt/console/bin/console-session
fi
