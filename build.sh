#!/usr/bin/env bash

set -uo pipefail

IGTOP=$(readlink -f "$(dirname "$0")")

source "${IGTOP}/scripts/dependencies_check"
dependencies_check "${IGTOP}/depends" || exit 1
source "${IGTOP}/scripts/common"
source "${IGTOP}/scripts/core"
source "${IGTOP}/bin/igconf"

# Defaults
EXT_DIR=
EXT_META=
EXT_NS=
EXT_NSDIR=
EXT_NSMETA=
INCONFIG=generic64-apt-simple
INOPTIONS=
ONLY_ROOTFS=0
ONLY_IMAGE=0

usage() {
   cat <<EOF

Root filesystem and image generation utility.

Options:
  [-c <config>]    Name of config file, location defaults to config/
                   Default: $INCONFIG
  [-D <directory>] Directory that takes precedence over the default in-tree
                   hierarchy when searching for config files, profiles, meta
                   layers and image layouts.
  [-N <namespace>] Optional namespace to specify an additional sub-directory
                   hierarchy within the directory provided by -D of where to
                   search for meta layers.
  [-o <file>]      Path to shell-style fragment specifying variables as
                   key=value. These variables can override the defaults, those
                   set by the config file, or provide completely new variables
                   available to both rootfs and image generation stages.
  Developer Options
  [-r]             Establish configuration, build rootfs, exit after post-build.
  [-i]             Establish configuration, skip rootfs, run hooks, generate image.
EOF
}

while getopts "c:D:hiN:o:r" flag ; do
   case "$flag" in
      c)
         INCONFIG="$OPTARG"
         ;;
      h)
         usage ; exit 0
         ;;
      i)
         ONLY_IMAGE=1
         ;;
      N)
         EXT_NS="$OPTARG"
         ;;
      D)
         EXT_DIR=$(realpath -e "$OPTARG" 2>/dev/null) || die "Bad directory: $OPTARG"
         ;;
      o)
         INOPTIONS="$OPTARG"
         ;;
      r)
         ONLY_ROOTFS=1
         ;;
      ?|*)
         usage ; exit 1
         ;;
   esac
done

[[ -d $EXT_DIR ]] && EXT_META=$(realpath -e "${EXT_DIR}/meta" 2>/dev/null)

[[ -n $EXT_NS && ! -d $EXT_DIR ]] && die "External namespace supplied without external dir"

if [[ -d $EXT_DIR && -n $EXT_NS ]] ; then
   EXT_NSDIR=$(realpath -e "${EXT_DIR}/${EXT_NS}" 2>/dev/null)
   [[ -d $EXT_NSDIR ]] || die "External namespace dir $EXT_NS does not exist in $EXT_DIR"
   EXT_NSMETA=$(realpath -e "${EXT_DIR}/$EXT_NS/meta" 2>/dev/null)
fi

# Constants
IGTOP_CONFIG="${IGTOP}/config"
IGTOP_DEVICE="${IGTOP}/device"
IGTOP_IMAGE="${IGTOP}/image"
IGTOP_PROFILE="${IGTOP}/profile"
META="${IGTOP}/meta"
META_HOOKS="${IGTOP}/meta-hooks"
RPI_TEMPLATES="${IGTOP}/templates/rpi"

# Establish the top level directory hierarchy by detecting the file and
# switching the base location to the external tree if possible
if [[ -z $INCONFIG ]] ; then
   die "No config file name provided"
fi

# Normalize config name: if no extension was provided, try adding .cfg
__BASENAME="$(basename -- "$INCONFIG")"
case "$__BASENAME" in
  *.cfg) : ;;
  *) __BASENAME="${__BASENAME}.cfg" ;;
esac

# Prefer external overlay (-D) if it contains the config
if [[ -d $EXT_DIR ]]; then
   if [[ -f "${EXT_DIR}/config/${INCONFIG}" ]]; then
      IGTOP_CONFIG="${EXT_DIR}/config"
   elif [[ -f "${EXT_DIR}/config/${__BASENAME}" ]]; then
      IGTOP_CONFIG="${EXT_DIR}/config"
      INCONFIG="${__BASENAME}"
   fi
fi

# Otherwise, fall back to in-repo config/
if [[ "$IGTOP_CONFIG" == "${IGTOP}/config" ]]; then
   if [[ -f "${IGTOP_CONFIG}/${INCONFIG}" ]]; then
      : # use as-is
   elif [[ -f "${IGTOP_CONFIG}/${__BASENAME}" ]]; then
      INCONFIG="${__BASENAME}"
   else
      die "Can't resolve config file path for '${INCONFIG}'. Need -D?"
   fi
