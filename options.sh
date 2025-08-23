#!/usr/bin/env bash
# Default, user-friendly options for local builds and CI.
# All variables can be overridden via environment or CLI flags (device/profile).

# Suite/arch
export KS_SUITE="${KS_SUITE:-bookworm}"
export KS_ARCH="${KS_ARCH:-arm64}"
export KS_VARIANT="${KS_VARIANT:-apt}"
export KS_COMPONENTS="${KS_COMPONENTS:-main}"
export KS_MIRROR="${KS_MIRROR:-http://deb.debian.org/debian}"

# Output/layout
export KS_OUT_DIR="${KS_OUT_DIR:-out}"
export KS_IMG_NAME="${KS_IMG_NAME:-debian.img}"
export KS_IMG_SIZE_MIB="${KS_IMG_SIZE_MIB:-4096}"
export KS_BOOT_SIZE_MIB="${KS_BOOT_SIZE_MIB:-256}"
export KS_PART_TABLE="${KS_PART_TABLE:-gpt}"
export KS_BOOT_LABEL="${KS_BOOT_LABEL:-BOOT}"
export KS_ROOTFS_LABEL="${KS_ROOTFS_LABEL:-rootfs}"

# Device/profile selection (default to a generic rpi-like device layout)
export KS_DEVICE="${KS_DEVICE:-rpi5}"
export KS_PROFILE="${KS_PROFILE:-base}"
export KS_HOSTNAME="${KS_HOSTNAME:-raspi}"

# Locale/timezone/keyboard
export KS_TZ_AREA="${KS_TZ_AREA:-America}"
export KS_TZ_CITY="${KS_TZ_CITY:-New_York}"
export KS_TIMEZONE="${KS_TIMEZONE:-${KS_TZ_AREA}/${KS_TZ_CITY}}"
export KS_LOCALE_DEFAULT="${KS_LOCALE_DEFAULT:-en_US.UTF-8}"
export KS_LOCALE_GEN="${KS_LOCALE_GEN:-en_US.UTF-8 UTF-8}"
export KS_LOCALE="${KS_LOCALE:-en_US.UTF-8}"
export KS_KB_KEYMAP="${KS_KB_KEYMAP:-us}"

# Default user (plaintext; chpasswd will hash inside the chroot)
export KS_CREATE_USER="${KS_CREATE_USER:-1}"
export KS_DEVICE_USER="${KS_DEVICE_USER:-pi}"
export KS_USER_PASSWORD_PLAIN="${KS_USER_PASSWORD_PLAIN:-raspberry}"
export KS_US_
