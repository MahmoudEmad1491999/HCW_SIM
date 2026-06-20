 #!/usr/bin/env bash
set -euo pipefail

DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

# --- Privilege handling: Enforced sudo for native root operations ---
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi
echo "SUDO :- $SUDO"
# --- Concurrency lock ---
LOCKFILE="${TMPDIR:-/tmp}/build_rootfs.lock"
exec 200>"$LOCKFILE"
if ! flock -n 200; then
    echo "❌ Another build is already running (lock: $LOCKFILE). Exiting."
    exit 1
fi

# --- Generic retry helper ---
retry() {
    local max=3 delay=15 n=0
    until "$@"; do
        n=$((n + 1))
        if [ "$n" -ge "$max" ]; then
            echo "❌ Command failed after $max attempts: $*"
            return 1
        fi
        echo "⚠️ Attempt $n failed, retrying in ${delay}s..."
        sleep "$delay"
    done
}

PARENT_IMAGE_PATH="$DIR/../build/arch/x86/boot/bzImage"
PARENT_ROOTFS_PATH="$DIR/../build/rootfs.img"
LINUX_KERNEL_TARBALL="$DIR/../third_party/os/linux-6.19.tar.gz"
LINUX_KERNEL_SOURCE_DIR="$DIR/../third_party/linux_kernel/"

SUITE="bookworm"
MIRROR="http://deb.debian.org/debian/"
DEBIAN_KEYRING="/usr/share/keyrings/debian-archive-keyring.gpg"
HOST_CACHE="${CI_CACHE_DIR:-$HOME/.cache}/debootstrap-debs/${SUITE}-amd64"
IMAGE_SIZE_MB=10240

ensure_host_dependencies() {
    # Removed fakeroot and fakechroot dependencies
    local pkgs=(debootstrap debian-archive-keyring e2fsprogs)
    local missing=()
    for p in "${pkgs[@]}"; do
        dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        echo "📦 Installing missing dependencies: ${missing[*]}"
        export DEBIAN_FRONTEND=noninteractive
        $SUDO apt-get update -qq
        $SUDO apt-get install -y -qq "${missing[@]}"
    fi
}

check_disk_space() {
    local target_dir="$1" required_mb="$2" available_mb
    available_mb=$(df --output=avail -m "$target_dir" | tail -1 | tr -d ' ')
    if [ "$available_mb" -lt "$required_mb" ]; then
        echo "❌ Insufficient disk space in $target_dir: need ${required_mb}MB, have ${available_mb}MB"
        return 1
    fi
}

