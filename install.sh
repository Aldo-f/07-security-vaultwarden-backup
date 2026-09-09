#!/bin/bash
# install.sh — idempotent setup for vaultwarden-google-drive-backup
# One-file setup: installs bw CLI + rclone (latest versions), checks rclone OAuth, sets cron
# Usage: ./install.sh [--test|-t]
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="vaultwarden-backup.sh"
PASS_FILE_DEFAULT="${HOME}/.vaultwarden-password.txt"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] install: $*"; }

# 1. Dependencies (idempotent) — always fetch latest from official sources ------
install_deps() {
    # bw (Bitwarden CLI) — install only if missing; fetch latest release from GitHub
    if ! command -v bw >/dev/null 2>&1; then
        log "Installing Bitwarden CLI (bw) — latest release..."
        local latest_tag arch zip_url
        latest_tag=$(curl -fsSL https://api.github.com/repos/bitwarden/clients/releases/latest \
            | grep -E '"tag_name"' | sed 's/.*"tag_name": *"//;s/".*//')
        arch=$(uname -m)
        case "$arch" in
            aarch64) zip_url="https://github.com/bitwarden/clients/releases/download/${latest_tag}/bw-linux-${latest_tag}.zip" ;;
            x86_64)  zip_url="https://github.com/bitwarden/clients/releases/download/${latest_tag}/bw-linux-${latest_tag}.zip" ;;
            *)       log "ERROR: unsupported arch $arch"; exit 1 ;;
        esac
        mkdir -p /tmp/bw-install
        curl -fsSL -o /tmp/bw-install/bw.zip "$zip_url"
        unzip -o /tmp/bw-install/bw.zip -d /tmp/bw-install
        chmod +x /tmp/bw-install/bw-linux-${latest_tag}/bw
        sudo mv /tmp/bw-install/bw-linux-${latest_tag}/bw /usr/local/bin/ || \
            mv /tmp/bw-install/bw-linux-${latest_tag}/bw ~/bin/ 2>/dev/null || \
            cp /tmp/bw-install/bw-linux-${latest_tag}/bw /home/aldo/.local/bin/
        log "bw installed: $(bw --version | head -1)"
    else
        log "bw already installed: $(bw --version | head -1)"
    fi

    # rclone — install only if missing; official installer always fetches latest
    if ! command -v rclone >/dev/null 2>&1; then
        log "Installing rclone — latest release..."
        curl -fsSL https://rclone.org/install.sh | sudo bash
    else
        log "rclone already installed: $(rclone version | head -1)"
    fi
}

# 2. Prerequisites (warn if missing; never block) -----------------------------
check_prereqs() {
    if ! rclone listremotes 2>/dev/null | grep -q .; then
        log "WARNING: rclone has no configured remotes. Run: rclone config"
        log "         (configure remote 'google-drive' for Drive upload)"
    else
        log "rclone remotes: $(rclone listremotes | tr '\n' ' ')"
    fi

    PASS_FILE="${PASS_FILE:-$PASS_FILE_DEFAULT}"
    if [ ! -f "$PASS_FILE" ]; then
        log "WARNING: Password file missing at $PASS_FILE"
        log "         Create with: echo 'master-password' > $PASS_FILE && chmod 600 $PASS_FILE"
        log "         (do NOT add this file to git)"
    else
        log "Password file OK: $PASS_FILE (perms: $(stat -c '%a' $PASS_FILE))"
    fi
}

# 3. Cron (idempotent — only adds if tag not present) ------------------------
setup_cron() {
    CRON_TAG="# HOME: vaultwarden-backup"
    CRON_LINE="30 3 * * * $PROJECT_DIR/$SCRIPT >> $PROJECT_DIR/vaultwarden-backup.log 2>&1"

    if crontab -l 2>/dev/null | grep -q "$CRON_TAG"; then
        log "Cron entry already present"
        return 0
    fi

    local current
    current="$(crontab -l 2>/dev/null | grep -v "$CRON_TAG" | grep -v "$SCRIPT" || true)"
    { echo "$current"; echo "$CRON_TAG"; echo "$CRON_LINE"; } | grep -v '^$' | crontab -
    log "Cron entry added (daily 03:30) → $CRON_LINE"
}

# 4. Test run (optional, only with --test) ------------------------------------
test_run() {
    if [ ! -x "$PROJECT_DIR/$SCRIPT" ]; then
        log "ERROR: $SCRIPT not executable (chmod +x $PROJECT_DIR/$SCRIPT)"
        exit 1
    fi
    log "Running test backup..."
    "$PROJECT_DIR/$SCRIPT"
    log "Test OK — check $BACKUP_DIR and Drive"
}

# --- Main --------------------------------------------------------------------
case "${1:-}" in
    --test|-t)
        install_deps
        check_prereqs
        setup_cron
        test_run
        log "Setup complete with test run"
        ;;
    *)
        install_deps
        check_prereqs
        setup_cron
        log "Setup complete. Run: $PROJECT_DIR/$SCRIPT"
        log "Or wait for daily cron at 03:30."
        log "Run with --test to verify end-to-end (includes real export + upload)."
        ;;
esac