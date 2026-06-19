#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_root

NEW_SSH_PORT="${NEW_SSH_PORT:-55889}"
SSH_ALLOW_USERS="${SSH_ALLOW_USERS:-root}"
DISABLE_PASSWORD="${DISABLE_PASSWORD:-no}"
PERMIT_ROOT_LOGIN="${PERMIT_ROOT_LOGIN:-yes}"
MAX_AUTH_TRIES="${MAX_AUTH_TRIES:-3}"
CLIENT_ALIVE_INTERVAL="${CLIENT_ALIVE_INTERVAL:-300}"
CLIENT_ALIVE_COUNT_MAX="${CLIENT_ALIVE_COUNT_MAX:-2}"
CONFIG_FILE="${CONFIG_FILE:-/etc/ssh/sshd_config.d/00-ssh-hardening-kit.conf}"
INCLUDE_LINE='Include /etc/ssh/sshd_config.d/*.conf'

validate_port "$NEW_SSH_PORT" NEW_SSH_PORT

if [[ ! -f /etc/ssh/sshd_config ]]; then
  die "/etc/ssh/sshd_config does not exist"
fi

if is_yes "$DISABLE_PASSWORD" && ! is_yes "${ALLOW_NO_KEY:-no}"; then
  users_to_check=()
  if [[ -n "$SSH_ALLOW_USERS" ]]; then
    read -r -a users_to_check <<<"$SSH_ALLOW_USERS"
  elif [[ -n "${SUDO_USER:-}" && "${SUDO_USER:-}" != "root" ]]; then
    users_to_check=("$SUDO_USER")
  else
    users_to_check=("root")
  fi

  key_found=no
  for user in "${users_to_check[@]:-}"; do
    if has_authorized_keys "$user"; then
      key_found=yes
      break
    fi
  done

  if [[ "$key_found" != yes ]]; then
    die "DISABLE_PASSWORD=yes but no authorized_keys found for SSH_ALLOW_USERS/current sudo user. Set SSH_ALLOW_USERS, add keys, or set ALLOW_NO_KEY=yes if you accept lockout risk."
  fi
fi

BACKUP_DIR="$(new_backup_dir sshd)"
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
      re = "(Port|PasswordAuthentication|KbdInteractiveAuthentication|ChallengeResponseAuthentication|PermitRootLogin|PubkeyAuthentication|MaxAuthTries|ClientAliveInterval|ClientAliveCountMax)[[:space:]]+"
    }
    /^[[:space:]]*Match[[:space:]]/ { in_match = 1 }
    !in_match && $0 ~ "^[[:space:]]*" re && $0 !~ /^#/ {
      print "# disabled by ssh-hardening-kit: " $0
      next
    }
    { print }
  ' "$file" >"$tmp_file"
  cp "$tmp_file" "$file"
  rm -f "$tmp_file"
}

ensure_include_line
comment_global_directives /etc/ssh/sshd_config

shopt -s nullglob
for file in /etc/ssh/sshd_config.d/*.conf; do
  comment_global_directives "$file"
done
shopt -u nullglob

password_value=yes
kbd_value=yes
challenge_value=yes
if is_yes "$DISABLE_PASSWORD"; then
  password_value=no
  kbd_value=no
  challenge_value=no
fi

{
  printf '# Managed by ssh-hardening-kit. Backup: %s\n' "$BACKUP_DIR"
  printf 'Port %s\n' "$NEW_SSH_PORT"
  printf 'PubkeyAuthentication yes\n'
  printf 'PasswordAuthentication %s\n' "$password_value"
  printf 'KbdInteractiveAuthentication %s\n' "$kbd_value"
  printf 'ChallengeResponseAuthentication %s\n' "$challenge_value"
  printf 'PermitRootLogin %s\n' "$PERMIT_ROOT_LOGIN"
  printf 'MaxAuthTries %s\n' "$MAX_AUTH_TRIES"
  printf 'LoginGraceTime 30\n'
  printf 'ClientAliveInterval %s\n' "$CLIENT_ALIVE_INTERVAL"
  printf 'ClientAliveCountMax %s\n' "$CLIENT_ALIVE_COUNT_MAX"
  if [[ -n "$SSH_ALLOW_USERS" ]]; then
    printf 'AllowUsers %s\n' "$SSH_ALLOW_USERS"
  fi
} >"$CONFIG_FILE"
chmod 0644 "$CONFIG_FILE"

if ! test_sshd_config; then
  restore_backup
  test_sshd_config || true
  die "New sshd config failed validation and was rolled back"
fi

restart_sshd

log "SSH config applied"
log "Backup directory: $BACKUP_DIR"
log "Keep this SSH session open and test from a new terminal:"
first_user="${SSH_ALLOW_USERS%% *}"
if [[ -z "$first_user" ]]; then
  first_user="${SUDO_USER:-your_user}"
fi
log "ssh -p $NEW_SSH_PORT $first_user@YOUR_SERVER_IP"

echo
echo "Effective SSH settings:"
"$(sshd_bin)" -T | awk '
  /^(port|passwordauthentication|kbdinteractiveauthentication|challengeresponseauthentication|permitrootlogin|pubkeyauthentication|maxauthtries|allowusers) / {print}
'

if have_cmd ss; then
  echo
  echo "Listening SSH ports:"
  ss -tlnp 2>/dev/null | awk 'NR == 1 || /sshd|systemd/'

  if ! ss -tln 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]$NEW_SSH_PORT$"; then
    warn "SSH does not appear to be listening on $NEW_SSH_PORT yet"
  fi

  if ss -tln 2>/dev/null | awk '{print $4}' | grep -Eq '[:.]22$'; then
    warn "Port 22 is still listening. Check systemd ssh.socket/sshd.socket and cloud images."
  fi
fi
