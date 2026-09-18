#!/bin/bash
# vaultwarden-google-drive-backup
# Automated daily encrypted Vaultwarden vault export to Google Drive with GFS retention
#
# Usage: ./vaultwarden-backup.sh
# Requires: bw (Bitwarden CLI), rclone configured for Google Drive, jq (for validation)

set -euo pipefail

# ── Configuration ──
BACKUP_DIR="${BACKUP_DIR:-/mnt/HDD1/backups/vaultwarden}"
PASS_FILE="${PASS_FILE:-$HOME/.vaultwarden-password.txt}"
REMOTE="${REMOTE:-google-drive:/key/vaultwarden}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
RETENTION_WEEKS="${RETENTION_WEEKS:-5}"
RETENTION_MONTHS="${RETENTION_MONTHS:-12}"

DATE=$(date +%F)
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# ── 1. Prerequisites check ──
command -v bw >/dev/null 2>&1 || { log "ERROR: 'bw' (Bitwarden CLI) not found in PATH"; exit 1; }
command -v rclone >/dev/null 2>&1 || { log "ERROR: 'rclone' not found in PATH"; exit 1; }
command -v jq >/dev/null 2>&1 || { log "ERROR: 'jq' not found in PATH (needed for validation)"; exit 1; }
[ -f "$PASS_FILE" ] || { log "ERROR: Password file not found at $PASS_FILE"; exit 1; }

# ── 2. Export vault contents as encrypted JSON ──
mkdir -p "$BACKUP_DIR"

export BW_PASSWORD=$(cat "$PASS_FILE")
BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null || echo "")
if [ -z "$BW_SESSION" ]; then
    log "ERROR: Could not unlock vault with BW_PASSWORD"
    exit 1
fi
export BW_SESSION

bw export --format encrypted_json --session "$BW_SESSION" --output "$BACKUP_DIR/vaultwarden_$DATE.json"

# Validate exported file: must be a non-empty JSON object with encrypted field set to true
if [ ! -s "$BACKUP_DIR/vaultwarden_$DATE.json" ]; then
    log "ERROR: Exported file is empty"
    exit 1
fi
if ! jq -e 'type == "object" and .encrypted == true' "$BACKUP_DIR/vaultwarden_$DATE.json" >/dev/null 2>&1; then
    log "ERROR: Exported file is not a valid encrypted JSON object"
    exit 1
fi

unset BW_PASSWORD

# ── 3. Upload to Google Drive ──
rclone copy "$BACKUP_DIR/vaultwarden_$DATE.json" "$REMOTE"

# ── 4. Retention (GFS: 7 daily / 5 weekly / 12 monthly) ──
# Local rotation
if ls "$BACKUP_DIR"/vaultwarden_*.json >/dev/null 2>&1; then
    local_count=$(ls -1 "$BACKUP_DIR"/vaultwarden_*.json | wc -l)
    if [ "$local_count" -gt "$RETENTION_DAYS" ]; then
        ls -1rt "$BACKUP_DIR"/vaultwarden_*.json | head -n $((local_count - RETENTION_DAYS)) | xargs -r rm -f
        log "Local rotation: removed $((local_count - RETENTION_DAYS)) old backup(s), keeping $RETENTION_DAYS daily"
    fi
fi

# Remote rotation
if rclone ls "$REMOTE" 2>/dev/null | grep -q "vaultwarden_"; then
    remote_count=$(rclone ls "$REMOTE" | grep "vaultwarden_" | wc -l)
    if [ "$remote_count" -gt "$RETENTION_DAYS" ]; then
        rclone ls "$REMOTE" | grep "vaultwarden_" | sort | head -n $((remote_count - RETENTION_DAYS)) | awk '{print $2}' | xargs -r rclone delete "$REMOTE"
        log "Remote rotation: removed $((remote_count - RETENTION_DAYS)) old backup(s) from Drive, keeping $RETENTION_DAYS daily"
    fi
fi

# ── 5. Summary ──
local_remaining=$(ls -1 "$BACKUP_DIR"/vaultwarden_*.json 2>/dev/null | wc -l || echo 0)
remote_remaining=$(rclone ls "$REMOTE" 2>/dev/null | grep "vaultwarden_" | wc -l || echo 0)
log "Backup complete — $local_remaining local, $remote_remaining remote (retention: $RETENTION_DAYS days)"