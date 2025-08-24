#!/usr/bin/env bash
# Minimal compatibility helpers for build.sh when repo libs don't export them.

_have() { declare -F "$1" >/dev/null 2>&1; }

_have abs_path || abs_path() {
  [ -n "$1" ] || { echo ""; return 0; }
  # Prefer readlink -f, else fall back to a simple echo
  if command -v readlink >/dev/null 2>&1; then
    readlink -f -- "$1" 2>/dev/null || echo "$1"
  else
    echo "$1"
  fi
}

_have is_var_set || is_var_set() { eval "[[ \${$1+_} ]]"; }

_have str_split_to_vars || str_split_to_vars() {
  # $1=PREFIX, $2=DEPTH (unused for now), $3="a.b=c"
  local prefix="$1" s="$3" key val name
  key="${s%%=*}"; val="${s#*=}"
  name="${prefix}_$(echo "$key" | tr '.-' '__')"
  export "$name"="$val"
}

_have load_json_vars || load_json_vars() {
  # Keep the raw payload so we can fish values out later
  INJSON="$1"
  export INJSON
}

_have KS_INLINE || KS_INLINE() {
  # Very small subset used by build.sh:
  #   KS_INLINE CONF set KSBNAME options.config
  #   KS_INLINE CONF get KSBNAME INCONFIG
  #   KS_INLINE CONF set KSMODE build|image
  #   KS_INLINE CONF get KSMODE VAR
  local domain="$1" op="$2" a="$3" b="$4"
  case "$domain $op $a" in
    "CONF set KSBNAME")
      : # marker, nothing to do
      ;;
    "CONF get KSBNAME")
      # Pull options.config from INJSON/INOPTIONS into $b (INCONFIG)
      local v src="${INJSON:-${INOPTIONS:-}}"
      v="$(printf '%s' "$src" | sed -n "s/.*['\"]config['\"]:['\"]\([^'\"]*\)['\"].*/\1/p" | head -n1)"
      [ -n "$v" ] && eval "$b=\"\$v\""
      ;;
    "CONF set KSMODE")
      case "$b" in
        build) KSconf_out_tag="build" ;;
        image) KSconf_out_tag="image" ;;
        *)     KSconf_out_tag="$b" ;;
      esac
      KSconf_sys_deploydir="sys_deploy"
      export KSconf_out_tag KSconf_sys_deploydir
      ;;
    "CONF get KSMODE")
      : # the variables are already exported above
      ;;
  esac
}

_have print_run || print_run() { echo "+ $*"; "$@"; }

_have print_check_dir || print_check_dir() { [ -d "$1" ] || mkdir -p "$1"; }

_have load_options_json_defaults || load_options_json_defaults() { :; }

_have load_klipper_suite_env || load_klipper_suite_env() {
  # Best-effort: source ks_options so KS_* defaults are present
  [ -f "$KSTOP/ks_options" ] && . "$KSTOP/ks_options" || :
}

_have load_default_configs || load_default_configs() {
  : "${KS_SUITE:=bookworm}"
  : "${INCONFIG:=${KS_SUITE}.cfg}"
  if   [ -f "$INCONFIG" ]; then :;
  elif [ -f "$KSTOP/$INCONFIG" ]; then INCONFIG="$KSTOP/$INCONFIG"
  elif [ -f "$KSTOP/config/$INCONFIG" ]; then INCONFIG="$KSTOP/config/$INCONFIG"
  else return 1
  fi
  export INCONFIG
  return 0
}
