#!/usr/bin/env bash
# Build a Bookworm ARM64 Raspberry Pi–style image using bdebstrap + genimage,
# with selectable DEVICE and PROFILE, colorized output, and preseeded RPi repo key.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "${ROOT}/options.sh"

# ------------------------- arg parsing ----------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--device)   KS_DEVICE="${2:?}"; shift 2 ;;
    -p|--profile)  KS_PROFILE="${2:?}"; shift 2 ;;
    -h|--help)     echo "Usage: $0 [--device <name>] [--profile base|klipper|mainsailos|ratos]"; exit 0 ;;
    --)            shift; break ;;
    *)             if [[ -z "${KS_DEVICE_SET:-}" ]]; then
                     KS_DEVICE="$1"; KS_DEVICE_SET=1; shift
                   elif [[ -z "${KS_PROFILE_SET:-}" ]]; then
                     KS_PROFILE="$1"; KS_PROFILE_SET=1; shift
                   else
                     echo "Unexpected arg: $1" >&2; exit 1
                   fi ;;
  esac
done

# ------------------------- color helpers --------------------------------------
: "${KS_COLOR:=auto}"
_color_on=false
if [[ "${KS_COLOR}" == "always" ]] || { [[ "${KS_COLOR}" == "auto" ]] && { [[ -t 1 ]] || [[ -n "${GITHUB_ACTIONS:-}" ]]; }; }; then
  _color_on=true
fi
if $_color_on; then
  RED=$'\e[31m'; GRN=$'\e[32m'; YEL=$'\e[33m'; BLU=$'\e[34m'; CYN=$'\e[36m'; BLD=$'\e[1m'; RST=$'\e[0m'
  export PS4=$'\e[36m+ \e[0m'
else
  RED=""; GRN=""; YEL=""; BLU=""; CYN=""; BLD=""; RST=""
  export PS4='+ '
fi
info()    { printf '%s[INFO]%s %s\n'  "$GRN" "$RST" "$*"; }
warn()    { printf '%s[WARN]%s %s\n'  "$YEL" "$RST" "$*"; }
error()   { printf '%s[ERR ]%s %s\n'  "$RED" "$RST" "$*"; }
section() { printf '\n%s==> %s%s\n'    "$BLU" "$1" "$RST"; }

# ------------------------- tool checks ----------------------------------------
need() { command -v "$1" >/dev/null 2>&1 || { error "Missing: $1"; exit 1; }; }
need bdebstrap
need genimage
need rsync
need zstd
need mkfs.vfat         # dosfstools
need mke2fs            # e2fsprogs
# yq only needed if you actually use devices/<dev>/layers.yaml
if [[ -f "${ROOT}/devices/${KS_DEVICE}/layers.yaml" ]]; then
  need yq
fi
command -v qemu-aarch64-static >/dev/null 2>&1 || warn "qemu-aarch64-static not found; required to cross-build arm64 on x86_64."

# ------------------------- defaults for RPi repo knobs ------------------------
: "${KS_ENABLE_RPI_REPO:=1}"
: "${KS_RPI_REPO_URL:=http://archive.raspberrypi.org/debian}"
: "${KS_RPI_REPO_COMPONENTS:=main}"
: "${KS_RPI_REPO_ARCH:=arm64}"
: "${KS_RPI_KEY_FILE:=keys/raspberrypi-archive-stable.gpg}"
: "${KS_RPI_KEY_DST:=/usr/share/keyrings/raspberrypi-archive-stable.gpg}"
: "${KS_RPI_APT_FILE:=/etc/apt/sources.list.d/raspi.list}"

# ------------------------- paths & logging ------------------------------------
OUT_DIR="${ROOT}/${KS_OUT_DIR}"
ROOTFS="${OUT_DIR}/rootfs"
LOGFILE="${OUT_DIR}/BUILD_LOG.txt"
IMG_DIR="${OUT_DIR}/images"
TMP_DIR="${OUT_DIR}/genimage-tmp"
CFG_AUTO="${OUT_DIR}/genimage.auto.cfg"
BOOT_IMG="${OUT_DIR}/boot.vfat"
BDEB_CFG_BASE="${OUT_DIR}/bdebstrap.base.yaml"
DEV_DIR="${ROOT}/devices/${KS_DEVICE}"
DEV_LAYERS="${DEV_DIR}/layers.yaml"

sudo rm -rf "${ROOTFS}" "${IMG_DIR}" "${TMP_DIR}" "${BOOT_IMG}" "${BDEB_CFG_BASE}" "${CFG_AUTO}"
mkdir -p "${OUT_DIR}" "${IMG_DIR}" "${TMP_DIR}"

# mirror console to file; strip ANSI for the saved log if colors are on
if $_color_on; then
  exec > >(tee >(sed -E 's/\x1b\[[0-9;]*m//g' > "${LOGFILE}")) 2>&1
else
  exec > >(tee "${LOGFILE}") 2>&1
fi

section "Build start"
info "Device : ${KS_DEVICE}"
info "Profile: ${KS_PROFILE}"
info "Color  : ${KS_COLOR}"

# ------------------------- verify repo key if enabled -------------------------
if [[ "${KS_ENABLE_RPI_REPO}" == "1" ]]; then
  if [[ ! -f "${ROOT}/${KS_RPI_KEY_FILE}" ]]; then
    error "Missing repo key file: ${KS_RPI_KEY_FILE} (expected in repo)"
    exit 1
  fi
  info "RPi APT repo enabled; key: ${KS_RPI_KEY_FILE}"
fi

