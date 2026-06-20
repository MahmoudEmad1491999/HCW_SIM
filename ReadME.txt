    # 1. Enable Core Virtualization and KVM
    $linux_kernel_source_dir/scripts/config --enable CONFIG_VIRTUALIZATION
    $linux_kernel_source_dir/scripts/config --enable CONFIG_KVM
    $linux_kernel_source_dir/scripts/config --enable CONFIG_KVM_INTEL   # Enable if your host is Intel
    $linux_kernel_source_dir/scripts/config --enable CONFIG_KVM_AMD     # Enable if your host is AMD

    # 2. Enable Core VirtIO Infrastructure (Crucial for VM-to-VM efficiency)
    $linux_kernel_source_dir/scripts/config --enable CONFIG_VIRTIO
    $linux_kernel_source_dir/scripts/config --enable CONFIG_VIRTIO_MENU
    $linux_kernel_source_dir/scripts/config --enable CONFIG_VIRTIO_PCI
    $linux_kernel_source_dir/scripts/config --enable CONFIG_VIRTIO_BALLOON

    # 3. Virtual Network Routing (Bridging and TUN/TAP for L2 VM interfaces)
./scripts/config --enable CONFIG_BRIDGE
./scripts/config --enable CONFIG_NET_CORE
./scripts/config --enable CONFIG_TUN
./scripts/config --enable CONFIG_VIRTIO_NET

# 4. Storage Drivers for Virtual Disks
./scripts/config --enable CONFIG_BLK_DEV
./scripts/config --enable CONFIG_BLK_DEV_LOOP
./scripts/config --enable CONFIG_VIRTIO_BLK
./scripts/config --enable CONFIG_VIRTIO_SCSI


# 5. CAN Bus Simulation (Allows L1 and L2 to talk via Virtual CAN)
./scripts/config --enable CONFIG_CAN
./scripts/config --enable CONFIG_CAN_RAW
./scripts/config --enable CONFIG_CAN_VCAN

# 6. VirtIO 9P File System (Allows mounting folders from L0 host to L1 VM seamlessly)
./scripts/config --enable CONFIG_NET_9P
./scripts/config --enable CONFIG_NET_9P_VIRTIO
./scripts/config --enable CONFIG_9P_FS



######################################## PARENT OPTIONS

    # 1. Enable Core Virtualization and KVM
    $linux_kernel_source_dir/scripts/config --enable CONFIG_VIRTUALIZATION
    $linux_kernel_source_dir/scripts/config --enable CONFIG_KVM
    $linux_kernel_source_dir/scripts/config --enable CONFIG_KVM_INTEL   # Enable if your host is Intel
    $linux_kernel_source_dir/scripts/config --enable CONFIG_KVM_AMD     # Enable if your host is AMD

    # 2. Enable Core VirtIO Infrastructure (Crucial for VM-to-VM efficiency)
    $linux_kernel_source_dir/scripts/config --enable CONFIG_VIRTIO
    $linux_kernel_source_dir/scripts/config --enable CONFIG_VIRTIO_MENU
    $linux_kernel_source_dir/scripts/config --enable CONFIG_VIRTIO_PCI
    $linux_kernel_source_dir/scripts/config --enable CONFIG_VIRTIO_BALLOON
