#!/usr/bin/env bash
# Build a Bookworm ARM64 Raspberry Pi–style image using bdebstrap + genimage.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "${ROOT}/options.sh"

# ---- tool checks -------------------------------------------------------------
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1" >&2; exit 1; }; }
need bdebstrap
need genimage
need rsync
need zstd
need mkfs.vfat         # from dosfstools
need mke2fs            # from e2fsprogs
command -v qemu-aarch64-static >/dev/null 2>&1 || \
  echo "Note: qemu-aarch64-static not found; required to cross-build arm64 on x86_64." >&2

# ---- paths -------------------------------------------------------------------
OUT_DIR="${ROOT}/${KS_OUT_DIR}"      # final output dir for bdebstrap + images
ROOTFS="${OUT_DIR}/rootfs"           # will be created by bdebstrap (target=rootfs)
LOGFILE="${OUT_DIR}/BUILD_LOG.txt"
IMG_DIR="${OUT_DIR}/images"
TMP_DIR="${OUT_DIR}/genimage-tmp"
CFG_AUTO="${OUT_DIR}/genimage.auto.cfg"
BOOT_IMG="${OUT_DIR}/boot.vfat"
BDEB_CFG="${OUT_DIR}/bdebstrap.yaml"

sudo rm -rf "${ROOTFS}" "${IMG_DIR}" "${TMP_DIR}" "${BOOT_IMG}" "${BDEB_CFG}"
mkdir -p "${OUT_DIR}" "${IMG_DIR}" "${TMP_DIR}"
: > "${LOGFILE}"

# ---- create single in-chroot apply script (executed by a customize-hook) ----
APPLY="$(mktemp)"
cat > "${APPLY}" <<'EOSH'
#!/usr/bin/env bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
. /etc/ks/options.sh

# Ensure RPi boot dir exists (Bookworm layout)
mkdir -p /boot/firmware

# Hostname + hosts
echo "${KS_HOSTNAME}" > /etc/hostname
printf "127.0.0.1\tlocalhost\n127.0.1.1\t%s\n" "${KS_HOSTNAME}" > /etc/hosts

# Timezone + locale
ln -sf "/usr/share/zoneinfo/${KS_TIMEZONE}" /etc/localtime
echo "${KS_TIMEZONE}" > /etc/timezone
sed -i "s/^# *${KS_LOCALE}/${KS_LOCALE}/" /etc/locale.gen || true
grep -qE "^${KS_LOCALE}" /etc/locale.gen || echo "${KS_LOCALE} UTF-8" >> /etc/locale.gen
locale-gen
update-locale LANG="${KS_LOCALE}"

# Minimal RPi boot configs if none provided by packages
if [ ! -s /boot/firmware/config.txt ]; then
  cat > /boot/firmware/config.txt <<CONF
[all]
auto_initramfs=1
dtparam=audio=on
CONF
fi
if [ ! -s /boot/firmware/cmdline.txt ]; then
  echo "console=serial0,115200 console=tty1 root=LABEL=${KS_ROOTFS_LABEL} rootfstype=ext4 fsck.repair=yes rootwait quiet" > /boot/firmware/cmdline.txt
fi

# Default user (plaintext -> chpasswd)
if [ "${KS_CREATE_USER}" = "1" ]; then
  if id -u "${KS_DEVICE_USER}" >/dev/null 2>&1; then
    echo "user exists, aborting by design"; exit 1
  fi
  useradd -m -s "${KS_USER_SHELL}" -G "${KS_USER_GROUPS}" "${KS_DEVICE_USER}"
  if [ -n "${KS_USER_PASSWORD_PLAIN}" ]; then
    set +x
    if [ -n "${KS_PASSWORD_CRYPT_METHOD}" ]; then
      printf '%s:%s\n' "${KS_DEVICE_USER}" "${KS_USER_PASSWORD_PLAIN}" | chpasswd --crypt-method "${KS_PASSWORD_CRYPT_METHOD}"
    else
      printf '%s:%s\n' "${KS_DEVICE_USER}" "${KS_USER_PASSWORD_PLAIN}" | chpasswd
    fi
    unset KS_USER_PASSWORD_PLAIN || true
    set -x
  else
    passwd -l "${KS_DEVICE_USER}"
  fi
fi

# Marker
echo "Built by bdebstrap at $(date -u +%FT%TZ)" > /etc/issue.d/ci-build.issue
touch /root/BUILD_OK
EOSH
chmod +x "${APPLY}"

# ---- render bdebstrap YAML config -------------------------------------------
# Convert comma lists to YAML arrays
pkg_yaml_items=""
IFS=',' read -ra _pkgs <<< "${KS_PACKAGES}"
for p in "${_pkgs[@]}"; do pkg_yaml_items+="\n      - ${p}"; done