fi

CFG=$(realpath -e "${IGTOP_CONFIG}/${INCONFIG}" 2>/dev/null) || \
   die "Bad config spec: $IGTOP_CONFIG : $INCONFIG"

[[ -d $EXT_META ]] && msg "External meta at $EXT_META"
[[ -d $EXT_NSMETA ]] && msg "External [$EXT_NS] meta at $EXT_NSMETA"

# Set via cmdline only
[[ -d $EXT_DIR ]] && IGconf_ext_dir="$EXT_DIR"
[[ -d $EXT_NSDIR ]] && IGconf_ext_nsdir="$EXT_NSDIR"

msg "Reading $CFG with options [$INOPTIONS]"

# Load options(1) to perform explicit set/unset
[[ -s "$INOPTIONS" ]] && apply_options "$INOPTIONS"

# Merge config
aggregate_config "$CFG"

# Mandatory for subsequent parsing
[[ -z ${IGconf_image_layout+x} ]] && die "No image layout provided"
[[ -z ${IGconf_device_class+x} ]] && die "No device class provided"
[[ -z ${IGconf_device_profile+x} ]] && die "No device profile provided"

# Internalise hierarchy paths, prioritising the external sub-directory tree
[[ -d $EXT_DIR ]] && IGDEVICE=$(realpath -e "${EXT_DIR}/device/$IGconf_device_class" 2>/dev/null)
: ${IGDEVICE:=${IGTOP_DEVICE}/$IGconf_device_class}

[[ -d $EXT_DIR ]] && IGIMAGE=$(realpath -e "${EXT_DIR}/image/$IGconf_image_layout" 2>/dev/null)
: ${IGIMAGE:=${IGTOP_IMAGE}/$IGconf_image_layout}

[[ -d $EXT_DIR ]] && IGPROFILE=$(realpath -e "${EXT_DIR}/profile/$IGconf_device_profile" 2>/dev/null)
: ${IGPROFILE:=${IGTOP_PROFILE}/$IGconf_device_profile}

# Final path validation
for i in IGDEVICE IGIMAGE IGPROFILE ; do
   msg "$i ${!i}"
   realpath -e ${!i} > /dev/null 2>&1 || die "$i is invalid"
done

# Merge config options for selected device and image
[[ -s ${IGDEVICE}/config.options ]] && aggregate_options "device" ${IGDEVICE}/config.options
[[ -s ${IGIMAGE}/config.options ]] && aggregate_options "image" ${IGIMAGE}/config.options

# Merge defaults for selected device and image
[[ -s ${IGDEVICE}/build.defaults ]] && aggregate_options "device" ${IGDEVICE}/build.defaults
[[ -s ${IGIMAGE}/build.defaults ]] && aggregate_options "image" ${IGIMAGE}/build.defaults
[[ -s ${IGIMAGE}/provision.defaults ]] && aggregate_options "image" ${IGIMAGE}/provision.defaults

# Merge remaining defaults
aggregate_options "device" ${IGTOP_DEVICE}/build.defaults
aggregate_options "image" ${IGTOP_IMAGE}/build.defaults
aggregate_options "image" ${IGTOP_IMAGE}/provision.defaults
aggregate_options "sys" ${IGTOP}/sys-build.defaults
aggregate_options "meta" ${META}/

# mq: populated derived variables
assignv IGconf_device_timezone UTC
assignv IGconf_device_timezone_area "${IGconf_device_timezone%%/*}"
assignv IGconf_device_timezone_city "${IGconf_device_timezone##*/}"
assignv IGconf_sys_workdir "${IGTOP}/work/${IGconf_sys_name}"
assignv IGconf_sys_target "${IGconf_sys_workdir}/rootfs"
assignv IGconf_sys_outputdir "${IGconf_sys_workdir}/output"
assignv IGconf_sys_deploydir "${IGconf_sys_workdir}/deploy"
assignv IGconf_sys_tmpdir "${IGconf_sys_workdir}/tmp"

