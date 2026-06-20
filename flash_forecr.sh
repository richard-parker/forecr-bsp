#!/bin/bash
set -e

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
L4T="$REAL_HOME/nvidia/nvidia_sdk/JetPack_6.2.2_Linux_JETSON_ORIN_NX_TARGETS/Linux_for_Tegra"

# Restart NetworkManager on exit (success or failure)
cleanup() {
    echo ""
    echo "Restarting NetworkManager..."
    systemctl start NetworkManager
    echo "Done."
}
trap cleanup EXIT

echo "Checking recovery mode..."
if ! lsusb | grep -q "0955:7323"; then
    echo "ERROR: Jetson Orin NX 16GB not found in recovery mode (0955:7323)."
    echo "Put the board into recovery mode first, then re-run this script."
    lsusb | grep -i nvidia || echo "(No NVIDIA USB device detected at all)"
    exit 1
fi
echo "Board found in recovery mode (0955:7323)."

# Stop NetworkManager so it doesn't grab the USB ethernet interface
# and break the IPv6 link-local address the flash tool needs.
# The existing wired connection is maintained by the kernel while NM is stopped.
echo "Stopping NetworkManager (will restart automatically when flash completes)..."
systemctl stop NetworkManager
sleep 2

echo "Starting flash..."
cd "$L4T"
./tools/kernel_flash/l4t_initrd_flash.sh --external-device nvme0n1p1 -c tools/kernel_flash/flash_l4t_external.xml -p "-c bootloader/generic/cfg/flash_t234_qspi.xml" --showlogs --network usb0:192.168.55.2/24:192.168.55.1 jetson-orin-nano-devkit internal
