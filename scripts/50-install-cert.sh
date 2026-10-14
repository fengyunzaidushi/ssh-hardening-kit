#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_root
umask 077

CERT_DIR="${CERT_DIR:-/root/cert-CF/sub2api.online}"
CERT_BASE_URL="${CERT_BASE_URL:-https://raw.githubusercontent.com/fengyunzaidushi/ssh-hardening-kit/${BRANCH:-main}/cert}"

if ! have_cmd curl; then
  install_packages curl
fi
if ! have_cmd openssl; then
  install_packages openssl
fi

mkdir -p "$CERT_DIR"
chmod 700 "$CERT_DIR"

staging_dir="$(mktemp -d "$CERT_DIR/.download.XXXXXX")"
cleanup() {
  rm -rf "$staging_dir"
}
trap cleanup EXIT

for name in fullchain.pem privkey.pem; do
  log "Downloading $name"
  curl --fail --silent --show-error --location \
    --proto '=https' --proto-redir '=https' \
    --connect-timeout 15 --max-time 120 --retry 2 \
    --output "$staging_dir/$name" "${CERT_BASE_URL%/}/$name"
  [[ -s "$staging_dir/$name" ]] || die "Downloaded $name is empty"
done

openssl x509 -in "$staging_dir/fullchain.pem" -noout >/dev/null
openssl pkey -in "$staging_dir/privkey.pem" -passin pass: -check -noout >/dev/null

cert_public_key="$(openssl x509 -in "$staging_dir/fullchain.pem" -pubkey -noout)"
key_public_key="$(openssl pkey -in "$staging_dir/privkey.pem" -passin pass: -pubout)"
[[ "$cert_public_key" == "$key_public_key" ]] || die "Certificate and private key do not match; existing files were not replaced"

if [[ -e "$CERT_DIR/fullchain.pem" || -e "$CERT_DIR/privkey.pem" ]]; then
  BACKUP_DIR="$(new_backup_dir cert)"
  backup_path "$CERT_DIR/fullchain.pem" "$BACKUP_DIR"
  backup_path "$CERT_DIR/privkey.pem" "$BACKUP_DIR"
  if [[ -f "$BACKUP_DIR$CERT_DIR/privkey.pem" ]]; then
    chmod 600 "$BACKUP_DIR$CERT_DIR/privkey.pem"
  fi
  log "Backup directory: $BACKUP_DIR"
fi

chown root:root "$CERT_DIR" "$staging_dir/fullchain.pem" "$staging_dir/privkey.pem"
chmod 644 "$staging_dir/fullchain.pem"
chmod 600 "$staging_dir/privkey.pem"
mv -f "$staging_dir/fullchain.pem" "$CERT_DIR/fullchain.pem"
mv -f "$staging_dir/privkey.pem" "$CERT_DIR/privkey.pem"

log "Certificate installed: $CERT_DIR/fullchain.pem"
log "Private key installed: $CERT_DIR/privkey.pem (mode 600)"
