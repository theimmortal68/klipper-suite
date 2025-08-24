#!/usr/bin/env bash

set -uo pipefail

KSTOP=$(readlink -f "$(dirname "$0")")

source "${KSTOP}/scripts/dependencies_check"
dependencies_check "${KSTOP}/depends" || exit 1
source "${KSTOP}/scripts/common"
source "${KSTOP}/scripts/core"
source "${KSTOP}/bin/ksconf"
# after: source "${KSTOP}/bin/ksconf"
[ -f "${KSTOP}/scripts/shim_helpers.sh" ] && . "${KSTOP}/scripts/shim_helpers.sh"


# Defaults
EXT_DIR=
EXT_NSDIR=
EXT_NSNAME=
EXT_NSBUILD=
EXT_NSIMAGE=
EXT_NSHOOKS=
EXT_NSCMDS=
EXT_NSVARS=
EXT_NSMETA=
INOPTIONS=
INCONFIG=${KS_SUITE}.cfg
ONLY_ROOTFS=0
ONLY_IMAGE=0

usage()
{
cat <<-EOF >&2
Usage
  $(basename "$0") [options]

Root filesystem and image generation utility.

Options
  -h, --help           Show this usage message and exit
  -n, --dry-run        Print commands but do NOT run them
  --no-flatten         Keep build and deploy folder structure
  --rootfs             Only generate the root file system
  --image              Only generate the image from an existing rootfs
  -i, --in        STR  Make it possible to use a different options file and or config filename
  -e, --ext       STR  Passes a string that will split into vars with depth 2 i.e. app.version
  -E, --ext-dir   STR  Path to an external namespace dir, structure must follow EXT_NAMESPACE pattern
  -N, --ext-ns    STR  Name of an external namespace within an external namespace dir

	Passing --ext-ns dir is the equivalent of passing --ext-dir /dir and --ext-ns dir

  --ext-nsbuild  PATH  Path to a external namespace build file
  --ext-nsimage  PATH  Path to a external namespace image file
  --ext-nshooks  PATH  Path to a external namespace hooks file
  --ext-nscmds   PATH  Path to a external namespace cmd file
  --ext-nsvars   PATH  Path to a external namespace vars file
  --ext-nsmeta   PATH  Path to a external namespace meta file
EOF
}

get_abs_path(){
	[ -z "$1" ] && echo "" && return
	[ -f "$1" ] && readlink -f "$1" || echo ""
}

EXT_NAMESPACE(){
	[ -z "$EXT_NSDIR" ] || [ ! -d "$EXT_NSDIR" ] && return 0
	[ -z "$EXT_NSNAME" ] && [ -z "$EXT_NSBUILD" ] && [ -z "$EXT_NSIMAGE" ] &&
	[ -z "$EXT_NSHOOKS" ] && [ -z "$EXT_NSCMDS" ] && [ -z "$EXT_NSVARS" ] &&
	[ -z "$EXT_NSMETA" ] && die "External namespace must point to a namespace"
	
	[ -z "$EXT_NSNAME" ] && [ -z "$EXT_NSBUILD" ] && [ -z "$EXT_NSIMAGE" ] && [ -z "$EXT_NSHOOKS" ] && [ -z "$EXT_NSCMDS" ] && [ -z "$EXT_NSVARS" ] && [ -z "$EXT_NSMETA" ] &&
	   die "Using the external namespace folder requires using --ext-ns (and or) all or a custom list of ns files"
	
	NSPATH="${EXT_NSDIR}"
	[ -n "$EXT_NSNAME" ] && NSPATH+="/${EXT_NSNAME}"
	NSSCRIPTS="${NSPATH}/scripts"
	
	[ -n "$EXT_NSBUILD" ] && EXT_NSBUILD=$(get_abs_path "${EXT_NSBUILD}")
	[ -n "$EXT_NSIMAGE" ] && EXT_NSIMAGE=$(get_abs_path "${EXT_NSIMAGE}")
	[ -n "$EXT_NSHOOKS" ] && EXT_NSHOOKS=$(get_abs_path "${EXT_NSHOOKS}")
	[ -n "$EXT_NSCMDS" ] && EXT_NSCMDS=$(get_abs_path "${EXT_NSCMDS}")
	[ -n "$EXT_NSVARS" ] && EXT_NSVARS=$(get_abs_path "${EXT_NSVARS}")
	[ -n "$EXT_NSMETA" ] && EXT_NSMETA=$(get_abs_path "${EXT_NSMETA}")
	
	[ -z "$EXT_NSBUILD" ] && EXT_NSBUILD=$(get_abs_path "${NSSCRIPTS}/build.json")
	[ -z "$EXT_NSIMAGE" ] && EXT_NSIMAGE=$(get_abs_path "${NSSCRIPTS}/image.json")
	[ -z "$EXT_NSHOOKS" ] && EXT_NSHOOKS=$(get_abs_path "${NSSCRIPTS}/hooks.json")
	[ -z "$EXT_NSCMDS" ] && EXT_NSCMDS=$(get_abs_path "${NSSCRIPTS}/commands.sh")
	[ -z "$EXT_NSVARS" ] && EXT_NSVARS=$(get_abs_path "${NSSCRIPTS}/config.json")
	[ -z "$EXT_NSMETA" ] && EXT_NSMETA=$(get_abs_path "${NSSCRIPTS}/metadata.json")
	
	[ -n "$EXT_NSBUILD" ] && [ -f "$EXT_NSBUILD" ] || die "External namespace DNE $EXT_NSBUILD"
	[ -n "$EXT_NSIMAGE" ] && [ -f "$EXT_NSIMAGE" ] || die "External namespace DNE $EXT_NSIMAGE"
	[ -n "$EXT_NSHOOKS" ] && [ -f "$EXT_NSHOOKS" ] || die "External namespace DNE $EXT_NSHOOKS"
	[ -n "$EXT_NSCMDS" ] && [ -f "$EXT_NSCMDS" ] || die "External namespace DNE $EXT_NSCMDS"
	[ -n "$EXT_NSVARS" ] && [ -f "$EXT_NSVARS" ] || die "External namespace DNE $EXT_NSVARS"
	[ -n "$EXT_NSMETA" ] && [ -f "$EXT_NSMETA" ] || die "External namespace DNE $EXT_NSMETA"
}

