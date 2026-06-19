#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

bash -n lib/common.sh scripts/*.sh

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck lib/common.sh scripts/*.sh
else
  echo "shellcheck not installed; skipped"
fi

echo "check ok"

