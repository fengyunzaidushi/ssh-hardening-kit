#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="${PROJECT_NAME:-ssh-hardening-kit}"

log() {
  printf '[%s] %s\n' "$PROJECT_NAME" "$*"
}

warn() {
  printf '[%s][warn] %s\n' "$PROJECT_NAME" "$*" >&2
}

die() {
  printf '[%s][error] %s\n' "$PROJECT_NAME" "$*" >&2
  exit 1
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "Run as root, for example: sudo bash $0"
  fi
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

is_yes() {
  case "${1:-}" in
    1 | y | Y | yes | YES | true | TRUE | on | ON) return 0 ;;
    *) return 1 ;;
  esac
}

backup_root() {
  printf '%s\n' "${BACKUP_ROOT:-/root/ssh-hardening-backups}"
}

new_backup_dir() {
  local suffix="$1"
  local base dir index
  base="$(backup_root)/$(date +%Y%m%d-%H%M%S)-${suffix}"
  dir="$base"
  index=1

  while [[ -e "$dir" ]]; do
    dir="${base}-${index}"
    index=$((index + 1))
  done

  mkdir -p "$dir"
  printf '%s\n' "$dir"
}

backup_path() {
  local src="$1"
  local dst_root="$2"

  if [[ -e "$src" || -L "$src" ]]; then
    mkdir -p "$dst_root$(dirname "$src")"
    cp -a "$src" "$dst_root$src"
    log "Backup: $src -> $dst_root$src"
  fi
}

validate_port() {
  local value="$1"
  local name="${2:-port}"

  if [[ ! "$value" =~ ^[0-9]+$ ]] || ((value < 1 || value > 65535)); then
    die "$name must be an integer between 1 and 65535, got: $value"
  fi
}

sshd_bin() {
  if have_cmd sshd; then
    command -v sshd
    return
  fi

  if [[ -x /usr/sbin/sshd ]]; then
    printf '%s\n' /usr/sbin/sshd
    return
  fi

  die "Cannot find sshd binary"
}

test_sshd_config() {
  mkdir -p /run/sshd
  "$(sshd_bin)" -t
}

reload_sshd() {
  if have_cmd systemctl; then
    if systemctl reload ssh >/dev/null 2>&1; then
      return
    fi
    if systemctl reload sshd >/dev/null 2>&1; then
      return
    fi
  fi

  if have_cmd service; then
    if service ssh reload >/dev/null 2>&1; then
      return
    fi
    if service sshd reload >/dev/null 2>&1; then
      return
    fi
  fi

  die "Could not reload ssh/sshd service"
}

restart_sshd() {
  if have_cmd systemctl; then
    disable_ssh_socket_if_active

    systemctl enable ssh >/dev/null 2>&1 || true
    systemctl enable sshd >/dev/null 2>&1 || true

    if systemctl restart ssh >/dev/null 2>&1; then
      return
    fi
    if systemctl restart sshd >/dev/null 2>&1; then
      return
    fi
  fi

  if have_cmd service; then
    if service ssh restart >/dev/null 2>&1; then
      return
    fi
    if service sshd restart >/dev/null 2>&1; then
      return
    fi
  fi

  die "Could not restart ssh/sshd service"
}

disable_ssh_socket_if_active() {
  local socket_name

  if ! have_cmd systemctl; then
    return
  fi

  for socket_name in ssh.socket sshd.socket; do
    if systemctl list-unit-files "$socket_name" --no-legend 2>/dev/null | awk '{print $1}' | grep -qx "$socket_name"; then
      if systemctl is-active --quiet "$socket_name" || systemctl is-enabled --quiet "$socket_name" 2>/dev/null; then
        log "Disabling $socket_name so sshd_config Port takes effect"
        systemctl stop "$socket_name" >/dev/null 2>&1 || true
        systemctl disable "$socket_name" >/dev/null 2>&1 || true
      fi
    fi
  done

  systemctl daemon-reload >/dev/null 2>&1 || true
}

restart_service() {
  local service_name="$1"

  if have_cmd systemctl; then
    systemctl enable --now "$service_name" >/dev/null 2>&1 || true
    if systemctl restart "$service_name" >/dev/null 2>&1; then
      return
    fi
  fi

  if have_cmd service; then
    if service "$service_name" restart >/dev/null 2>&1; then
      return
    fi
  fi

  die "Could not restart service: $service_name"
}

install_packages() {
  if have_cmd apt-get; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
    return
  fi

  if have_cmd dnf; then
    dnf install -y "$@"
    return
  fi

  if have_cmd yum; then
    yum install -y "$@"
    return
  fi

  die "No supported package manager found: apt-get, dnf, yum"
}

user_home() {
  local user="$1"
  getent passwd "$user" | awk -F: '{print $6}'
}

has_authorized_keys() {
  local user="$1"
  local home
  home="$(user_home "$user" 2>/dev/null || true)"

  [[ -n "$home" && -s "$home/.ssh/authorized_keys" ]]
}