load_ext_ns(){
	[ -z "$EXT_NSDIR" ] && [ -z "$EXT_NSNAME" ] && [ -z "$EXT_NSBUILD" ] && [ -z "$EXT_NSIMAGE" ] &&
	[ -z "$EXT_NSHOOKS" ] && [ -z "$EXT_NSCMDS" ] && [ -z "$EXT_NSVARS" ] && [ -z "$EXT_NSMETA" ] && return 0

	EXT_NAMESPACE || return 0
	
	echo "Setting EXTERNAL NAMESPACE"
	export KS_NS_DIR="${EXT_NSDIR}"
	export KS_NS_SCRIPTS="${NSSCRIPTS}"
	
	[ -n "$EXT_NSVARS" ] && export KS_NS_VARS="$EXT_NSVARS"
	[ -n "$EXT_NSBUILD" ] && export KS_NS_BUILD="$EXT_NSBUILD"
	[ -n "$EXT_NSIMAGE" ] && export KS_NS_IMAGE="$EXT_NSIMAGE"
	[ -n "$EXT_NSHOOKS" ] && export KS_NS_HOOKS="$EXT_NSHOOKS"
	[ -n "$EXT_NSCMDS" ] && export KS_NS_COMMANDS="$EXT_NSCMDS"
	[ -n "$EXT_NSMETA" ] && export KS_NS_META="$EXT_NSMETA"
}

override_default_paths(){
	[ -z "$INOPTIONS" ] && return 0
	load_json_vars "${INOPTIONS}"
	
	if is_var_set options.config; then
		KS_INLINE CONF set KSBNAME options.config
		KS_INLINE CONF get KSBNAME INCONFIG
		unset KSBNAME
	fi
}

run_dry(){
	env | sort | grep -E "^KS_" >&2
	
	echo -e "\nPrinting commands only..." >&2
	print_run bdebstrap --ksconf runr $INCONFIG
	print_run bdebstrap --ksconf runh ${KSTOP}/image/mbr/simple_dual/pre-image.sh $KSTOP/work/$KSconf_out_tag $KSTOP/work/$KSconf_sys_deploydir
	print_run bdebstrap --ksconf runh ${KSTOP}/image/mbr/simple_dual/post-image.sh $KSTOP/work/$KSconf_out_tag $KSTOP/work/$KSconf_sys_deploydir
	print_run bdebstrap --ksconf runh ${KSTOP}/image/mbr/simple_dual/pre-image.sh $KSTOP_IMAGE $KSTOP_ARTE $KSTOP_WORKDIR
	print_run bdebstrap --ksconf runh ${KSTOP}/image/mbr/simple_dual/post-image.sh $KSTOP_IMAGE $KSTOP_ARTE $KSTOP_WORKDIR
}

