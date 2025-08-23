#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "${ROOT}/options.sh"

OUT_DIR="${ROOT}/${KS_OUT_DIR}"
sudo rm -rf "${OUT_DIR}"
echo "Removed ${OUT_DIR}"
