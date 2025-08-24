#!/usr/bin/env bash

set -eu

KSTOP=$(readlink -f "$(dirname "$0")")
source "${KSTOP}/scripts/dependencies_check"
depf=("${KSTOP}/depends")
for f in "$@" ; do
   depf+=($(realpath -e "$f"))
done
dependencies_install "${depf[@]}"
