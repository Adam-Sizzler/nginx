#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="/var/log/geolite2.log"
DEST_DIR="/etc/nginx/geolite2"

mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$DEST_DIR"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $*" >> "$LOG_FILE"
}

log "Starting GeoLite2 database update"

FILES="
GeoLite2-Country.mmdb
GeoLite2-City.mmdb
GeoLite2-ASN.mmdb
"

for fname in $FILES; do
    url="https://github.com/P3TERX/GeoLite.mmdb/releases/latest/download/$fname"

    log "Downloading $url to $DEST_DIR/$fname"

    rm -f "$DEST_DIR/$fname.tmp"

curl -fsSL \
        --connect-timeout 20 \
        --max-time 300 \
        -o "$DEST_DIR/$fname.tmp" \
        "$url" || true

    if [ ! -s "$DEST_DIR/$fname.tmp" ]; then
        log "Download failed or file is empty: $fname"
        rm -f "$DEST_DIR/$fname.tmp"
        
        if [ -s "$DEST_DIR/$fname" ]; then
            log "Using existing database fallback for $fname"
            continue
        else
            log "Critical: No fallback database available for $fname"
            exit 1
        fi
    fi

    mv "$DEST_DIR/$fname.tmp" "$DEST_DIR/$fname"
    chmod 644 "$DEST_DIR/$fname"

    log "Successfully downloaded $fname"
done

for fname in $FILES; do
    if [ ! -s "$DEST_DIR/$fname" ]; then
        log "Required database is missing or empty: $DEST_DIR/$fname"
        exit 1
    fi
done

if command -v nginx >/dev/null 2>&1; then
    if [ -f /run/nginx.pid ] && kill -0 "$(cat /run/nginx.pid)" 2>/dev/null; then
        if nginx -s reload 2>> "$LOG_FILE"; then
            log "Nginx reloaded successfully"
        else
            log "Failed to reload nginx"
        fi
    else
        log "Nginx not running, will use new DB on next start"
    fi
fi

log "GeoLite2 update completed"
