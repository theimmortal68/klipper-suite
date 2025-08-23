# Base knobs used by build.sh
export KS_DEVICE="${KS_DEVICE:-rpi5}"
export KS_PROFILE="${KS_PROFILE:-base}"

export KS_SUITE="${KS_SUITE:-bookworm}"
export KS_ARCH="${KS_ARCH:-arm64}"
export KS_COMPONENTS="${KS_COMPONENTS:-main}"
export KS_MIRROR="${KS_MIRROR:-http://deb.debian.org/debian}"
export KS_VARIANT="${KS_VARIANT:-apt}"

# Leave empty if you don’t want to force extra packages from base layer
# (layers can add their own packages cleanly)
# Minimal base packages (comma-separated). Leave empty to omit the block.
: "${KS_PACKAGES:=apt,ca-certificates,gnupg,locales,tzdata,netbase}"
export KS_PACKAGES

export KS_IMG_NAME="${KS_IMG_NAME:-ks-${KS_DEVICE}-${KS_PROFILE}-${KS_SUITE}-${KS_ARCH}.img}"
export KS_PART_TABLE="${KS_PART_TABLE:-dos}"
export KS_IMG_SIZE_MIB="${KS_IMG_SIZE_MIB:-4096}"
export KS_BOOT_SIZE_MIB="${KS_BOOT_SIZE_MIB:-256}"
export KS_BOOT_LABEL="${KS_BOOT_LABEL:-BOOT}"
export KS_ROOTFS_LABEL="${KS_ROOTFS_LABEL:-rootfs}"

export KS_HOSTNAME="${KS_HOSTNAME:-raspi}"
export KS_TIMEZONE="${KS_TIMEZONE:-America/New_York}"
export KS_LOCALE="${KS_LOCALE:-en_US.UTF-8}"
export KS_LOCALE_GEN="${KS_LOCALE_GEN:-en_US.UTF-8 UTF-8}"
export KS_LOCALE_DEFAULT="${KS_LOCALE_DEFAULT:-en_US.UTF-8}"
export KS_TZ_AREA="${KS_TZ_AREA:-America}"
export KS_TZ_CITY="${KS_TZ_CITY:-New_York}"
export KS_KB_KEYMAP="${KS_KB_KEYMAP:-us}"

export KS_CREATE_USER="${KS_CREATE_USER:-1}"
export KS_DEVICE_USER="${KS_DEVICE_USER:-pi}"
export KS_USER_SHELL="${KS_USER_SHELL:-/bin/bash}"
export KS_USER_GROUPS="${KS_USER_GROUPS:-sudo,adm,video,plugdev,audio,netdev}"
export KS_USER_PASSWORD_PLAIN="${KS_USER_PASSWORD_PLAIN:-raspberry}"
export KS_PASSWORD_CRYPT_METHOD="${KS_PASSWORD_CRYPT_METHOD:-}"

export KS_OUT_DIR="${KS_OUT_DIR:-out}"