# ------------------------- collect device/profile layers ----------------------
LAYER_CFGS=()
if [[ -f "${DEV_LAYERS}" ]]; then
  if ! yq -e '.profiles' "${DEV_LAYERS}" >/dev/null; then
    error "layers.yaml missing 'profiles' key: ${DEV_LAYERS}"; exit 1
  fi
  if ! yq -e ".profiles.${KS_PROFILE}" "${DEV_LAYERS}" >/dev/null; then
    error "Profile '${KS_PROFILE}' not defined for device '${KS_DEVICE}'."
    echo "Available: $(yq -r '.profiles | keys | join(", ")' "${DEV_LAYERS}")"
    exit 1
  fi
  mapfile -t LAYER_CFGS < <(yq -r ".profiles.${KS_PROFILE}[]?" "${DEV_LAYERS}")
  section "Layers"
  for f in "${LAYER_CFGS[@]}"; do info "$f"; done
else
  warn "No device layer file at ${DEV_LAYERS}; continuing with base config only."
fi

# ------------------------- in-chroot apply script -----------------------------
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

# Minimal RPi boot configs if none provided by packages/layers
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

# ------------------------- base bdebstrap YAML (robust list printing) ---------
BDEB_CFG_BASE="${OUT_DIR}/bdebstrap.base.yaml"
cat > "${BDEB_CFG_BASE}" <<EOF
---
name: ${KS_DEVICE}-${KS_PROFILE}-${KS_SUITE}-${KS_ARCH}
env:
  KS_TZ_AREA: "${KS_TZ_AREA}"
  KS_TZ_CITY: "${KS_TZ_CITY}"
  KS_LOCALE_DEFAULT: "${KS_LOCALE_DEFAULT}"
  KS_LOCALE_GEN: "${KS_LOCALE_GEN}"
  KS_KB_KEYMAP: "${KS_KB_KEYMAP}"

mmdebstrap:
  suite: ${KS_SUITE}
  architectures:
    - ${KS_ARCH}
  components:
$(printf '    - %s\n' ${KS_COMPONENTS//,/ })
  mirrors:
    - ${KS_MIRROR}
  variant: ${KS_VARIANT}
  format: directory
  target: rootfs
  packages:
$(printf '    - %s\n' ${KS_PACKAGES//,/ })
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

section "Generated bdebstrap.base.yaml (head)"
sed -n '1,120p' "${BDEB_CFG_BASE}" || true

# ------------------------- run bdebstrap (merge layers) ----------------------
section "bdebstrap"
cmd=(bdebstrap
  --config "${BDEB_CFG_BASE}"
  --name   "${KS_DEVICE}-${KS_PROFILE}-${KS_SUITE}-${KS_ARCH}"
  --output "${OUT_DIR}"
  --force --verbose)

# Preseed Raspberry Pi repo key & source before apt runs (setup-hooks)
if [[ "${KS_ENABLE_RPI_REPO}" == "1" ]]; then
  cmd+=(--setup-hook="copy-in ${ROOT}/${KS_RPI_KEY_FILE} ${KS_RPI_KEY_DST}")
  cmd+=(--setup-hook="sh -c 'mkdir -p \"\$1/etc/apt/sources.list.d\" && printf \"%s\n\" \"deb [arch=${KS_RPI_REPO_ARCH} signed-by=${KS_RPI_KEY_DST}] ${KS_RPI_REPO_URL} ${KS_SUITE} ${KS_RPI_REPO_COMPONENTS}\" > \"\$1${KS_RPI_APT_FILE}\"'")
fi

# Add any device/profile layer configs (-c merges in order)
for f in "${LAYER_CFGS[@]}"; do
  [[ -f "${ROOT}/${f}" ]] || { error "Missing layer config: ${f}"; exit 1; }
  cmd+=(-c "${ROOT}/${f}")
done

set -x
"${cmd[@]}"
set +x

# ------------------------- assemble boot (FAT32) -----------------------------
section "Assemble boot (FAT32)"
dd if=/dev/zero of="${BOOT_IMG}" bs=1M count="${KS_BOOT_SIZE_MIB}" status=none
mkfs.vfat -n "${KS_BOOT_LABEL}" "${BOOT_IMG}"
TMP_BOOT="$(mktemp -d)"
sudo mount -o loop "${BOOT_IMG}" "${TMP_BOOT}"
sudo rsync -aH --delete "${ROOTFS}/boot/firmware/" "${TMP_BOOT}/"
sync; sudo umount "${TMP_BOOT}"; rmdir "${TMP_BOOT}"

# ------------------------- compute rootfs size --------------------------------
ROOT_SIZE_MIB=$(( KS_IMG_SIZE_MIB - KS_BOOT_SIZE_MIB - 8 ))
(( ROOT_SIZE_MIB > 0 )) || { error "Increase KS_IMG_SIZE_MIB"; exit 1; }

# ------------------------- genimage config (auto) -----------------------------
section "genimage"
cat > "${CFG_AUTO}" <<CFGEOF
image "${KS_IMG_NAME}" {
  hdimage { partition-table-type = "${KS_PART_TABLE}" }
  partition boot   { partition-type = 0x0C; image = "boot.vfat"; offset = 1M }
  partition rootfs { partition-type = 0x83; image = "rootfs.ext4" }
}
image "rootfs.ext4" {
  ext4 { label = "${KS_ROOTFS_LABEL}" }
  size = ${ROOT_SIZE_MIB}M
}
CFGEOF

cp -f "${BOOT_IMG}" "${IMG_DIR}/boot.vfat"
genimage --rootpath "${ROOTFS}" --tmppath "${TMP_DIR}" --outputpath "${IMG_DIR}" --config "${CFG_AUTO}"

section "Done"
info "Device : ${KS_DEVICE}"
info "Profile: ${KS_PROFILE}"
info "Image  : ${IMG_DIR}/${KS_IMG_NAME}"
info "Log    : ${LOGFILE}"
```0
