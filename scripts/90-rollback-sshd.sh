#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_root

CONFIG_FILE="${CONFIG_FILE:-/etc/ssh/sshd_config.d/00-ssh-hardening-kit.conf}"

if [[ -z "${BACKUP_DIR:-}" ]]; then
  BACKUP_DIR="$(find "$(backup_root)" -maxdepth 1 -type d -name '*-sshd' 2>/dev/null | sort | tail -1 || true)"
fi

if [[ -z "${BACKUP_DIR:-}" || ! -d "$BACKUP_DIR" ]]; then
  die "No sshd backup found. Set BACKUP_DIR=/root/ssh-hardening-backups/YYYYMMDD-HHMMSS-sshd"
fi

log "Restoring SSH config from: $BACKUP_DIR"

if [[ -f "$BACKUP_DIR/etc/ssh/sshd_config" ]]; then
  cp -a "$BACKUP_DIR/etc/ssh/sshd_config" /etc/ssh/sshd_config
else
  warn "Backup does not contain /etc/ssh/sshd_config"
fi

if [[ -d "$BACKUP_DIR/etc/ssh/sshd_config.d" ]]; then
  mkdir -p /etc/ssh/sshd_config.d
  cp -a "$BACKUP_DIR/etc/ssh/sshd_config.d/." /etc/ssh/sshd_config.d/
elif [[ -f "$CONFIG_FILE" ]]; then
  rm -f "$CONFIG_FILE"
fi

test_sshd_config
restart_sshd

log "SSH config rolled back and sshd reloaded"
echo
"$(sshd_bin)" -T | awk '
  /^(port|passwordauthentication|kbdinteractiveauthentication|challengeresponseauthentication|permitrootlogin|pubkeyauthentication|maxauthtries|allowusers) / {print}
'
