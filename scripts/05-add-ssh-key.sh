#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_root

SSH_KEY_USER="${SSH_KEY_USER:-root}"
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY:-ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH535gEQjjfN8kGVCo4743cvNL5nih2gX+JgWts9Dqeo fengx@fxy-win11}"

if ! getent passwd "$SSH_KEY_USER" >/dev/null; then
  die "User does not exist: $SSH_KEY_USER"
fi

key_type="$(printf '%s\n' "$SSH_PUBLIC_KEY" | awk '{print $1}')"
key_body="$(printf '%s\n' "$SSH_PUBLIC_KEY" | awk '{print $2}')"

if [[ "$key_type" != "ssh-ed25519" || -z "$key_body" ]]; then
  die "SSH_PUBLIC_KEY must be a valid ssh-ed25519 public key"
fi

home_dir="$(user_home "$SSH_KEY_USER")"
if [[ -z "$home_dir" || ! -d "$home_dir" ]]; then
  die "Home directory not found for user $SSH_KEY_USER"
fi

ssh_dir="$home_dir/.ssh"
authorized_keys="$ssh_dir/authorized_keys"

BACKUP_DIR="$(new_backup_dir authorized-keys)"
backup_path "$authorized_keys" "$BACKUP_DIR"

mkdir -p "$ssh_dir"
touch "$authorized_keys"

if awk -v body="$key_body" '$2 == body { found = 1 } END { exit found ? 0 : 1 }' "$authorized_keys"; then
  log "Public key already exists in $authorized_keys"
else
  printf '%s\n' "$SSH_PUBLIC_KEY" >>"$authorized_keys"
  log "Public key added to $authorized_keys"
fi

owner_group="$(id -gn "$SSH_KEY_USER")"
chown "$SSH_KEY_USER:$owner_group" "$ssh_dir" "$authorized_keys"
chmod 700 "$ssh_dir"
chmod 600 "$authorized_keys"

log "Permissions fixed: $ssh_dir=700, $authorized_keys=600"
log "Backup directory: $BACKUP_DIR"