build_custom_bootstraped_rootfs() {
    local build_dir="$1"
    local rootfs_path="$2"

    echo "Building custom bootstrap root filesystem with root privileges in: $build_dir"
    echo "Root filesystem output will be at: $rootfs_path"

    ensure_host_dependencies

    if [ ! -f "$DEBIAN_KEYRING" ]; then
        echo "❌ $DEBIAN_KEYRING still missing after dependency install."
        return 1
    fi

    check_disk_space "$(dirname "$rootfs_path")" "$IMAGE_SIZE_MB"

    # Clean up previous run states (requires sudo since files are root-owned)
    $SUDO rm -rf "$build_dir"
    rm -f "$rootfs_path"
    mkdir -p "$HOST_CACHE"

    echo "⚙️ Bootstrapping $SUITE (via native sudo debootstrap)..."
    retry $SUDO debootstrap --arch=amd64 \
        --keyring="$DEBIAN_KEYRING" \
        --include=openssh-server \
        --cache-dir="$HOST_CACHE" \
        "$SUITE" "$build_dir" "$MIRROR"

    echo "🔧 Automating DHCP provisioning configuration for network interface enp0s4..."
    $SUDO mkdir -p "$build_dir/etc/network"
    cat << 'EOF' | $SUDO tee "$build_dir/etc/network/interfaces" > /dev/null

# Added via automated bootstrap build configuration to prevent boot amnesia
auto enp0s4
iface enp0s4 inet dhcp
EOF

    echo "🧹 Cleaning apt cache inside rootfs..."
    $SUDO rm -rf "$build_dir/var/cache/apt/archives"/*

    echo "💾 Creating ${IMAGE_SIZE_MB}MB raw disk image..."
    dd if=/dev/zero of="$rootfs_path" bs=1M count="$IMAGE_SIZE_MB" status=none

    echo "🚀 Populating ext4 filesystem directly (bypassing mount)..."
    $SUDO mkfs.ext4 -F -q -d "$build_dir" "$rootfs_path"

    echo "👤 Adjusting ownership of final rootfs image for user space execution..."
    $SUDO chown "$(id -u):$(id -g)" "$rootfs_path"

    # Clean up intermediate root-owned build tree
    $SUDO rm -rf "$build_dir"
    echo "✅ Successfully built custom bootstrap root filesystem natively!"
}

validate_path() {
    local target="$1"

    if [ ! -e "$target" ]; then
        echo "❌ Path does not Exist ->  $target"
        return 1
    fi

    if [ -d "$target" ]; then
        if [ -z "$(ls -A "$target" 2>/dev/null)" ]; then
            echo "❌ Dummy Folder Exists But Empty -> $target"
            return 1
        fi
        echo "✅ Folder Exists and Not Empty -> $target"
        return 0
    fi

    if [ -f "$target" ]; then
        if [ ! -s "$target" ]; then
            echo "❌ File Exists But Empty (0 bytes) -> $target"
            return 1
        fi
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
    tar -xzf "$kernel_tarball" -C "$target_dir" --strip-components=1
    echo "✅ Extracted Linux Kernel Source Code to: $target_dir"
}

build_custom_linux_kernel() {
    local kernel_dir="$1"
    local build_dir="$2"

    echo "Building Linux Kernel from source in: $kernel_dir"
    echo "Build output will be in: $build_dir"

    if [ ! -d "$kernel_dir" ]; then
        echo "❌ Kernel source directory does not exist: $kernel_dir"
        return 1
    fi

    local linux_source_dir
    local linux_build_dir
    linux_source_dir=$(realpath -m "$kernel_dir")
    linux_build_dir=$(realpath -m "$build_dir")

    mkdir -p "$linux_build_dir"
    cd "$linux_source_dir"

    echo "🧹 Sanitizing kernel source directory..."
    make ARCH=x86_64 mrproper

    echo "⚙️ Generating default defconfig..."
    make -C "$linux_source_dir" O="$linux_build_dir" defconfig ARCH=x86_64

    local target_config="$linux_build_dir/.config"
    local config_script="$linux_source_dir/scripts/config"

    echo "🔧 Applying nested virtualization configurations..."
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

    "$config_script" --file "$target_config" --enable CONFIG_VIRTIO
    "$config_script" --file "$target_config" --enable CONFIG_VIRTIO_MENU
    "$config_script" --file "$target_config" --enable CONFIG_VIRTIO_PCI
    "$config_script" --file "$target_config" --enable CONFIG_VIRTIO_BALLOON

    "$config_script" --file "$target_config" --enable CONFIG_CAN
    "$config_script" --file "$target_config" --enable CONFIG_CAN_RAW
    "$config_script" --file "$target_config" --enable CONFIG_CAN_VCAN

    "$config_script" --file "$target_config" --enable CONFIG_NET_9P
    "$config_script" --file "$target_config" --enable CONFIG_NET_9P_VIRTIO
    "$config_script" --file "$target_config" --enable CONFIG_9P_FS

    echo "🔄 Resolving Kconfig internal dependencies..."
    make -C "$linux_source_dir" O="$linux_build_dir" ARCH=x86_64 olddefconfig

    mkdir -p "$(dirname "$linux_build_dir/linux_kernel_build.log")"

    echo "🚀 Starting compilation across $(nproc) threads..."
    make -C "$linux_source_dir" O="$linux_build_dir" ARCH=x86_64 -j"$(nproc)" 2>&1 \
        | tee "$linux_build_dir/linux_kernel_build.log" || true
    local build_exit_code=${PIPESTATUS[0]}

    if [ "$build_exit_code" -eq 0 ]; then
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

if ! validate_path "$PARENT_ROOTFS_PATH"; then
    echo "❌ Parent RootFS Image Does Not Exist."
    echo "✅ Building Custom Bootstraped RootFS..."
    build_custom_bootstraped_rootfs "$DIR/../build/rootfs_build" "$PARENT_ROOTFS_PATH"
fi

# sudo umount $DIR/../mnt
sudo mount $PARENT_ROOTFS_PATH $DIR/../mnt
sudo chroot $DIR/../mnt passwd
sudo chroot "$DIR/../mnt" sh << 'EOF'
LINE="PermitRootLogin yes"
FILE="/etc/ssh/sshd_config"

# Ensure file exists
touch "$FILE"

# Check if the last line matches
if [ "$(tail -n 1 "$FILE" 2>/dev/null)" != "$LINE" ]; then
    # If the file isn't empty and doesn't end with a newline, add one first
    if [ -s "$FILE" ] && [ "$(tail -c 1 "$FILE")" != $'\n' ]; then
        echo "" >> "$FILE"
    fi
    echo "$LINE" >> "$FILE"
    echo "✅ Line appended successfully inside chroot!"
fi
EOF
sudo chroot "$DIR/../mnt" sh -c 'cat /etc/ssh/sshd_config'

sudo umount $DIR/../mnt
