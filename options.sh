#!/usr/bin/env bash
set -euo pipefail

# helper for defaults; env vars can override anything
def() { eval ": \${$1:=$2}"; export "$1"; }

# ---- Device + Profile selectors ---------------------------------------------
def KS_DEVICE   "rpi5"      # devices/<device>/layers.yaml (optional)
def KS_PROFILE  "base"       # base | klipper | mainsailos | ratos

# ---- Raspberry Pi repo (key + source) ---------------------------------------
# Enable to add http://archive.raspberrypi.org/debian with signed-by keyring
def KS_ENABLE_RPI_REPO        "1"
def KS_RPI_REPO_URL           "http://archive.raspberrypi.org/debian"
def KS_RPI_REPO_COMPONENTS    "main"
def KS_RPI_REPO_ARCH          "arm64"

# Path to the key file in THIS repo and where to install it inside the target
def KS_RPI_KEY_FILE           "keys/raspberrypi-archive-stable.gpg"
def KS_RPI_KEY_DST            "/usr/share/keyrings/raspberrypi-archive-stable.gpg"

# Where to write the apt source entry inside the target
def KS_RPI_APT_FILE           "/etc/apt/sources.list.d/raspi.list"

# ---- Build target (ARM64) ---------------------------------------------------
def KS_ARCH        "arm64"
def KS_SUITE       "bookworm"
def KS_VARIANT     "apt"
def KS_COMPONENTS  "main"
def KS_MIRROR      "http://deb.debian.org/debian"

# ---- Packages (Raspberry Pi defaults) ---------------------------------------
def KS_PACKAGES "linux-image-rpi-v8,raspi-firmware,firmware-brcm80211,ca-certificates,locales,tzdata,sudo"

# ---- Identity / preseeding --------------------------------------------------
def KS_HOSTNAME        "raspi"
def KS_TZ_AREA         "America"
def KS_TZ_CITY         "New_York"
def KS_TIMEZONE        "${KS_TZ_AREA}/${KS_TZ_CITY}"
def KS_LOCALE_DEFAULT  "en_US.UTF-8"
def KS_LOCALE_GEN      "en_US.UTF-8 UTF-8"
def KS_LOCALE          "${KS_LOCALE_DEFAULT}"
def KS_KB_KEYMAP       "us"

# ---- Default user (plaintext; hashed via chpasswd in-chroot) ----------------
def KS_CREATE_USER           "1"
def KS_DEVICE_USER           "pi"
def KS_USER_SHELL            "/bin/bash"
def KS_USER_GROUPS           "sudo"
def KS_USER_PASSWORD_PLAIN   "raspberry"
def KS_PASSWORD_CRYPT_METHOD ""             # e.g., SHA512 or YESCRYPT (optional)

# ---- Output -----------------------------------------------------------------
def KS_OUT_DIR          "out"

# ---- Disk image (Raspberry Pi layout) ---------------------------------------
def KS_PART_TABLE       "mbr"        # mbr|gpt
def KS_IMG_NAME         "raspi.img"
def KS_IMG_SIZE_MIB     "4096"       # total image size
def KS_BOOT_SIZE_MIB    "512"        # FAT32 boot size
def KS_BOOT_LABEL       "FIRMWARE"
def KS_ROOTFS_LABEL     "rootfs"

# ---- Colors -----------------------------------------------------------------
# auto = color if TTY or GitHub Actions; always = force; never = disable
def KS_COLOR            "auto"
