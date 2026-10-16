#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_root

bash "$SCRIPT_DIR/00-preflight.sh"
bash "$SCRIPT_DIR/05-add-ssh-key.sh"
bash "$SCRIPT_DIR/06-enable-pubkey-login.sh"
SSH_PORT="${SSH_PORT:-auto}" bash "$SCRIPT_DIR/20-install-fail2ban.sh"
bash "$SCRIPT_DIR/50-install-cert.sh"