# Prepare apt trust roots path if not provided (copying known keydirs)
if [ -z "${IGconf_sys_apt_keydir+x}" ] || [ -z "${IGconf_sys_apt_keydir}" ] ; then
   IGconf_sys_apt_keydir="${IGconf_sys_workdir}/keys"
   mkdir -p "${IGconf_sys_apt_keydir}"
   cp -r /usr/share/keyrings/* "${IGconf_sys_apt_keydir}" 2>/dev/null || true
   cp -r "${HOME}/.local/share/keyrings"/* "${IGconf_sys_apt_keydir}" 2>/dev/null || true
   cp -r "${IGTOP}/keydir"/* "${IGconf_sys_apt_keydir}" 2>/dev/null || true
fi
[ -d "${IGconf_sys_apt_keydir}" ] || die "Missing APT keydir ${IGconf_sys_apt_keydir}"

# Rootfs run env: bdebstrap options + exported env/apt opts
ENV_ROOTFS=()
ENV_POST_BUILD=()

for v in $(set | grep '^IGconf' | cut -d= -f1) ; do
   case $v in
      IGconf_device_timezone)
         ENV_ROOTFS+=("--env" ${v}="${!v}")
         ENV_POST_BUILD+=(${v}="${!v}")
         ENV_ROOTFS+=("--env" IGconf_device_timezone_area="${!v%%/*}")
         ENV_ROOTFS+=("--env" IGconf_device_timezone_city="${!v##*/}")
         ENV_POST_BUILD+=(IGconf_device_timezone_area="${!v%%/*}")
         ENV_POST_BUILD+=(IGconf_device_timezone_city="${!v##*/}")
         ;;
      IGconf_sys_apt_proxy_http)
         err=$(curl --head --silent --write-out "%{http_code}" --output /dev/null "${!v}")
         [[ $? -ne 0 ]] && die "unreachable proxy: ${!v}"
         msg "$err ${!v}"
         ENV_ROOTFS+=("--aptopt" "Acquire::http { Proxy \"${!v}\"; }")
         ENV_ROOTFS+=("--env" ${v}="${!v}")
         ;;
      IGconf_sys_apt_keydir)
         ENV_ROOTFS+=("--aptopt" "Dir::Etc::TrustedParts ${!v}")
         ENV_ROOTFS+=("--env" ${v}="${!v}")
         ;;
      IGconf_sys_apt_get_purge)
         if igconf_isy $v ; then ENV_ROOTFS+=("--aptopt" "APT::Get::Purge true") ; fi
         ;;
      IGconf_ext_dir|IGconf_ext_nsdir )
         ENV_ROOTFS+=("--env" ${v}="${!v}")
         ENV_POST_BUILD+=(${v}="${!v}")
         if [ -d "${!v}/bin" ] ; then
            PATH="${!v}/bin:${PATH}"
            ENV_ROOTFS+=("--env" PATH="$PATH")
            ENV_POST_BUILD+=(PATH="${PATH}")
         fi
         ;;
      *)
         ENV_ROOTFS+=("--env" ${v}="${!v}")
         ENV_POST_BUILD+=(${v}="${!v}")
         ;;
   esac
done

PATH="${IGTOP}/bin:${PATH}"
ENV_ROOTFS+=("--env" PATH="$PATH")
ENV_POST_BUILD+=(PATH="${PATH}")

# Meta layer helpers
layer_push() {
   [[ $# -eq 2 ]] || die "Invalid layer push for $@"
   case $1 in
      image)
         if [[ -s "${IGIMAGE}/meta/$2.yaml" ]] ; then
            [[ -f "${IGIMAGE}/meta/$2.defaults" ]] && \
               aggregate_options "meta" "${IGIMAGE}/meta/$2.defaults"
            ARGS_LAYERS+=("--config" "${IGIMAGE}/meta/$2.yaml")
         fi
         ;;&
      main|auto)
         if [[ -n $EXT_NSMETA && -s "${EXT_NSMETA}/$2.yaml" ]] ; then
            [[ -f "${EXT_NSMETA}/$2.defaults" ]] && \
               aggregate_options "meta" "${EXT_NSMETA}/$2.defaults"
            ARGS_LAYERS+=("--config" "${EXT_NSMETA}/$2.yaml")

         elif [[ -n $EXT_META && -s "${EXT_META}/$2.yaml" ]] ; then
            [[ -f "${EXT_META}/$2.defaults" ]] && \
               aggregate_options "meta" "${EXT_META}/$2.defaults"
            ARGS_LAYERS+=("--config" "${EXT_META}/$2.yaml")

         elif [[ -s "${META}/$2.yaml" ]] ; then
            [[ -f "${META}/$2.defaults" ]] && \
               aggregate_options "meta" "${META}/$2.defaults"
            ARGS_LAYERS+=("--config" "${META}/$2.yaml")
         else
            die "Invalid meta layer specifier: $2 (not found)"
         fi
         ;;
      *)
         die "Invalid layer scope" ;;
   esac
}

