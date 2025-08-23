#!/usr/bin/env bash
set -euo pipefail

# helper for defaults; env vars can override anything
def() { eval ": \${$1:=$2}"; export "$1"; }

# ---- Build target (ARM64) ---------------------------------------------------
def KS_ARCH        "arm64"
def KS_SUITE       "bookworm"
def KS_VARIANT     "apt"
def KS_COMPONENTS  "main"
def KS_MIRROR      "http://deb.debian.org/debian"

# ---- Packages (Raspberry Pi defaults) ---------------------------------------
# Minimal but bootable on Pi: kernel + firmware; Wi-Fi firmware optional.
# Comma-separated, no spaces.
def KS_PACKAGES "linux-image-rpi-v8,raspi-firmware,firmware-brcm80211,ca-certificates,locales,tzdata,sudo"

# ---- Identity / preseeding --------------------------------------------------
def KS_HOSTNAME        "raspi"

# Timezone (tzdata expects Area and City with underscore)
def KS_TZ_AREA         "America"
def KS_TZ_CITY         "New_York"
def KS_TIMEZONE        "${KS_TZ_AREA}/${KS_TZ_CITY}"

def KS_LOCALE_DEFAULT  "en_US.UTF-8"
def KS_LOCALE_GEN      "en_US.UTF-8 UTF-8"
def KS_LOCALE          "${KS_LOCALE_DEFAULT}"
def KS_KB_KEYMAP       "us"

# ---- Default user (plaintext; hashed via chpasswd in-chroot) ----------------
def KS_CREATE_USER           "1"            # 1=create; 0=skip
def KS_DEVICE_USER           "pi"
def KS_USER_SHELL            "/bin/bash"
def KS_USER_GROUPS           "sudo"
def KS_USER_PASSWORD_PLAIN   "raspberry"    # plaintext default
def KS_PASSWORD_CRYPT_METHOD ""             # e.g., SHA512 or YESCRYPT (optional)

# ---- Output -----------------------------------------------------------------
def KS_OUT_DIR          "out"

# ---- Disk image (Raspberry Pi layout) ---------------------------------------
# MBR with 2 partitions:
#  - p1: FAT32 boot (/boot/firmware) label FIRMWARE
#  - p2: ext4 root (/)             label rootfs
def KS_PART_TABLE       "mbr"        # mbr|gpt
def KS_IMG_NAME         "raspi.img"
def KS_IMG_SIZE_MIB     "4096"       # total image size
def KS_BOOT_SIZE_MIB    "512"        # FAT32 boot size
def KS_BOOT_LABEL       "FIRMWARE"
def KS_ROOTFS_LABEL     "rootfs"
