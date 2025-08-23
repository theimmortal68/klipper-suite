#!/bin/sh

set -eu

rootfs=$1
genimg_in=$2

SETUP=setup.sh


# Install provision map
if igconf isset image_pmap ; then
   cp ./device/provisionmap-${IGconf_image_pmap}.json ${IGconf_sys_outputdir}/provisionmap.json
fi


# Generate pre-defined UUIDs
BOOT_LABEL=$(uuidgen | sed 's/-.*//' | tr 'a-f' 'A-F')
BOOT_UUID=$(echo "$BOOT_LABEL" | sed 's/^\(....\)\(....\)$/\1-\2/')
ROOT_UUID=$(uuidgen)
CRYPT_UUID=$(uuidgen)

rm -f ${IGconf_sys_outputdir}/img_uuids
for v in BOOT_LABEL BOOT_UUID ROOT_UUID CRYPT_UUID; do
    eval "val=\$$v"
    echo "$v=$val" >> "${IGconf_sys_outputdir}/img_uuids"
done


# Write genimage template
cat genimage.cfg.in.$IGconf_image_rootfs_type | sed \
   -e "s|<IMAGE_DIR>|$IGconf_sys_outputdir|g" \
   -e "s|<IMAGE_NAME>|$IGconf_image_name|g" \
   -e "s|<IMAGE_SUFFIX>|$IGconf_image_suffix|g" \
   -e "s|<FW_SIZE>|$IGconf_image_boot_part_size|g" \
   -e "s|<ROOT_SIZE>|$IGconf_image_root_part_size|g" \
   -e "s|<SECTOR_SIZE>|$IGconf_device_sector_size|g" \
   -e "s|<SETUP>|'$(readlink -ef $SETUP)'|g" \
   -e "s|<MKE2FSCONF>|'$(readlink -ef mke2fs.conf)'|g" \
   -e "s|<BOOT_LABEL>|$BOOT_LABEL|g" \
   -e "s|<BOOT_UUID>|$BOOT_UUID|g" \
   -e "s|<ROOT_UUID>|$ROOT_UUID|g" \
   > ${genimg_in}/genimage.cfg


# Populate PMAP UUIDs
sed -i \
   -e "s|<CRYPT_UUID>|$CRYPT_UUID|g" ${IGconf_sys_outputdir}/provisionmap.json
