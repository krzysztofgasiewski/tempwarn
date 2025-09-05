#!/bin/bash
set -e

TEMPWARN_URL="https://raw.githubusercontent.com/krzysztofgasiewski/tempwarn/refs/heads/main/tempwarn.sh"
TARGET_BIN="/usr/local/bin/tempwarn.sh"
SERVICE_FILE="/etc/systemd/system/tempwarn.service"

# Require root
if [[ $EUID -ne 0 ]]; then
    echo "[!] Please run this installer with sudo or as root."
    exit 1
fi

# Dependencies
for dep in curl beep sensors; do
    if ! command -v $dep &>/dev/null; then
        echo "[!] Missing dependency: $dep"
        echo "    Install it with: sudo pacman -S $dep"
        exit 1
    fi
done

# Uninstall mode
if [[ "$1" == "--uninstall" ]]; then
    echo "[*] Stopping service..."
    systemctl stop tempwarn.service || true
    systemctl disable tempwarn.service || true
    rm -f "$TARGET_BIN" "$SERVICE_FILE"
    systemctl daemon-reload
    echo "[+] Tempwarn uninstalled."
    exit 0
fi

echo "[*] Downloading latest tempwarn.sh..."
curl -fsSL "$TEMPWARN_URL" -o /tmp/tempwarn.sh

if [ -f "$TARGET_BIN" ]; then
    cp "$TARGET_BIN" "$TARGET_BIN.bak.$(date +%s)" || true
    echo "[*] Backed up old tempwarn.sh"
fi

echo "[*] Installing to $TARGET_BIN..."
mv /tmp/tempwarn.sh "$TARGET_BIN"
chmod +x "$TARGET_BIN"

echo "[*] Writing systemd service..."
tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=CPU Temp Monitor with Alerts
After=multi-user.target

[Service]
ExecStart=$TARGET_BIN
Restart=always
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=tempwarn

[Install]
WantedBy=multi-user.target
EOF

echo "[*] Reloading systemd..."
systemctl daemon-reload

echo "[*] Enabling service..."
systemctl enable tempwarn.service

echo "[*] Starting service..."
systemctl restart tempwarn.service

echo "[+] Installation complete."
systemctl --no-pager --full status tempwarn.service | head -n 20