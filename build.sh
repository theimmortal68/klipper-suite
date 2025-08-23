#!/bin/bash

set -uo pipefail

IGTOP=$(readlink -f $(dirname "$0"))

. "$IGTOP/scripts/dependencies_check" depends
. "$IGTOP/scripts/common"
. "$IGTOP/scripts/core"
. "$IGTOP/bin/igconf"

EXTERNAL_DIR=""
EXTERNAL_NSDIR=""
INCONFIG="generic64-apt-simple"
OVERRIDES=""
ROOTFS_ONLY=""
IMAGE_ONLY=""

usage() {
    echo "Usage: $0 [-c <config>] [-D <dir>] [-N <nsdir>] [-o <file>] [-r] [-i]" >&2
    exit 1
}

while getopts "c:D:N:o:ri" opt; do
    case "$opt" in
        c) INCONFIG="$OPTARG";;
        D) EXTERNAL_DIR="$OPTARG";;
        N) EXTERNAL_NSDIR="$OPTARG";;
        o) OVERRIDES="$OPTARG";;
        r) ROOTFS_ONLY=1;;
        i) IMAGE_ONLY=1;;
        *) usage;;
    esac
done

# core directories
IGCONFIG="$IGTOP/config"
IGDEVICE="$IGTOP/device"
IGIMAGE="$IGTOP/image"
IGPROFILE="$IGTOP/profile"
IGMETA="$IGTOP/meta"
IGMETA_HOOKS="$IGTOP/meta-hooks"
RPI_TEMPLATES="$IGTOP/templates"

# normalize INCONFIG
if [[ ! "$INCONFIG" =~ ".cfg$" ]]; then
    INCONFIG="$INCONFIG.cfg"
fi

# external dir handling
if [ -n "$EXTERNAL_DIR" ]; then
    [ -d "$EXTERNAL_DIR/config" ] || die "External dir missing config/"
    if [ -f "$EXTERNAL_DIR/config/$INCONFIG" ]; then
        INCONFIG="$EXTERNAL_DIR/config/$INCONFIG"
    else
        INCONFIG="$IGCONFIG/$INCONFIG"
    fi
else
    INCONFIG="$IGCONFIG/$INCONFIG"
fi

# NOTE: scripts/core provides merge_config (not aggregate_config)
merge_config "$INCONFIG"

[ -n "${IGconf_image_layout:-}" ] || die "IGconf_image_layout not set"
[ -n "${IGconf_device_class:-}" ] || die "IGconf_device_class not set"
[ -n "${IGconf_device_profile:-}" ] || die "IGconf_device_profile not set"

# resolve directories for the selected device/image/profile
IGDEVICE="$IGTOP/device/$IGconf_device_class"
IGIMAGE="$IGTOP/image/$IGconf_image_layout"
IGPROFILE="$IGTOP/profile/$IGconf_device_profile"

# merge defaults/options (SBOM references removed)
aggregate_options "$IGDEVICE/config.options"
aggregate_options "$IGDEVICE/build.defaults"
aggregate_options "$IGDEVICE/provision.defaults"
aggregate_options "$IGIMAGE/config.options"
aggregate_options "$IGIMAGE/build.defaults"
aggregate_options "$IGIMAGE/provision.defaults"
aggregate_options "$IGTOP/device/build.defaults"
aggregate_options "$IGTOP/image/build.defaults"
aggregate_options "$IGTOP/image/provision.defaults"
aggregate_options "$IGTOP/sys-build.defaults"
aggregate_options "$IGTOP/meta/defaults"
[ -n "$OVERRIDES" ] && aggregate_options "$OVERRIDES"

# assemble meta layers from profiles
ARGS_LAYERS=()
load_profile main "$IGPROFILE"
if [ -n "${IGconf_image_profile:-}" ] && [ -f "$IGIMAGE/profile/$IGconf_image_profile" ]; then
    load_profile image "$IGIMAGE/profile/$IGconf_image_profile"
fi
# convenience: auto-add ssh server if requested
if [ "${IGconf_device_ssh_user1:-false}" = "true" ]; then
    layer_push auto "net-misc/openssh-server"
fi

