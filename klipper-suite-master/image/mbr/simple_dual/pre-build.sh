#!/bin/bash

set -u

case $KSconf_image_rootfs_type in
   ext4|btrfs)
      ;;
   *)
      die "Unsupported rootfs type ($KSconf_image_rootfs_type)."
      ;;
esac
