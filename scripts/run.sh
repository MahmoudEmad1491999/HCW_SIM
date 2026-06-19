DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

PARENT_IMAGE_PATH="$DIR/../build/arch/x86/boot/bzImage"
PARENT_ROOTFS_PATH="$DIR/../build/rootfs.img"
LINUX_KERNEL_TARBALL="$DIR/../third_party/os/linux-6.19.tar.gz"
LINUX_KERNEL_SOURCE_DIR="$DIR/../third_party/linux_kernel/"


validate_path() {
    local target="$1"

    # 1. Check if the path exists at all
    if [ ! -e "$target" ]; then
        echo "❌ Path does not Exist ->  $target"
        return 1
    fi

    # 2. Handle Directories
    if [ -d "$target" ]; then 
        # FIX: Moved the quote to the very end of the subshell command
        if [ -z "$(ls -A "$target" 2>/dev/null)" ]; then
            echo "❌ Dummy Folder Exists But Empty -> $target"
            return 1
        fi
        echo "✅ Folder Exists and Not Empty -> $target" 
        return 0
    fi

    # 3. Handle Files
    if [ -f "$target" ]; then
        # Check if it is completely 0 bytes
        if [ ! -s "$target" ]; then
            echo "❌ File Exists But Empty (0 bytes) -> $target"
            return 1
        fi

        # NEW: Catch if it's just a Git LFS placeholder text pointer
        if head -n 1 "$target" 2>/dev/null | grep -q "^version https://git-lfs.github.com/spec/v1"; then
            echo "❌ File Exists But is an un-pulled Git LFS pointer! -> $target"
            return 1
        fi

        echo "✅ File Exists, Populated, and Not a Pointer -> $target"
        return 0
    fi
}



extract_linux_kernel() {
    local kernel_tarball="$1"
    local target_dir="$2"

    if [ ! -f "$kernel_tarball" ]; then
        echo "❌ Kernel tarball does not exist: $kernel_tarball"
        return 1
    fi

    mkdir -p "$target_dir"
    tar -xvzf "$kernel_tarball" -C "$target_dir" --strip-components=1
    echo "✅ Extracted Linux Kernel Source Code to: $target_dir"
}


# build_custom_linux_kernel() {
#     local kernel_dir="$1"
#     local build_dir="$2"
#     echo "Building Linux Kernel from source in: $kernel_dir"
#     echo "Build output will be in: $build_dir"

#     if [ ! -d "$kernel_dir" ]; then
#         echo "❌ Kernel source directory does not exist: $kernel_dir"
#         return 1
#     fi
#     cd "$kernel_dir"
#     LINUX_SOURCE_DIR=$(realpath -m "$kernel_dir")
#     make -C "$LINUX_SOURCE_DIR" O="$build_dir" defconfig ARCH=x86_64
#     LINUX_SOURCE_DIR=$(realpath -m "$kernel_dir")
#     # 1. Enable Core Virtualization and KVM
#     $LINUX_SOURCE_DIR/scripts/config --enable CONFIG_VIRTUALIZATION
#     $LINUX_SOURCE_DIR/scripts/config --enable CONFIG_KVM
#     if grep -q "GenuineIntel" /proc/cpuinfo; then
#         echo "Intel CPU detected. Enabling KVM for Intel."
#         $LINUX_SOURCE_DIR/scripts/config --enable CONFIG_KVM_INTEL   # Enable if your host is Intel
#     elif grep -q "AuthenticAMD" /proc/cpuinfo; then
#         echo "AMD CPU detected. Enabling KVM for AMD."
#         $LINUX_SOURCE_DIR/scripts/config --enable CONFIG_KVM_AMD     # Enable if your host is AMD
#     else
#         echo "Unknown CPU vendor. Please enable KVM manually in the kernel config."
#     fi

#     # 2. Enable Core VirtIO Infrastructure (Crucial for VM-to-VM efficiency)
#     $LINUX_SOURCE_DIR/scripts/config --enable CONFIG_VIRTIO
#     $LINUX_SOURCE_DIR/scripts/config --enable CONFIG_VIRTIO_MENU
#     $LINUX_SOURCE_DIR/scripts/config --enable CONFIG_VIRTIO_PCI
#     $LINUX_SOURCE_DIR/scripts/config --enable CONFIG_VIRTIO_BALLOON
#     # 5. CAN Bus Simulation (Allows L1 and L2 to talk via Virtual CAN)
#     $LINUX_SOURCE_DIR/scripts/config --enable CONFIG_CAN
#     $LINUX_SOURCE_DIR/scripts/config --enable CONFIG_CAN_RAW
#     $LINUX_SOURCE_DIR/scripts/config --enable CONFIG_CAN_VCAN
#     # 6. VirtIO 9P File System (Allows mounting folders from L0 host to L1 VM seamlessly)
#     $LINUX_SOURCE_DIR/scripts/config --enable CONFIG_NET_9P
#     $LINUX_SOURCE_DIR/scripts/config --enable CONFIG_NET_9P_VIRTIO
#     $LINUX_SOURCE_DIR/scripts/config --enable CONFIG_9P_FS
#     make -C "$LINUX_SOURCE_DIR" O="$build_dir" ARCH=x86_64 olddefconfig
#     make -C "$LINUX_SOURCE_DIR" O="$build_dir" -j$(nproc) | tee $DIR/../build/linux_kernel_build.log

