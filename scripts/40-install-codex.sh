#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_root

CODEX_PACKAGE_SPEC="${CODEX_PACKAGE_SPEC:-@openai/codex@latest}"
MIN_NODE_MAJOR="${MIN_NODE_MAJOR:-22}"
NODE_DIST_BASE="${NODE_DIST_BASE:-https://nodejs.org/dist}"
CODEX_RUN_USER="${CODEX_RUN_USER:-${SUDO_USER:-}}"
NODE_TMPDIR=""

if [[ ! "$MIN_NODE_MAJOR" =~ ^[0-9]+$ ]]; then
  die "MIN_NODE_MAJOR must be a positive integer, got: $MIN_NODE_MAJOR"
fi

cleanup() {
  if [[ -n "$NODE_TMPDIR" && -d "$NODE_TMPDIR" ]]; then
    rm -rf -- "$NODE_TMPDIR"
  fi
}
trap cleanup EXIT

node_major() {
  node --version 2>/dev/null | sed -E 's/^v([0-9]+).*/\1/'
}

install_latest_node_lts() {
  local machine_arch node_arch node_version archive download_base install_root install_dir binary

  machine_arch="$(uname -m)"
  case "$machine_arch" in
    x86_64 | amd64) node_arch="x64" ;;
    aarch64 | arm64) node_arch="arm64" ;;
    *) die "Unsupported CPU architecture for automatic Node.js installation: $machine_arch" ;;
  esac

  NODE_TMPDIR="$(mktemp -d)"
  log "Finding the latest Node.js LTS release"
  curl -fsSL "$NODE_DIST_BASE/index.json" -o "$NODE_TMPDIR/index.json"
  node_version="$(jq -r '[.[] | select(.lts != false)][0].version // empty' "$NODE_TMPDIR/index.json")"

  if [[ ! "$node_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    die "Could not determine the latest Node.js LTS version"
  fi

  archive="node-${node_version}-linux-${node_arch}.tar.xz"
  download_base="$NODE_DIST_BASE/$node_version"

  log "Downloading Node.js $node_version for $node_arch"
  curl -fsSL "$download_base/$archive" -o "$NODE_TMPDIR/$archive"
  curl -fsSL "$download_base/SHASUMS256.txt" -o "$NODE_TMPDIR/SHASUMS256.txt"

  (
    cd "$NODE_TMPDIR"
    grep -F "  $archive" SHASUMS256.txt | sha256sum -c -
  )

  install_root="/usr/local/lib/nodejs"
  install_dir="$install_root/node-${node_version}-linux-${node_arch}"
  mkdir -p "$install_root" /usr/local/bin
  rm -rf -- "$install_dir"
  tar -xJf "$NODE_TMPDIR/$archive" -C "$install_root"

  for binary in node npm npx corepack; do
    if [[ -e "$install_dir/bin/$binary" ]]; then
      ln -sfn "$install_dir/bin/$binary" "/usr/local/bin/$binary"
    fi
  done

  hash -r
  log "Installed Node.js $(node --version) and npm $(npm --version)"
}

if ! have_cmd apt-get; then
  die "This installer currently supports Ubuntu/Debian systems with apt-get"
fi

log "Installing Codex CLI prerequisites"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates curl git jq nodejs npm ripgrep tmux xz-utils

current_node_major="$(node_major || true)"
if [[ ! "$current_node_major" =~ ^[0-9]+$ ]] || ((current_node_major < MIN_NODE_MAJOR)); then
  warn "Node.js ${current_node_major:-unknown} is older than the recommended major version $MIN_NODE_MAJOR"
  install_latest_node_lts
fi

current_node_major="$(node_major || true)"
if [[ ! "$current_node_major" =~ ^[0-9]+$ ]]; then
  die "Node.js installation completed but node --version is unavailable"
fi

engine_requirement="$(npm view "$CODEX_PACKAGE_SPEC" engines.node 2>/dev/null || true)"
if [[ -n "$engine_requirement" ]]; then
  log "$CODEX_PACKAGE_SPEC requires Node.js $engine_requirement"
fi

required_node_major="$(printf '%s\n' "$engine_requirement" | sed -nE 's/^[[:space:]]*>=([0-9]+).*$/\1/p')"
current_node_major="$(node_major || true)"
if [[ "$required_node_major" =~ ^[0-9]+$ ]] && ((current_node_major < required_node_major)); then
  warn "Installed Node.js does not satisfy the Codex package requirement"
  install_latest_node_lts
fi

log "Installing or updating $CODEX_PACKAGE_SPEC"
npm_config_engine_strict=true npm install \
  --global --prefix /usr/local --no-audit --no-fund "$CODEX_PACKAGE_SPEC"
hash -r

if ! have_cmd codex; then
  die "npm completed but the codex command is not available in PATH"
fi

log "Codex CLI installed: $(codex --version)"
log "Executable: $(command -v codex)"

if [[ -n "$CODEX_RUN_USER" && "$CODEX_RUN_USER" != root ]]; then
  echo
  log "Run Codex as the normal user, not root:"
  printf '  sudo -iu %q\n' "$CODEX_RUN_USER"
  printf '  codex login --device-auth\n'
  printf '  codex login status\n'
else
  echo
  warn "Do not run interactive Codex sessions as root"
  warn "Switch to or create a normal user, then run: codex login --device-auth"
fi
