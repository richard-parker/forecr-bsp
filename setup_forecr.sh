#!/bin/bash
set -e

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
TARGET_PARENT="$REAL_HOME/nvidia/nvidia_sdk/JetPack_6.2.2_Linux_JETSON_ORIN_NX_TARGETS"
L4T="$TARGET_PARENT/Linux_for_Tegra"

if [ "$(whoami)" != "root" ]; then
    echo "ERROR: Run this script with sudo: sudo bash $0"
    exit 1
fi

echo "========================================"
echo " Forecr DSBOX-ORNX BSP Setup"
echo " JetPack 6.2.2 + Orin NX 16GB"
echo "========================================"

# Step 1: Flash prerequisites
echo ""
echo "[1/4] Running l4t_flash_prerequisites.sh..."
cd "$L4T"
./tools/l4t_flash_prerequisites.sh

# Step 2: Apply binaries (rootfs overlay)
echo ""
echo "[2/4] Running apply_binaries.sh..."
./apply_binaries.sh

# Step 3: Apply Forecr BSP (custom DTBs, kernel, pinmux, ODMDATA patches)
echo ""
echo "[3/4] Applying Forecr BSP (replace_bsp_files.sh)..."
cd "$TARGET_PARENT"
./replace_bsp_files.sh

# Step 4: Pre-create default user (skips Ubuntu first-boot wizard)
echo ""
echo "[4/4] Creating default user (username: jetson, password: jetson)..."
cd "$L4T"
./tools/l4t_create_default_user.sh -u jetson -p jetson -a -n jetson-ornx --accept-license

echo ""
echo "========================================"
echo " Setup complete. Board is ready to flash."
echo ""
echo " Make sure the board is in recovery mode:"
echo "   lsusb | grep 0955:7323"
echo ""
echo " Then flash with:"
echo "   cd $L4T"
echo "   sudo ./tools/kernel_flash/l4t_initrd_flash.sh \\"
echo "     --external-device nvme0n1p1 \\"
echo "     -c tools/kernel_flash/flash_l4t_external.xml \\"
echo "     -p \"-c bootloader/generic/cfg/flash_t234_qspi.xml\" \\"
echo "     --showlogs --network usb0:192.168.55.2/24:192.168.55.1 \\"
echo "     jetson-orin-nano-devkit internal"
echo "========================================"
