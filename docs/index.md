# Vaultwarden → Google Drive Backup (07-security-vaultwarden-backup)

Automated encrypted vault export to Google Drive, with GFS retention (7 daily / 5 weekly / 12 monthly).

## What's in this folder

| File | Purpose |
|------|---------|
| `install.sh` | Idempotent setup: installs latest `bw` + `rclone`, checks Drive OAuth, sets cron |
| `vaultwarden-backup.sh` | Non-interactive backup: export → Drive → rotate |
| `README.md` | Detailed setup, restore, and troubleshooting |
| `.gitignore` | Keeps secrets, logs, OS files out of git |

## Quick start (one command)

```bash
# Clone / enter folder
cd ~/dev/07-security-vaultwarden-backup

# Set up everything (installs latest bw + rclone, checks Drive, adds cron)
./install.sh

# First real backup (creates encrypted JSON + uploads to Drive)
PASS_FILE="$HOME/.vaultwarden-password.txt" ./vaultwarden-backup.sh
```

The password file must exist once before first run:

```bash
echo "your-master-password" > ~/.vaultwarden-password.txt
chmod 600 ~/.vaultwarden-password.txt
# Do NOT add this file to git
```

## Before first run: configure rclone for Google Drive

```bash
rclone config
# n (new remote) → name: google-drive → type: drive → client_id / client_secret
# Use the JSON from Google Cloud Console (see below for steps)
# Then authenticate via browser when prompted
```

If you don't have a Google Drive OAuth client yet:
- Go to https://console.cloud.google.com/ → APIs & Services → Credentials
- Create OAuth 2.0 Client ID (Desktop app) → download JSON
- Use those `client_id` / `client_secret` values in `rclone config`

## How it works (automatic)

- `bw unlock --passwordenv BW_PASSWORD --raw` → gets session token
- `bw export --format encrypted_json --session $BW_SESSION` → creates encrypted vault JSON
- `rclone copy ... google-drive:/key/vaultwarden/` → uploads
- Rotation trims old backups (7 daily kept, older removed locally + on Drive)
- Cron at 03:30 runs `vaultwarden-backup.sh` daily

## Restore from backup

```bash
# Download the JSON from Google Drive first (rclone copy from Drive to local)
rclone copy google-drive:/key/vaultwarden/vaultwarden_2026-09-09.json ./

# Import into Vaultwarden
bw login --apikey
bw unlock --passwordenv BW_PASSWORD
bw import --format encrypted_json vaultwarden_2026-09-09.json
```

Or open the file in Bitwarden web UI → Import.

## Configuration (via environment variables or defaults)

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKUP_DIR` | `/mnt/HDD1/backups/vaultwarden` | Where local backups live |
| `PASS_FILE` | `~/.vaultwarden-password.txt` | Vaultwarden master password file |
| `REMOTE` | `google-drive:/key/vaultwarden` | Google Drive path |
| `RETENTION_DAYS` | `7` | Daily backups to keep |

## Security rules

- `.gitignore` excludes `.vaultwarden-password.txt`, `*.env`, `rclone.conf`
- Master password never appears in logs (read from file into env, then unset)
- Encrypted JSON requires master password to decrypt
- rclone OAuth token stays in `~/.config/rclone/rclone.conf` (outside repo)

## Setup verification

```bash
# Check install
ls -la install.sh vaultwarden-backup.sh

# Check dependencies
command -v bw && command -v rclone

# Check cron
crontab -l | grep vaultwarden-backup

# Check first backup exists
ls -la /mnt/HDD1/backups/vaultwarden/vaultwarden_*.json 2>/dev/null || true
ls -la ~/dev/07-security-vaultwarden-backup/*.log 2>/dev/null || true
```

## License

MIT — for personal/home-lab use. Not for production secrets storage.