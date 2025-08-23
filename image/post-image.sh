#!/bin/bash

set -eu


deploydir=$1

case ${KSconf_image_compression} in
   zstd|none)
      ;;
   *)
      die "Deploy error. Unsupported compression."
      ;;
esac


if [ -f ${KSconf_sys_outputdir}/genimage.cfg ] ; then
   fstabs=()
   opts=()
   fstabs+=("${KSconf_sys_outputdir}"/fstab*)
   for f in "${fstabs[@]}" ; do
      if [ -f "$f" ] ; then
         opts+=('-f' $f)
      fi
   done

   if [ -f ${KSconf_sys_outputdir}/provisionmap.json ] ; then
      opts+=('-m' ${KSconf_sys_outputdir}/provisionmap.json)
   fi
   image2json -g ${KSconf_sys_outputdir}/genimage.cfg "${opts[@]}" > ${KSconf_sys_outputdir}/image.json
fi


files=()

for f in "${KSconf_sys_outputdir}/${KSconf_image_name}"*.${KSconf_image_suffix} ; do
   files+=($f)
   [[ -f "$f" ]] || continue
   
   # Ensure that the output image is a multiple of the selected sector size
   truncate -s %${KSconf_device_sector_size} $f
done

msg "Deploying image"

for f in "${files[@]}" ; do
   [[ -f "$f" ]] || continue
   case ${KSconf_image_compression} in
      zstd)
         zstd -v -f $f --sparse --output-dir-flat $deploydir
         ;;
      none)
         install -v -D -m 644 $f $deploydir
         ;;
      *)
         ;;
   esac
done
