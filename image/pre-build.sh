#!/bin/bash

set -u

if ksconf isset image_pmap ; then
   [[ -d "${IGIMAGE}/device" ]] || die "No device directory for pmap $KSconf_image_pmap"
   [[ -f "${IGIMAGE}/device/provisionmap-${KSconf_image_pmap}.json" ]] || die "pmap not found"
fi