# apt keydir
if [ -z "${IGconf_sys_apt_keydir:-}" ]; then
    IGconf_sys_apt_keydir="$IGconf_sys_workdir/keys"
    mkdir -p "$IGconf_sys_apt_keydir"
    cp -r /usr/share/keyrings/* "$IGconf_sys_apt_keydir" 2>/dev/null || true
    cp -r "$HOME/.local/share/keyrings"/* "$IGconf_sys_apt_keydir" 2>/dev/null || true
    cp -r "$IGTOP/keydir"/* "$IGconf_sys_apt_keydir" 2>/dev/null || true
fi
[ -d "$IGconf_sys_apt_keydir" ] || die "keydir $IGconf_sys_apt_keydir missing"

# prepare envs
ENV_ROOTFS=()
ENV_POST_BUILD=()

for var in $(set | grep '^IGconf' | cut -d= -f1); do
    val="${!var}"
    case "$var" in
        IGconf_device_timezone)
            ENV_ROOTFS+=("IGconf_device_timezone=$val")
            ENV_POST_BUILD+=("IGconf_device_timezone=$val")
            ENV_ROOTFS+=("IGconf_device_timezone_area=${val%%/*}")
            ENV_ROOTFS+=("IGconf_device_timezone_city=${val##*/}")
            ;;
        IGconf_sys_apt_proxy_http)
            if curl -x "$val" --head http://deb.debian.org >/dev/null 2>&1; then
                ENV_ROOTFS+=("APT_OPTION=Acquire::http::Proxy \"$val\"")
            fi
            ;;
        IGconf_sys_apt_keydir)
            ENV_ROOTFS+=("APT_OPTION=Dir::Etc::TrustedParts \"$val\"")
            ;;
        IGconf_sys_apt_get_purge)
            [ "$val" = "true" ] && ENV_ROOTFS+=("APT_OPTION=APT::Get::Purge true")
            ;;
        IGconf_ext_dir|IGconf_ext_nsdir)
            ENV_ROOTFS+=("$var=$val")
            ENV_POST_BUILD+=("$var=$val")
            ;;
        *)
            ENV_ROOTFS+=("$var=$val")
            ENV_POST_BUILD+=("$var=$val")
            ;;
    esac
done

ENV_ROOTFS+=("IGTOP=$IGTOP" "META_HOOKS=$IGMETA_HOOKS" "RPI_TEMPLATES=$RPI_TEMPLATES" "IGDEVICE=$IGDEVICE" "IGIMAGE=$IGIMAGE" "IGPROFILE=$IGPROFILE")
ENV_POST_BUILD+=("IGTOP=$IGTOP" "META_HOOKS=$IGMETA_HOOKS" "RPI_TEMPLATES=$RPI_TEMPLATES" "IGDEVICE=$IGDEVICE" "IGIMAGE=$IGIMAGE" "IGPROFILE=$IGPROFILE")

# PATH adjustments
PATH_ROOTFS="$IGTOP/bin"
PATH_POST_BUILD="$IGTOP/bin"
[ -n "${IGconf_ext_dir:-}" ] && PATH_ROOTFS="$IGconf_ext_dir/bin:$PATH_ROOTFS" && PATH_POST_BUILD="$IGconf_ext_dir/bin:$PATH_POST_BUILD"
[ -n "${IGconf_ext_nsdir:-}" ] && PATH_ROOTFS="$IGconf_ext_nsdir/bin:$PATH_ROOTFS" && PATH_POST_BUILD="$IGconf_ext_nsdir/bin:$PATH_POST_BUILD"
PATH_POST_BUILD="$IGconf_sys_workdir/host/bin:$PATH_POST_BUILD"

# meta layer helpers (unchanged)
layer_push() {
    scope="$1"; shift; name="$1"
    case "$scope" in
        image)
            if [ -f "$IGIMAGE/meta/$name.yaml" ]; then
                ARGS_LAYERS+=("--config" "$IGIMAGE/meta/$name.yaml")
                [ -f "$IGIMAGE/meta/$name.defaults" ] && aggregate_options "$IGIMAGE/meta/$name.defaults"
            fi
            ;;&
        main|auto)
            if [ -n "$EXTERNAL_NSDIR" ] && [ -f "$EXTERNAL_DIR/meta-$EXTERNAL_NSDIR/$name.yaml" ]; then
                ARGS_LAYERS+=("--config" "$EXTERNAL_DIR/meta-$EXTERNAL_NSDIR/$name.yaml")
                [ -f "$EXTERNAL_DIR/meta-$EXTERNAL_NSDIR/$name.defaults" ] && aggregate_options "$EXTERNAL_DIR/meta-$EXTERNAL_NSDIR/$name.defaults"
            elif [ -n "$EXTERNAL_DIR" ] && [ -f "$EXTERNAL_DIR/meta/$name.yaml" ]; then
                ARGS_LAYERS+=("--config" "$EXTERNAL_DIR/meta/$name.yaml")
                [ -f "$EXTERNAL_DIR/meta/$name.defaults" ] && aggregate_options "$EXTERNAL_DIR/meta/$name.defaults"
            elif [ -f "$IGMETA/$name.yaml" ]; then
                ARGS_LAYERS+=("--config" "$IGMETA/$name.yaml")
                [ -f "$IGMETA/$name.defaults" ] && aggregate_options "$IGMETA/$name.defaults"
            fi
            ;;
    esac
}

