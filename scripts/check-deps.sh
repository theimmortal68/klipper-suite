#!/usr/bin/env bash
set -euo pipefail

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1" >&2; exit 1; }; }

need bdebstrap
need mmdebstrap
need rsync
need tar
need zstd

# Helpful (for cross-building on non-arm64 hosts)
if ! command -v qemu-aarch64-static >/dev/null 2>&1; then
  echo "Note: qemu-aarch64-static not found; required to cross-build arm64 on x86_64." >&2
fi

echo "All required tools present."
