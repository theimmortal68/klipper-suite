#!/bin/bash

set -u

case ${KSconf_device_storage_type:?} in
   sd|emmc|nvme)
      ;;
   *)
      die "Unsupported device storage type: $KSconf_device_storage_type"
      ;;
esac

case ${KSconf_device_sector_size:?} in
   512)
      ;;
   *)
      die "Unsupported device sector size: $KSconf_device_storage_type"
      ;;
esac
