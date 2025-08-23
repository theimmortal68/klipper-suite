#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

sudo apt-get update
sudo apt-get install -y \
  bdebstrap \
  mmdebstrap \
  genimage \
  dosfstools \
  e2fsprogs \
  binfmt-support \
  qemu-user-static \
  rsync \
  zstd \
  tar \
  util-linux

# Enable qemu-aarch64 binfmt if available (for cross-building arm64 on x86_64)
sudo update-binfmts --enable qemu-aarch64 || true

# Quick sanity print
echo "Installed tools:"
command -v bdebstrap       && bdebstrap --version || true
command -v mmdebstrap      && mmdebstrap --version
command -v genimage        && genimage --version
command -v mkfs.vfat       && echo "mkfs.vfat: $(mkfs.vfat -V 2>&1 | head -n1 || true)"
command -v mke2fs          && echo "mke2fs: $(mke2fs -V 2>&1 | head -n1 || true)"
command -v qemu-aarch64-static >/dev/null 2>&1 || echo "Note: qemu-aarch64-static not found in PATH"
