#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_root

SSH_KEY_USER="${SSH_KEY_USER:-root}"
PERMIT_ROOT_LOGIN="${PERMIT_ROOT_LOGIN:-yes}"
AUTHORIZED_KEYS_FILE="${AUTHORIZED_KEYS_FILE:-.ssh/authorized_keys .ssh/authorized_keys2}"
CONFIG_FILE="${CONFIG_FILE:-/etc/ssh/sshd_config.d/00-enable-pubkey-login.conf}"
INCLUDE_LINE='Include /etc/ssh/sshd_config.d/*.conf'
FIX_KEY_PERMISSIONS="${FIX_KEY_PERMISSIONS:-yes}"

if [[ ! -f /etc/ssh/sshd_config ]]; then
  die "/etc/ssh/sshd_config does not exist"
fi

if ! getent passwd "$SSH_KEY_USER" >/dev/null; then
  die "User does not exist: $SSH_KEY_USER"
fi

BACKUP_DIR="$(new_backup_dir enable-pubkey)"
backup_path /etc/ssh/sshd_config "$BACKUP_DIR"
mkdir -p /etc/ssh/sshd_config.d

shopt -s nullglob
for file in /etc/ssh/sshd_config.d/*.conf; do
  backup_path "$file" "$BACKUP_DIR"
done
shopt -u nullglob

restore_backup() {
  warn "Restoring SSH config from $BACKUP_DIR"
  if [[ -f "$BACKUP_DIR/etc/ssh/sshd_config" ]]; then
    cp -a "$BACKUP_DIR/etc/ssh/sshd_config" /etc/ssh/sshd_config
  fi
  if [[ -d "$BACKUP_DIR/etc/ssh/sshd_config.d" ]]; then
    cp -a "$BACKUP_DIR/etc/ssh/sshd_config.d/." /etc/ssh/sshd_config.d/
  else
    rm -f "$CONFIG_FILE"
  fi
}

ensure_include_line() {
  if grep -Eiq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config; then
    return
  fi

  tmp_file="$(mktemp)"
  {
    printf '%s\n' "$INCLUDE_LINE"
    cat /etc/ssh/sshd_config
  } >"$tmp_file"
  cp "$tmp_file" /etc/ssh/sshd_config
  rm -f "$tmp_file"
  log "Added sshd_config Include line for /etc/ssh/sshd_config.d/*.conf"
}

comment_global_directives() {
  local file="$1"
  local tmp_file

  [[ -f "$file" ]] || return
  [[ "$file" == "$CONFIG_FILE" ]] && return

  tmp_file="$(mktemp)"
  awk '
    BEGIN {
      in_match = 0
      re = "(PubkeyAuthentication|AuthorizedKeysFile|PermitRootLogin|AuthenticationMethods)[[:space:]]+"
    }
    /^[[:space:]]*Match[[:space:]]/ { in_match = 1 }
    !in_match && $0 ~ "^[[:space:]]*" re && $0 !~ /^#/ {
      print "# disabled by ssh-hardening-kit enable-pubkey: " $0
      next
    }
    { print }
  ' "$file" >"$tmp_file"
  cp "$tmp_file" "$file"
  rm -f "$tmp_file"
}

fix_authorized_keys_permissions() {
  local home_dir ssh_dir authorized_keys owner_group

  home_dir="$(user_home "$SSH_KEY_USER")"
  if [[ -z "$home_dir" || ! -d "$home_dir" ]]; then
    warn "Home directory not found for user $SSH_KEY_USER"
    return
  fi

  ssh_dir="$home_dir/.ssh"
  authorized_keys="$ssh_dir/authorized_keys"

  if [[ ! -d "$ssh_dir" ]]; then
    warn "$ssh_dir does not exist. Run add-key first or create authorized_keys manually."
    return
  fi

  owner_group="$(id -gn "$SSH_KEY_USER")"
  chown "$SSH_KEY_USER:$owner_group" "$ssh_dir"
  chmod 700 "$ssh_dir"

  if [[ -f "$authorized_keys" ]]; then
    chown "$SSH_KEY_USER:$owner_group" "$authorized_keys"
    chmod 600 "$authorized_keys"
  else
    warn "$authorized_keys does not exist. Public key login needs an authorized_keys file."
  fi
}

ensure_include_line
comment_global_directives /etc/ssh/sshd_config

shopt -s nullglob
for file in /etc/ssh/sshd_config.d/*.conf; do
  comment_global_directives "$file"
done
shopt -u nullglob

{
  printf '# Managed by ssh-hardening-kit enable-pubkey. Backup: %s\n' "$BACKUP_DIR"
  printf 'PubkeyAuthentication yes\n'
  printf 'AuthorizedKeysFile %s\n' "$AUTHORIZED_KEYS_FILE"
  if [[ "$SSH_KEY_USER" == "root" ]]; then
    printf 'PermitRootLogin %s\n' "$PERMIT_ROOT_LOGIN"
  fi
} >"$CONFIG_FILE"
chmod 0644 "$CONFIG_FILE"

if is_yes "$FIX_KEY_PERMISSIONS"; then
  fix_authorized_keys_permissions
fi

if ! test_sshd_config; then
  restore_backup
  test_sshd_config || true
  die "New sshd config failed validation and was rolled back"
fi

restart_sshd

log "SSH public key login enabled"
log "Config file: $CONFIG_FILE"
log "Backup directory: $BACKUP_DIR"

if ! has_authorized_keys "$SSH_KEY_USER"; then
  warn "No authorized_keys found for $SSH_KEY_USER. Run add-key before testing key login."
fi

echo
echo "Effective SSH settings:"
"$(sshd_bin)" -T -C "user=$SSH_KEY_USER,host=localhost,addr=127.0.0.1" | awk '
  /^(port|pubkeyauthentication|authorizedkeysfile|permitrootlogin|passwordauthentication|kbdinteractiveauthentication|challengeresponseauthentication|authenticationmethods|allowusers|maxauthtries) / {print}
'

echo
log "Keep this SSH session open and test from a new terminal:"
log "ssh -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 -p <PORT> $SSH_KEY_USER@YOUR_SERVER_IP"