comp_yaml_items=""
IFS=',' read -ra _comps <<< "${KS_COMPONENTS}"
for c in "${_comps[@]}"; do comp_yaml_items+="\n      - ${c}"; done

cat > "${BDEB_CFG}" <<EOF
---
name: raspi-${KS_SUITE}-${KS_ARCH}
env:
  KS_TZ_AREA: "${KS_TZ_AREA}"
  KS_TZ_CITY: "${KS_TZ_CITY}"
  KS_LOCALE_DEFAULT: "${KS_LOCALE_DEFAULT}"
  KS_LOCALE_GEN: "${KS_LOCALE_GEN}"
  KS_KB_KEYMAP: "${KS_KB_KEYMAP}"

mmdebstrap:
  suite: ${KS_SUITE}
  architectures:${comp_yaml_items/#*/}
  architectures:
    - ${KS_ARCH}
  components:${comp_yaml_items:-"
    - main"}
  mirrors:
    - ${KS_MIRROR}
  variant: ${KS_VARIANT}
  format: directory
  target: rootfs
  packages:${pkg_yaml_items}

  essential-hooks:
    - echo tzdata tzdata/Areas select "\$KS_TZ_AREA" | chroot \$1 debconf-set-selections
    - echo tzdata tzdata/Zones/\$KS_TZ_AREA select "\$KS_TZ_CITY" | chroot \$1 debconf-set-selections
    - echo locales locales/locales_to_be_generated multiselect "\$KS_LOCALE_GEN" | chroot \$1 debconf-set-selections
    - echo locales locales/default_environment_locale select "\$KS_LOCALE_DEFAULT" | chroot \$1 debconf-set-selections
    - echo keyboard-configuration keyboard-configuration/xkb-keymap select "\$KS_KB_KEYMAP" | chroot \$1 debconf-set-selections

  customize-hooks:
    - copy-in ${ROOT}/options.sh /etc/ks/options.sh
    - copy-in ${APPLY} /apply.sh
    - chroot "\$1" bash -eux /apply.sh
EOF

# ---- run bdebstrap (writes rootfs/ into OUT_DIR) ----------------------------
# --output points to OUT_DIR; --force removes any prior build dir.
bdebstrap \
  --config "${BDEB_CFG}" \
  --name "raspi-${KS_SUITE}-${KS_ARCH}" \
  --output "${OUT_DIR}" \
  --force --verbose | tee "${LOGFILE}"

# ---- make FAT boot image from /boot/firmware --------------------------------
dd if=/dev/zero of="${BOOT_IMG}" bs=1M count="${KS_BOOT_SIZE_MIB}" status=none
mkfs.vfat -n "${KS_BOOT_LABEL}" "${BOOT_IMG}"
TMP_BOOT="$(mktemp -d)"
sudo mount -o loop "${BOOT_IMG}" "${TMP_BOOT}"
sudo rsync -aH --delete "${ROOTFS}/boot/firmware/" "${TMP_BOOT}/"
sync
sudo umount "${TMP_BOOT}"
rmdir "${TMP_BOOT}"

# ---- compute rootfs size for genimage ---------------------------------------
ROOT_SIZE_MIB=$(( KS_IMG_SIZE_MIB - KS_BOOT_SIZE_MIB - 8 ))
if (( ROOT_SIZE_MIB <= 0 )); then
  echo "Computed ROOT_SIZE_MIB <= 0; increase KS_IMG_SIZE_MIB" >&2
  exit 1
fi

# ---- auto genimage config (MBR: boot FAT32 + root ext4) ---------------------
cat > "${CFG_AUTO}" <<CFGEOF
image "${KS_IMG_NAME}" {
  hdimage { partition-table-type = "${KS_PART_TABLE}" }

  partition boot {
    partition-type = 0x0C
    image = "boot.vfat"
    offset = 1M
  }

  partition rootfs {
    partition-type = 0x83
    image = "rootfs.ext4"
  }
}

image "rootfs.ext4" {
  ext4 { label = "${KS_ROOTFS_LABEL}" }
  size = ${ROOT_SIZE_MIB}M
}
CFGEOF

# Place the prebuilt boot image where genimage expects it
cp -f "${BOOT_IMG}" "${IMG_DIR}/boot.vfat"

# ---- run genimage ------------------------------------------------------------
genimage \
  --rootpath   "${ROOTFS}" \
  --tmppath    "${TMP_DIR}" \
  --outputpath "${IMG_DIR}" \
  --config     "${CFG_AUTO}"

echo
echo "✅ Image ready: ${IMG_DIR}/${KS_IMG_NAME}"
echo "?? Log: ${LOGFILE}"
