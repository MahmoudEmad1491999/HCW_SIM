DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

validate_path() {
    local target=$1

    if [ ! -e "$target" ]; then
        echo "Path does not Exist ->  $target"
        return 1
    fi

    if [ -d "$target" ]; then 
        if [ -z "$(ls -A "$target") 2>/dev/null" ]; then
            echo "Dummy Folder Exists But Empty -> $target"
            return 1
        fi
        echo "Folder Exists and Not Empty -> $target" 
        return 0
    fi

    if [ -f "$target" ]; then
        echo "File Exists -> $target"
        if [ -s "$target" ]; then
            echo "File Exists and not empty -> $target"
            return 0
        fi
        echo "File Exists But Empty -> $target"
        return 1
    fi

}


if validate_path "$DIR/../build/bzImage"; then
    echo "The Kernel Image Exists, for the Parent -> $(realpath -m $DIR/../build/bzImage)"
else
    echo "The Kernel Image Does Not Exists, for the Parent -> $(realpath -m $DIR/../build/bzImage)"
fi

if validate_path "$DIR/../build/rootfs.img"; then
    echo "The Root File System Does Exists, for the Parent -> $(realpath -m $DIR/../build/rootfs.img)"
else
    echo "The Root File System Does Not Exists, for the Parent -> $(realpath -m $DIR/../build/rootfs.img)"
fi

# qemu-system-x86_64 \
#  -enable-kvm \
#  -cpu host,vmx=on \
#  -m 8192 \
#  -smp 8 \
#  -kernel $DIR/../build/bzImage \
#  -append "root=/dev/vda rw selinux=0 console=ttyS0 loglevel=8" \
#  -drive file=$DIR/../build/rootfs.img,format=raw,id=hd0,if=none \
#  -device virtio-blk-pci,drive=hd0 \
#  -netdev user,id=net0,hostfwd=tcp::6520-:6520,hostfwd=tcp::8443-:8443 \
#  -device virtio-net-pci,netdev=net0 \
#  -nographic

#sudo qemu-system-x86_64 \
#  -enable-kvm \
#  -cpu host,vmx=on \
#  -m 8192 \
#  -smp 8 \
#  -kernel ~/amd64/arch/x86_64/boot/bzImage \
#  -append "root=/dev/vda rw selinux=0 console=ttyS0 loglevel=8" \
#  -drive file=~/amd64/rootfs.img,format=raw,id=hd0,if=none \
#  -device virtio-blk-pci,drive=hd0 \
#  -netdev tap,id=my_tap_interface,ifname=tap0,script=no,downscript=no \
#  -device virtio-net-pci,netdev=my_tap_interface,mac=aa:bb:cc:dd:00:02 \
#  -nographic
#
#