#     echo "✅ Built Linux Kernel Image in: $kernel_dir"
# }


build_custom_linux_kernel() {
    local kernel_dir="$1"
    local build_dir="$2"
    
    echo "Building Linux Kernel from source in: $kernel_dir"
    echo "Build output will be in: $build_dir"

    # Validate kernel source directory
    if [ ! -d "$kernel_dir" ]; then
        echo "❌ Kernel source directory does not exist: $kernel_dir"
        return 1
    fi

    # Absolute paths calculations
    local linux_source_dir
    local linux_build_dir
    linux_source_dir=$(realpath -m "$kernel_dir")
    linux_build_dir=$(realpath -m "$build_dir")

    # Ensure output build directory exists
    mkdir -p "$linux_build_dir"

    # Step into source directory to clean it up
    cd "$linux_source_dir" || return 1

    # FIX 1: Safely sanitize the source tree so out-of-tree compilation doesn't crash
    echo "🧹 Sanitizing kernel source directory..."
    make ARCH=x86_64 mrproper

    # Generate baseline default config directly inside the build directory
    echo "⚙️ Generating default defconfig..."
    make -C "$linux_source_dir" O="$linux_build_dir" defconfig ARCH=x86_64

    # Target path for config manipulations
    local target_config="$linux_build_dir/.config"
    local config_script="$linux_source_dir/scripts/config"

    echo "🔧 Applying nested virtualization configurations..."

    # FIX 2: Added '--file "$target_config"' to all script calls so edits map to the build dir
    # 1. Enable Core Virtualization and KVM
    "$config_script" --file "$target_config" --enable CONFIG_VIRTUALIZATION
    "$config_script" --file "$target_config" --enable CONFIG_KVM
    
    if grep -q "GenuineIntel" /proc/cpuinfo; then
        echo "🧬 Intel CPU detected. Enabling KVM for Intel."
        "$config_script" --file "$target_config" --enable CONFIG_KVM_INTEL
        "$config_script" --file "$target_config" --disable CONFIG_KVM_AMD
    elif grep -q "AuthenticAMD" /proc/cpuinfo; then
        echo "🧬 AMD CPU detected. Enabling KVM for AMD."
        "$config_script" --file "$target_config" --enable CONFIG_KVM_AMD
        "$config_script" --file "$target_config" --disable CONFIG_KVM_INTEL
    else
        echo "⚠️ Unknown CPU vendor. Skipping automated hardware-specific KVM configuration."
    fi

    # 2. Enable Core VirtIO Infrastructure
    "$config_script" --file "$target_config" --enable CONFIG_VIRTIO
    "$config_script" --file "$target_config" --enable CONFIG_VIRTIO_MENU
    "$config_script" --file "$target_config" --enable CONFIG_VIRTIO_PCI
    "$config_script" --file "$target_config" --enable CONFIG_VIRTIO_BALLOON
    
    # 5. CAN Bus Simulation (L1 <-> L2 communication)
    "$config_script" --file "$target_config" --enable CONFIG_CAN
    "$config_script" --file "$target_config" --enable CONFIG_CAN_RAW
    "$config_script" --file "$target_config" --enable CONFIG_CAN_VCAN
    
    # 6. VirtIO 9P File System (L0 Host <-> L1 Car sharing)
    "$config_script" --file "$target_config" --enable CONFIG_NET_9P
    "$config_script" --file "$target_config" --enable CONFIG_NET_9P_VIRTIO
    "$config_script" --file "$target_config" --enable CONFIG_9P_FS

    # Force build system to parse changes and auto-resolve hidden dependencies
    echo "🔄 Resolving Kconfig internal dependencies..."
    make -C "$linux_source_dir" O="$linux_build_dir" ARCH=x86_64 olddefconfig

    # Ensure log output directory exists before compiling
    mkdir -p "$(dirname "$linux_build_dir/linux_kernel_build.log")"

    # Compile the kernel
    echo "🚀 Starting compilation across $(nproc) threads..."
    make -C "$linux_source_dir" O="$linux_build_dir" ARCH=x86_64 -j$(nproc) 2>&1 | tee "$linux_build_dir/linux_kernel_build.log"

    # Check build output
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        echo "✅ Successfully built Linux Kernel Image!"
        echo "👉 Final Artifact: $linux_build_dir/arch/x86/boot/bzImage"
        return 0
    else
        echo "❌ Kernel compilation failed! View log at: $linux_build_dir/linux_kernel_build.log"
        return 1
    fi
}


if ! validate_path "$PARENT_IMAGE_PATH"; then
    echo "❌ Parent Image Does Not Exist."
    if ! validate_path "$LINUX_KERNEL_SOURCE_DIR"; then
        echo "❌ Linux Kernel Source Does Not Exist. Extracting..."
        extract_linux_kernel "$LINUX_KERNEL_TARBALL" "$LINUX_KERNEL_SOURCE_DIR"
    fi
    echo "✅ Building Custom Linux Kernel..."
    build_custom_linux_kernel "$LINUX_KERNEL_SOURCE_DIR" "$DIR/../build"
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