main(){
	KSTOP_IMAGE=
	KSTOP_ARTE=
	KSTOP_WORKDIR=
	
	if is_var_set KSTOP_IMAGE; then KSTOP_IMAGE=$(abs_path "${KSTOP_IMAGE}"); fi
	if is_var_set KSTOP_ARTE; then KSTOP_ARTE=$(abs_path "${KSTOP_ARTE}"); fi
	if is_var_set KSTOP_WORKDIR; then KSTOP_WORKDIR=$(abs_path "${KSTOP_WORKDIR}"); fi
	
	[ -f "$KSTOP/bin/ksconf" ] || die "missing ksconf"

	load_options_json_defaults
	load_klipper_suite_env
	
	override_default_paths
	
	if ! dependencies_check "${KSTOP}/depends"; then
		return 1
	fi

	load_ext_ns
	
	[ -f "$KSTOP/bin/ksconf.log" ] && mv -f "$KSTOP/bin/ksconf.log" "$KSTOP/bin/ksconf.log.old"
	
	if [ -n "$KSTOP_IMAGE" ]; then
		print_check_dir "$KSTOP_IMAGE"
		print_check_dir "$KSTOP_ARTE"
		print_check_dir "$KSTOP_WORKDIR"
	fi
	
	if [ $# -gt 0 ]; then
		while [ $# -gt 0 ]
		do
			case "$1" in
				-h|--help) usage; exit 0 ;;
				-n|--dry-run) set -x; run_dry; exit 0 ;;
				-i|--in) INOPTIONS="$2"; shift ;;
				--in=*) INOPTIONS="${1#--in=}" ;;
				-e|--ext) str_split_to_vars EXT_DIR 2 "$2"; shift ;;
				--ext=*) str_split_to_vars EXT_DIR 2 "${1#--ext=}" ;;
				-E|--ext-dir) EXT_NSDIR=$(get_abs_path "$2"); shift ;;
				--ext-dir=*) EXT_NSDIR=$(get_abs_path "${1#--ext-dir=}") ;;
				-N|--ext-ns) EXT_NSNAME="$2"; shift ;;
				--ext-ns=*) EXT_NSNAME="${1#--ext-ns=}" ;;
				--ext-nsbuild) EXT_NSBUILD="$2"; shift ;;
				--ext-nsbuild=*) EXT_NSBUILD="${1#--ext-nsbuild=}" ;;
				--ext-nsimage) EXT_NSIMAGE="$2"; shift ;;
				--ext-nsimage=*) EXT_NSIMAGE="${1#--ext-nsimage=}" ;;
				--ext-nshooks) EXT_NSHOOKS="$2"; shift ;;
				--ext-nshooks=*) EXT_NSHOOKS="${1#--ext-nshooks=}" ;;
				--ext-nscmds) EXT_NSCMDS="$2"; shift ;;
				--ext-nscmds=*) EXT_NSCMDS="${1#--ext-nscmds=}" ;;
				--ext-nsvars) EXT_NSVARS="$2"; shift ;;
				--ext-nsvars=*) EXT_NSVARS="${1#--ext-nsvars=}" ;;
				--ext-nsmeta) EXT_NSMETA="$2"; shift ;;
				--ext-nsmeta=*) EXT_NSMETA="${1#--ext-nsmeta=}" ;;
				*) die "Unknown argument '$1'" ;;
			esac
			shift
		done
	fi

	if [ $ONLY_ROOTFS -eq 1 ] && [ $ONLY_IMAGE -eq 1 ]; then
		die "Cannot use --rootfs AND --image"
	fi

	load_default_configs || die "Failed to load the configs"
	
	[ $ONLY_IMAGE -eq 1 ] || {
		KS_INLINE CONF set KSMODE build
		KS_INLINE CONF get KSMODE KSconf_out_tag
		print_run bdebstrap --ksconf runr "$INCONFIG"
	}
	
	KS_INLINE CONF set KSMODE image
	KS_INLINE CONF get KSMODE KSconf_out_tag
	print_run bdebstrap --ksconf runh ${KSTOP}/image/mbr/simple_dual/pre-image.sh $KSTOP/work/$KSconf_out_tag $KSTOP/work/$KSconf_sys_deploydir
	print_run bdebstrap --ksconf runh ${KSTOP}/image/mbr/simple_dual/post-image.sh $KSTOP/work/$KSconf_out_tag $KSTOP/work/$KSconf_sys_deploydir
	
	if [ "/tmp" = "${KSTOP_IMAGE:-/tmp}" ]; then
		print_run bdebstrap --ksconf runh ${KSTOP}/image/mbr/simple_dual/pre-image.sh $KSTOP_IMAGE $KSTOP_ARTE $KSTOP_WORKDIR
		print_run bdebstrap --ksconf runh ${KSTOP}/image/mbr/simple_dual/post-image.sh $KSTOP_IMAGE $KSTOP_ARTE $KSTOP_WORKDIR
	fi
}
main "$@"
