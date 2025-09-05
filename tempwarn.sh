#!/bin/bash

VERSION="1.0.1"
REMOTE_VERSION_URL="https://raw.githubusercontent.com/krzysztofgasiewski/tempwarn/refs/heads/main/version.txt"
REMOTE_SCRIPT_URL="https://raw.githubusercontent.com/krzysztofgasiewski/tempwarn/refs/heads/main/tempwarn.sh"
SENSOR_NAME="Tctl"
LOGFILE="/var/log/temp-monitor.log"

install_path="/usr/local/bin/tempwarn.sh"
service_name="tempwarn.service"

if [[ "$1" == "--version" ]]; then
    echo "Tempwarn version $VERSION"
    exit 0
fi

if [[ "$1" == "--update" ]]; then
    echo "[*] Checking for updates..."
    remote_ver=$(curl -fsSL "$REMOTE_VERSION_URL" 2>/dev/null || echo "unknown")
    if [[ "$remote_ver" == "unknown" ]]; then
        echo "[!] Could not fetch remote version."
        exit 1
    fi
    if [[ "$VERSION" == "$remote_ver" ]]; then
        echo "[*] Already up to date (version $VERSION)."
        exit 0
    fi
    echo "[*] Updating from $VERSION to $remote_ver..."
    tmpfile=$(mktemp)
    if ! curl -fsSL "$REMOTE_SCRIPT_URL" -o "$tmpfile"; then
        echo "[!] Failed to download new script."
        exit 1
    fi
    sudo mv "$tmpfile" "$install_path"
    sudo chmod +x "$install_path"
    echo "[+] Installed Tempwarn $remote_ver at $install_path"
    if systemctl list-unit-files | grep -q "$service_name"; then
        echo "[*] Restarting systemd service..."
        sudo systemctl restart "$service_name"
    fi
    exit 0
fi

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOGFILE"
}

boot_beep() { beep -f 800 -l 100; beep -f 1000 -l 100; }
shutdown_beep() { beep -f 600 -l 300; }
crash_beep() { for i in {1..3}; do beep -f 400 -l 150; sleep 0.1; done; }
update_beep() { beep -f 1200 -l 200; sleep 0.1; beep -f 1400 -l 200; }

trap 'log "INFO: Tempwarn stopped"; shutdown_beep; exit 0' SIGINT SIGTERM
trap 'log "ERROR: Tempwarn crashed"; crash_beep; exit 1' ERR

remote_ver=$(curl -fsSL "$REMOTE_VERSION_URL" 2>/dev/null || echo "unknown")
if [[ "$remote_ver" != "unknown" ]]; then
    if [[ "$VERSION" != "$remote_ver" ]]; then
        log "WARNING: Tempwarn version $VERSION (latest is $remote_ver)"
        update_beep
    else
        log "INFO: Tempwarn up to date (version $VERSION)"
    fi
else
    log "NOTICE: Could not check latest version."
fi

log "INFO: Tempwarn started (version $VERSION)"
boot_beep

dismissed60=0
dismissed80=0

while true; do
    TEMP=$(sensors | awk -v name="$SENSOR_NAME" '$1 == name ":" {gsub(/\+|°C/, "", $2); print int($2)}')

    if [ -n "$TEMP" ]; then
        if [ "$TEMP" -ge 95 ]; then
            log "CRITICAL: $TEMP°C reached, shutting down."
            for i in {1..10}; do beep -f 1500 -l 50; sleep 0.05; done
            poweroff
        elif [ "$TEMP" -ge 90 ] && [ $dismissed80 -eq 0 ]; then
            log "WARNING: $TEMP°C entered ≥90°C mode."
            while [ "$TEMP" -ge 80 ]; do
                if [ -f /tmp/tempwarn.dismiss80 ]; then
                    dismissed80=1
                    log "NOTICE: User dismissed 80°C warning"
                    rm -f /tmp/tempwarn.dismiss80
                    break
                fi
                beep -f 1500 -l 500; sleep 0.5
                TEMP=$(sensors | awk -v name="$SENSOR_NAME" '$1 == name ":" {gsub(/\+|°C/, "", $2); print int($2)}')
            done
            if [ $dismissed80 -eq 0 ]; then
                log "INFO: Temperature dropped below 80°C, leaving ≥90°C mode."
            else
                dismissed80=0
            fi
        elif [ "$TEMP" -ge 60 ] && [ $dismissed60 -eq 0 ]; then
            log "NOTICE: $TEMP°C entered ≥60°C mode."
            while [ "$TEMP" -ge 60 ]; do
                if [ -f /tmp/tempwarn.dismiss60 ]; then
                    dismissed60=1
                    log "NOTICE: User dismissed 60°C warning"
                    rm -f /tmp/tempwarn.dismiss60
                    break
                fi
                beep -f 1000 -l 1000; sleep 0.5
                TEMP=$(sensors | awk -v name="$SENSOR_NAME" '$1 == name ":" {gsub(/\+|°C/, "", $2); print int($2)}')
            done
            if [ $dismissed60 -eq 0 ]; then
                log "INFO: Temperature dropped below 60°C, leaving ≥60°C mode."
            else
                dismissed60=0
            fi
        fi
    fi
    sleep 1
done