#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/fengyunzaidushi/ssh-hardening-kit.git}"
BRANCH="${BRANCH:-main}"
ACTION="${1:-sshd}"

usage() {
  cat <<'EOF'
Usage:
  bash <(curl -Ls https://raw.githubusercontent.com/fengyunzaidushi/ssh-hardening-kit/main/install.sh) [action]

Actions:
  preflight   Show system, SSH, UFW, fail2ban status
  add-key     Add the default ssh-ed25519 public key to root authorized_keys
  sshd        Change SSH port to 55889 by default; keep root password login enabled
  fail2ban    Install/configure fail2ban for SSH port 55889 by default
  ufw         Configure UFW for SSH port 55889, HTTP, HTTPS
  rollback    Roll back the latest SSH config backup
  all         Run preflight, sshd, fail2ban, ufw

Examples:
  bash <(curl -Ls https://raw.githubusercontent.com/fengyunzaidushi/ssh-hardening-kit/main/install.sh) preflight
  sudo bash <(curl -Ls https://raw.githubusercontent.com/fengyunzaidushi/ssh-hardening-kit/main/install.sh) add-key
  sudo bash <(curl -Ls https://raw.githubusercontent.com/fengyunzaidushi/ssh-hardening-kit/main/install.sh) sshd
  sudo bash <(curl -Ls https://raw.githubusercontent.com/fengyunzaidushi/ssh-hardening-kit/main/install.sh) fail2ban
  sudo bash <(curl -Ls https://raw.githubusercontent.com/fengyunzaidushi/ssh-hardening-kit/main/install.sh) ufw
  sudo CLOSE_PORT_22=yes bash <(curl -Ls https://raw.githubusercontent.com/fengyunzaidushi/ssh-hardening-kit/main/install.sh) ufw
EOF
}

die() {
  printf '[ssh-hardening-kit][error] %s\n' "$*" >&2
  exit 1
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

install_git_if_possible() {
  if have_cmd git; then
    return
  fi

  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "git is not installed. Install git first or run with sudo so this bootstrap can install it."
  fi

  if have_cmd apt-get; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y git
    return
  fi

  if have_cmd dnf; then
    dnf install -y git
    return
  fi

  if have_cmd yum; then
    yum install -y git
    return
  fi

  die "git is not installed and no supported package manager was found"
}

run_script() {
  local script="$1"
  bash "$workdir/$script"
}

case "$ACTION" in
  -h | --help | help)
    usage
    exit 0
    ;;
  preflight | add-key | sshd | fail2ban | ufw | rollback | all)
    ;;
  *)
    usage
    die "Unknown action: $ACTION"
    ;;
esac

install_git_if_possible

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$tmpdir/ssh-hardening-kit" >/dev/null
workdir="$tmpdir/ssh-hardening-kit"

case "$ACTION" in
  preflight)
    run_script scripts/00-preflight.sh
    ;;
  add-key)
    run_script scripts/05-add-ssh-key.sh
    ;;
  sshd)
    run_script scripts/10-harden-sshd.sh
    ;;
  fail2ban)
    run_script scripts/20-install-fail2ban.sh
    ;;
  ufw)
    run_script scripts/30-configure-ufw.sh
    ;;
  rollback)
    run_script scripts/90-rollback-sshd.sh
    ;;
  all)
    run_script scripts/00-preflight.sh
    run_script scripts/05-add-ssh-key.sh
    run_script scripts/10-harden-sshd.sh
    run_script scripts/20-install-fail2ban.sh
    run_script scripts/30-configure-ufw.sh
    ;;
esac
