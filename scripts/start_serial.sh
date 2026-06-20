#!/usr/bin/env bash
DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

PARENT_IMAGE_PATH="$DIR/../build/arch/x86/boot/bzImage"
PARENT_ROOTFS_PATH="$DIR/../build/rootfs.img"
qemu-system-x86_64 \
  -enable-kvm \
  -cpu host,vmx=on \
  -m 8192 \
  -smp 8 \
  -kernel "$PARENT_IMAGE_PATH" \
  -append "root=/dev/vda rw selinux=0 console=ttyS0 loglevel=8" \
  -drive file="$PARENT_ROOTFS_PATH",format=raw,id=hd0,if=none \
  -device virtio-blk-pci,drive=hd0 \
  -netdev user,id=net0,hostfwd=tcp::6520-:6520,hostfwd=tcp::8443-:8443,hostfwd=tcp::2222-:22 \
  -device virtio-net-pci,netdev=net0 \
  -nographic
