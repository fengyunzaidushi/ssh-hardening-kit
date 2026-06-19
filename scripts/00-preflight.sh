#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

echo "== System =="
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  printf 'OS: %s\n' "${PRETTY_NAME:-unknown}"
else
  uname -a
fi

printf 'User: %s\n' "$(id -un)"
printf 'Root: %s\n' "$([[ "${EUID:-$(id -u)}" -eq 0 ]] && echo yes || echo no)"

if have_cmd curl; then
  public_ip="$(curl -fsS --max-time 3 https://api.ipify.org 2>/dev/null || true)"
  [[ -n "$public_ip" ]] && printf 'Public IP: %s\n' "$public_ip"
fi

echo
echo "== SSH effective config =="
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  if test_sshd_config >/dev/null 2>&1; then
    "$(sshd_bin)" -T | awk '
      /^(port|passwordauthentication|kbdinteractiveauthentication|challengeresponseauthentication|permitrootlogin|pubkeyauthentication|maxauthtries|allowusers) / {print}
    '
  else
    warn "sshd -t failed; check /etc/ssh/sshd_config before changing SSH"
  fi
else
  warn "Run with sudo to show sshd -T effective config"
fi

echo
echo "== Listening SSH ports =="
if have_cmd ss; then
  ss -tlnp 2>/dev/null | awk 'NR == 1 || /sshd|:22\b|:55889\b/'
else
  warn "ss not found"
fi

echo
echo "== UFW =="
if have_cmd ufw; then
  ufw status verbose || true
else
  echo "ufw not installed"
fi

echo
echo "== Fail2ban =="
if have_cmd fail2ban-client; then
  fail2ban-client status || true
else
  echo "fail2ban not installed"
fi

echo
echo "== Recent SSH auth failures =="
if have_cmd journalctl; then
  journalctl -u ssh -u sshd --since "2 hours ago" --no-pager 2>/dev/null \
    | grep -E "Invalid user|Failed password|Accepted " \
    | tail -50 || true
else
  warn "journalctl not found"
fi
