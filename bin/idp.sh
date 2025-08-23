#!/usr/bin/env bash

set -u

BINDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
export PATH="$BINDIR:$PATH"

msg() {
   date +"[%T] $*"
}

err (){
   >&2 msg "$*"
}


die (){
   err "$*"
   exit 1
}

usage()
{
cat <<-EOF >&2
Usage
  $(basename "$0") [options]

Simple provisioner that uses an rpi-image-gen JSON image description to write
the corresponding software image to a remote device running the pi-gen-micro
fastboot gadget.

Options:

-f <json> [-- args] Path to the file created with image2json. Remaing args
                    will be passed to fastboot.
EOF
}


JSON=
FARGS=
while getopts "f:" flag ; do
   case "$flag" in
      f)
         JSON="$OPTARG"
         ;;
      *|?)
         usage ; exit 1
         ;;
   esac
done
[[ -z $JSON ]] && { usage ; die "Require path to JSON file" ; }
realpath -e $JSON > /dev/null 2>&1 || die "$JSON is invalid"

shift $((OPTIND - 1))
FARGS=("$@")


# Dependencies
progs=()
progs+=(fastboot)
for p in "${progs[@]}" ; do
   if ! command -v $p 2>&1 >/dev/null ; then
      die "$p is not installed"
   fi
done


FB() {
if [ "${#FARGS[@]}" -eq 0 ]; then
      fastboot "$@"
   else
      fastboot "${FARGS[@]}" "$@"
   fi
   [[ $? -eq 0 ]] || { err "fastboot: error running ${FARGS[@]} $@" ; false ; }
}


ASSET_DIR=$(pmap -f $JSON --get-key IGmeta.IGconf_sys_outputdir)
[[ -d $ASSET_DIR ]] || die "JSON specified asset dir $ASSET_DIR is invalid"

# Do it

msg "Staging description.."
FB stage $JSON 2>&1 || die "Unable to transfer description to device"

msg "Checking if provisioning is possible.."
FB oem idpinit 2>&1 || die "Pre-provision checks failed"

msg "Initiating provisioning.."
FB oem idpwrite || die "Error writing to device"

while true; do
    output=$(FB oem idpgetblk 2>&1)

    info_resp=$(echo "$output" | grep '^(bootloader)')

    # If there are no more info responses, we're done
    if [[ -z "$info_resp" ]]; then
        break
    fi

    # Write each image into the appointed block device
    while read -r line; do
        if [[ "$line" =~ ^\(bootloader\)\ ([^:]+):(.+)$ ]]; then
            dev="${BASH_REMATCH[1]}"
            image="${BASH_REMATCH[2]}"
            FB flash $dev ${ASSET_DIR}/$image || die "Error writing $image to $dev"
        fi
    done <<< "$info_resp"
done

msg "Complete"

FB oem idpdone || die "Error cleaning up"