load_profile() {
    scope="$1"; file="$2"
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        [[ "$line" =~ ^# ]] && continue
        layer_push "$scope" "$line"
    done < "$file"
}

# pre-build hooks (fix undefined IGTOP_* vars)
[ -x "$IGTOP/device/pre-build.sh" ] && runh "$IGTOP/device/pre-build.sh"
[ -x "$IGTOP/image/pre-build.sh" ] && runh "$IGTOP/image/pre-build.sh"
[ -x "$IGIMAGE/pre-build.sh" ] && runh "$IGIMAGE/pre-build.sh"
[ -x "$IGDEVICE/pre-build.sh" ] && runh "$IGDEVICE/pre-build.sh"

# rootfs build
if [ -z "$IMAGE_ONLY" ]; then
    run bdebstrap "${ARGS_LAYERS[@]}" \
        "${ENV_ROOTFS[@]}" \
        --name "$IGconf_sys_name" \
        --hostname "$IGconf_sys_hostname" \
        --output "$IGconf_sys_staging" \
        --target "$IGconf_sys_target" \
        --setup-hook 'bin/runner setup "$@"' \
        --essential-hook 'bin/runner essential "$@"' \
        --customize-hook 'bin/runner customize "$@"' \
        --cleanup-hook 'bin/runner cleanup "$@"'

    if [ -f "$IGconf_sys_target" ]; then
        exit 0
    fi
fi

# overlays & post-build
[ -d "$IGIMAGE/device/rootfs-overlay" ] && rsync -a "$IGIMAGE/device/rootfs-overlay/" "$IGconf_sys_target/"
[ -d "$IGDEVICE/device/rootfs-overlay" ] && rsync -a "$IGDEVICE/device/rootfs-overlay/" "$IGconf_sys_target/"
[ -x "$IGIMAGE/post-build.sh" ] && runh "$IGIMAGE/post-build.sh" "$IGconf_sys_target"
[ -x "$IGDEVICE/post-build.sh" ] && runh "$IGDEVICE/post-build.sh" "$IGconf_sys_target"

[ -n "$ROOTFS_ONLY" ] && exit 0

# pre-image
if [ -x "$IGDEVICE/pre-image.sh" ]; then
    runh "$IGDEVICE/pre-image.sh" "$IGconf_sys_target" "$IGconf_sys_output"
elif [ -x "$IGIMAGE/pre-image.sh" ]; then
    runh "$IGIMAGE/pre-image.sh" "$IGconf_sys_target" "$IGconf_sys_output"
else
    die "No pre-image hook"
fi

# image build
mkdir -p "$IGconf_sys_output"
rm -rf "$IGconf_sys_tmp"
mkdir -p "$IGconf_sys_tmp"

for cfg in "$IGconf_sys_output"/genimage*.cfg; do
    run genimage --rootpath "$IGconf_sys_target" --tmppath "$IGconf_sys_tmp" --inputpath "$IGconf_sys_output" --outputpath "$IGconf_sys_output" --config "$cfg"
done

# post-image
if [ -x "$IGDEVICE/post-image.sh" ]; then
    runh "$IGDEVICE/post-image.sh" "$IGconf_sys_output"
elif [ -x "$IGIMAGE/post-image.sh" ]; then
    runh "$IGIMAGE/post-image.sh" "$IGconf_sys_output"
elif [ -x "$IGTOP_IMAGE/post-image.sh" ]; then
    runh "$IGTOP_IMAGE/post-image.sh" "$IGconf_sys_output"
fi
