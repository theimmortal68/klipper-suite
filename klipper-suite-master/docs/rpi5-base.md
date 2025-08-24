# Raspberry Pi 5 — Base profile (master)

Included by default on master for Pi 5:
- Raspberry Pi APT repo with signed-by and APT preference (origin archive.raspberrypi.com)
- Kernel defaults: `linux-image-rpi-2712`, `raspberrypi-bootloader`, `libraspberrypi-*`, `rpi-eeprom`, `firmware-brcm80211`
- Camera stack: Crowsnest with `ustreamer` backend; default config at `/etc/crowsnest/crowsnest.conf`

You can override camera backend by exporting:
```
KS_PI5_CAMERA_BACKEND=camera-streamer   # not recommended on Pi 5
```
