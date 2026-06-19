#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_root

SSH_PORT="${SSH_PORT:-55889}"
ALLOWED_SSH_CIDRS="${ALLOWED_SSH_CIDRS:-}"
ALLOW_HTTP="${ALLOW_HTTP:-yes}"
ALLOW_HTTPS="${ALLOW_HTTPS:-yes}"
CLOSE_PORT_22="${CLOSE_PORT_22:-no}"

validate_port "$SSH_PORT" SSH_PORT

if ! have_cmd ufw; then
  log "Installing ufw"
  install_packages ufw
fi

BACKUP_DIR="$(new_backup_dir ufw)"
backup_path /etc/ufw "$BACKUP_DIR"

ufw --force default deny incoming
ufw --force default allow outgoing

if [[ -n "$ALLOWED_SSH_CIDRS" ]]; then
  normalized_cidrs="${ALLOWED_SSH_CIDRS//,/ }"
  for cidr in $normalized_cidrs; do
    ufw allow from "$cidr" to any port "$SSH_PORT" proto tcp
  done
else
  ufw allow "$SSH_PORT/tcp"
  warn "SSH port $SSH_PORT is allowed from anywhere. Set ALLOWED_SSH_CIDRS to restrict it."
fi

if is_yes "$ALLOW_HTTP"; then
  ufw allow 80/tcp
fi

if is_yes "$ALLOW_HTTPS"; then
  ufw allow 443/tcp
fi

if is_yes "$CLOSE_PORT_22"; then
  ufw delete allow OpenSSH >/dev/null 2>&1 || true
  ufw delete allow ssh >/dev/null 2>&1 || true
  ufw delete allow 22 >/dev/null 2>&1 || true
  ufw delete allow 22/tcp >/dev/null 2>&1 || true
  ufw deny 22/tcp
  log "Port 22 was denied by UFW. Confirm cloud firewall/security group also matches your SSH_PORT."
else
  warn "Port 22 was not closed. Re-run with CLOSE_PORT_22=yes after testing the new SSH port."
fi

ufw --force enable

log "UFW configured"
log "Backup directory: $BACKUP_DIR"
echo
ufw status verbose
