# hooks/

Put helper scripts here if you want to call them from bdebstrap hooks, e.g.:

```yaml
mmdebstrap:
  customize-hooks:
    - copy-in hooks/something.sh /usr/local/sbin/something
    - chroot "$1" chmod +x /usr/local/sbin/something
    - chroot "$1" /usr/local/sbin/something --flag
