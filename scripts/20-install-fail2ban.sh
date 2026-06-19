#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_root

SSH_PORT="${SSH_PORT:-55889}"
FAIL2BAN_MAXRETRY="${FAIL2BAN_MAXRETRY:-5}"
FAIL2BAN_FINDTIME="${FAIL2BAN_FINDTIME:-10m}"
FAIL2BAN_BANTIME="${FAIL2BAN_BANTIME:-1d}"
FAIL2BAN_BACKEND="${FAIL2BAN_BACKEND:-systemd}"
FAIL2BAN_IGNORE_IPS="${FAIL2BAN_IGNORE_IPS:-}"
JAIL_FILE="${JAIL_FILE:-/etc/fail2ban/jail.d/sshd-hardening-kit.local}"

validate_port "$SSH_PORT" SSH_PORT

if ! have_cmd fail2ban-client; then
  log "Installing fail2ban"
  install_packages fail2ban
fi

BACKUP_DIR="$(new_backup_dir fail2ban)"
mkdir -p /etc/fail2ban/jail.d
backup_path "$JAIL_FILE" "$BACKUP_DIR"

ignore_ips="127.0.0.1/8 ::1"
if [[ -n "$FAIL2BAN_IGNORE_IPS" ]]; then
  ignore_ips="$ignore_ips $FAIL2BAN_IGNORE_IPS"
fi

{
  printf '# Managed by ssh-hardening-kit. Backup: %s\n' "$BACKUP_DIR"
  printf '[DEFAULT]\n'
  printf 'ignoreip = %s\n\n' "$ignore_ips"
  printf '[sshd]\n'
  printf 'enabled = true\n'
  printf 'filter = sshd\n'
  printf 'port = %s\n' "$SSH_PORT"
  printf 'backend = %s\n' "$FAIL2BAN_BACKEND"
  printf 'maxretry = %s\n' "$FAIL2BAN_MAXRETRY"
  printf 'findtime = %s\n' "$FAIL2BAN_FINDTIME"
  printf 'bantime = %s\n' "$FAIL2BAN_BANTIME"
} >"$JAIL_FILE"
chmod 0644 "$JAIL_FILE"

if have_cmd fail2ban-client; then
  fail2ban-client -t
fi

restart_service fail2ban

log "fail2ban sshd jail applied"
log "Backup directory: $BACKUP_DIR"
echo
fail2ban-client status || true
echo
fail2ban-client status sshd || true