ARGS_LAYERS=()
load_profile() {
   [[ $# -eq 2 ]] || die "Load profile bad nargs"
   msg "Load profile $2"
   [[ -f $2 ]] || die "Invalid profile: $2"
   while read -r l ; do
      [[ -z $l ]] && continue
      [[ $l =~ ^#.*$ ]] && continue
      layer_push "$1" "$l"
   done < $2
}

# Load profile: main
load_profile main ${IGPROFILE}

# Load profile: image-specific (optional)
[[ -n ${IGconf_image_profile+x} ]] && [[ -f ${IGIMAGE}/profile/${IGconf_image_profile} ]] && \
   load_profile image ${IGIMAGE}/profile/${IGconf_image_profile}

# Auto-add SSH server layer if requested
if igconf_isy IGconf_device_ssh_user1 ; then
   layer_push auto net-misc/openssh-server
fi

# pre-build: device + share then image + share
if [ -x ${IGTOP_DEVICE}/pre-build.sh ] ; then
   runh ${IGTOP_DEVICE}/pre-build.sh
fi
if [ -x ${IGTOP_IMAGE}/pre-build.sh ] ; then
   runh ${IGTOP_IMAGE}/pre-build.sh
fi
if [ -x ${IGIMAGE}/pre-build.sh ] ; then
   runh ${IGIMAGE}/pre-build.sh
fi
if [ -x ${IGDEVICE}/pre-build.sh ] ; then
   runh ${IGDEVICE}/pre-build.sh
fi

# root filesystem generation
if [[ $ONLY_IMAGE = 0 ]] ; then
   run podman unshare env "${ENV_ROOTFS[@]}" bdebstrap \
      "${ARGS_LAYERS[@]}" \
      --name ${IGconf_sys_name} \
      --hostname ${IGconf_sys_hostname} \
      --output ${IGconf_sys_outputdir} \
      --target ${IGconf_sys_target} \
      --setup-hook 'bin/runner setup "$@"' \
      --essential-hook 'bin/runner essential "$@"' \
      --customize-hook 'bin/runner customize "$@"' \
      --cleanup-hook 'bin/runner cleanup "$@"'
fi

[[ -f "$IGconf_sys_target" ]] && { msg "Exiting as non-directory target complete" ; exit 0 ; }

# post-build: apply rootfs overlays - image layout then device
if [ -d ${IGIMAGE}/device/rootfs-overlay ] ; then
   run podman unshare rsync -a ${IGIMAGE}/device/rootfs-overlay/ ${IGconf_sys_target}
fi
if [ -d ${IGDEVICE}/device/rootfs-overlay ] ; then
   run podman unshare rsync -a ${IGDEVICE}/device/rootfs-overlay/ ${IGconf_sys_target}
fi

# post-build: hooks - image layout then device
if [ -x ${IGIMAGE}/post-build.sh ] ; then
   runh ${IGIMAGE}/post-build.sh ${IGconf_sys_target}
fi
if [ -x ${IGDEVICE}/post-build.sh ] ; then
   runh ${IGDEVICE}/post-build.sh ${IGconf_sys_target}
fi

[[ $ONLY_ROOTFS = 1 ]] && exit $?

# pre-image: hooks - device has priority over image layout
if [ -x ${IGDEVICE}/pre-image.sh ] ; then
   runh ${IGDEVICE}/pre-image.sh ${IGconf_sys_target} ${IGconf_sys_outputdir}
elif [ -x ${IGIMAGE}/pre-image.sh ] ; then
   runh ${IGIMAGE}/pre-image.sh ${IGconf_sys_target} ${IGconf_sys_outputdir}
else
   die "no pre-image hook"
fi

GTMP=$(mktemp -d)
trap 'rm -rf $GTMP' EXIT
mkdir -p "$IGconf_sys_deploydir"

# Generate image(s)
for f in "${IGconf_sys_outputdir}"/genimage*.cfg; do
   [[ -f "$f" ]] || continue
   run podman unshare env "${ENV_POST_BUILD[@]}" genimage \
      --rootpath ${IGconf_sys_target} \
      --tmppath $GTMP \
      --inputpath ${IGconf_sys_outputdir} \
      --outputpath ${IGconf_sys_outputdir} \
      --loglevel=1 \
      --config $f | pv -t -F 'Generating image...%t' || die "genimage error"
done

# post-image: hooks - device has priority over image layout
if [ -x ${IGDEVICE}/post-image.sh ] ; then
   runh ${IGDEVICE}/post-image.sh $IGconf_sys_deploydir
elif [ -x ${IGIMAGE}/post-image.sh ] ; then
   runh ${IGIMAGE}/post-image.sh $IGconf_sys_deploydir
else
   runh ${IGTOP_IMAGE}/post-image.sh $IGconf_sys_deploydir
fi
