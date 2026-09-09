# 07-security-vaultwarden-backup — Automated Vaultwarden → Google Drive Backup

Encrypted daily backup of your Vaultwarden vault contents to Google Drive, with GFS retention (7 daily / 5 weekly / 12 monthly).

## Features

- **Non-interactive**: runs unattended via cron
- **Encrypted**: exports vault as encrypted JSON (master password required)
- **Two destinations**: local disk + Google Drive (via rclone)
- **Retention**: keeps 7 daily backups, trims older ones automatically
- **Zero secrets in repo**: master password stored in a protected file outside git

## Quick Start

```bash
# 1. Clone this repo
git clone https://github.com/Aldo-f/07-security-vaultwarden-backup.git
cd 07-security-vaultwarden-backup

# 2. Install dependencies
sudo apt-get install -y unzip
curl -fsSL https://rclone.org/install.sh | sudo bash
npm install -g @bitwarden/cli

# 3. Configure rclone for Google Drive
rclone config

# 4. Create password file (gitignored)
echo "your-master-password" > ~/.vaultwarden-password.txt
chmod 600 ~/.vaultwarden-password.txt

# 5. Run once to test
./vaultwarden-backup.sh

# 6. Schedule daily at 03:30
crontab -l | { cat; echo "# HOME: vaultwarden-backup"; echo "30 3 * * * $PWD/vaultwarden-backup.sh >> $PWD/vaultwarden-backup.log 2>&1"; } | crontab -
```

## Configuration

All settings are environment variables or defaults:

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKUP_DIR` | `/mnt/HDD1/backups/vaultwarden` | Local backup directory |
| `PASS_FILE` | `~/.vaultwarden-password.txt` | Path to Vaultwarden master password file |
| `REMOTE` | `google-drive:/key/vaultwarden` | rclone remote destination |
| `RETENTION_DAYS` | `7` | Number of daily backups to keep |

## Restore

```bash
# Import encrypted JSON back into Vaultwarden
bw login --apikey
bw unlock --passwordenv BW_PASSWORD
bw import --format json --vaultwarden_encrypted_json vaultwarden_2026-09-09.json
```

## Security

- Master password never stored in repo or logs
- `~/.vaultwarden-password.txt` must be `chmod 600`
- rclone OAuth token stored in `~/.config/rclone/rclone.conf`
- Encrypted JSON requires master password to decrypt

## License

MIT