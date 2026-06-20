#!/bin/bash
# Flash a Forecr DSBOX-ORNX (Jetson Orin NX 16GB) end-to-end.
# Downloads JetPack via SDK Manager and the Forecr BSP, applies all
# customisations, and flashes the board over USB.
#
# Usage:
#   sudo bash flash_board.sh [options]
#
# Options:
#   --nvidia-user <email>    NVIDIA developer account email (developer.nvidia.com)
#   --nvidia-pass <pass>     NVIDIA developer account password
#   --sudo-pass  <pass>      Host sudo password (needed by SDK Manager)
#   --bsp-url    <url>       Direct download URL for the Forecr BSP tarball
#   --bsp        <path>      Local path to the Forecr BSP tarball (skips download)
#   --user       <username>  Username to create on the board (default: jetson)
#   --pass       <password>  Password for that user       (default: jetson)
#   --host       <hostname>  Hostname to set on the board (default: jetson-ornx)
#   --docker                 Pre-install Docker CE into the rootfs before flashing
#   --l4t        <path>      Path to Linux_for_Tegra (skips SDK Manager if set)
#
# Any omitted credentials will be prompted for interactively.

set -euo pipefail

# ─── Colour output ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()   { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()     { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()   { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()    { echo -e "${RED}[FAIL]${NC}  $*" >&2; exit 1; }
banner() { echo -e "\n${CYAN}════════════════════════════════════════${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}════════════════════════════════════════${NC}"; }
prompt() {
    # prompt <variable_name> <display_text> [secret]
    local var="$1" text="$2" secret="${3:-}"
    if [[ -n "${!var:-}" ]]; then return; fi   # already set via argument
    if [[ -n "$secret" ]]; then
        read -rsp "  $text: " "$var"; echo
    else
        read -rp  "  $text: " "$var"
    fi
}

# ─── Root check ───────────────────────────────────────────────────────────────
[[ "$(id -u)" -eq 0 ]] || die "Run with sudo: sudo bash $0 $*"

# Real (non-root) user who invoked sudo — SDK Manager must run as them
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
[[ -n "$REAL_HOME" ]] || die "Could not determine home directory for user '$REAL_USER'"

# ─── Defaults ─────────────────────────────────────────────────────────────────
NVIDIA_USER=""
NVIDIA_PASS=""
SUDO_PASS=""
BSP_URL=""
BSP_LOCAL=""
BOARD_USER="jetson"
BOARD_PASS="jetson"
BOARD_HOST="jetson-ornx"
INSTALL_DOCKER=false
L4T_OVERRIDE=""

# ─── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --nvidia-user) NVIDIA_USER="$2"; shift 2 ;;
        --nvidia-pass) NVIDIA_PASS="$2"; shift 2 ;;
        --sudo-pass)   SUDO_PASS="$2";   shift 2 ;;
        --bsp-url)     BSP_URL="$2";     shift 2 ;;
        --bsp)         BSP_LOCAL="$2";   shift 2 ;;
        --user)        BOARD_USER="$2";  shift 2 ;;
        --pass)        BOARD_PASS="$2";  shift 2 ;;
        --host)        BOARD_HOST="$2";  shift 2 ;;
        --docker)      INSTALL_DOCKER=true; shift ;;
        --l4t)         L4T_OVERRIDE="$2"; shift 2 ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) die "Unknown argument: $1  (run with --help)" ;;
    esac
done

# ─── Temp dir (cleaned up on exit) ───────────────────────────────────────────
WORK_DIR="$(mktemp -d /tmp/forecr_flash_XXXXXX)"
chown "$REAL_USER" "$WORK_DIR"
trap 'rm -rf "$WORK_DIR"' EXIT

# ═════════════════════════════════════════════════════════════════════════════
banner "Step 1/8 — Install JetPack 6.2.2 via SDK Manager"
# ═════════════════════════════════════════════════════════════════════════════

find_l4t() {
    [[ -n "$L4T_OVERRIDE" ]] && { echo "$L4T_OVERRIDE"; return; }
    find "$REAL_HOME/nvidia/nvidia_sdk" \
        -maxdepth 4 -name "Linux_for_Tegra" -type d \
        2>/dev/null | grep -i "orin_nx" | sort | tail -1 || true
}

L4T=$(find_l4t)

if [[ -n "$L4T" && -f "$L4T/apply_binaries.sh" ]]; then
    ok "JetPack already installed at: $L4T"
    ok "Skipping SDK Manager download."
else
    # Check sdkmanager is available
    command -v sdkmanager &>/dev/null || \
        die "sdkmanager not found.\nInstall it from: https://developer.nvidia.com/sdk-manager\n  sudo apt install ./sdkmanager_*.deb"

    echo ""
    echo "  SDK Manager will log in with your NVIDIA developer account"
    echo "  (developer.nvidia.com) to download JetPack 6.2.2."
    echo "  This download is ~10 GB and takes 20–40 minutes."
    echo ""

    prompt NVIDIA_USER "NVIDIA developer account email"
    prompt NVIDIA_PASS "NVIDIA developer account password" secret
    prompt SUDO_PASS   "Host sudo password (for SDK Manager)" secret

    # Write response file as the real user
    RESPONSE_FILE="$WORK_DIR/sdkm_jetson.ini"
    cat > "$RESPONSE_FILE" << EOF
[client_arguments]
action = install
login-type = devzone
product = Jetson
version = 6.2.2
target-os = Linux
host = true
target = JETSON_ORIN_NX_TARGETS
license = accept
deselect[] = Jetson SDK Components
sudo-password = ${SUDO_PASS}

[pre-flash-settings]
recovery = manual

[post-flash-settings]
post-flash = skip
EOF
    chmod 600 "$RESPONSE_FILE"
    chown "$REAL_USER" "$RESPONSE_FILE"

    info "Running SDK Manager (this takes 20–40 minutes)..."
    sudo -u "$REAL_USER" sdkmanager \
        --cli \
        --user  "$NVIDIA_USER" \
        --password "$NVIDIA_PASS" \
        --response-file "$RESPONSE_FILE" \
        --exit-on-finish

    # Scrub credentials from response file now that we're done with it
    rm -f "$RESPONSE_FILE"

    L4T=$(find_l4t)
    [[ -n "$L4T" && -f "$L4T/apply_binaries.sh" ]] || \
        die "SDK Manager completed but Linux_for_Tegra was not found.\nCheck the SDK Manager logs in $REAL_HOME/nvidia/nvidia_sdk/"
    ok "JetPack installed at: $L4T"
fi

L4T_PARENT="$(dirname "$L4T")"
ROOTFS="$L4T/rootfs"

# ═════════════════════════════════════════════════════════════════════════════
banner "Step 2/8 — Download and Extract Forecr BSP"
# ═════════════════════════════════════════════════════════════════════════════

BSP_TARBALL=""

# 1. Use --bsp local path if provided
if [[ -n "$BSP_LOCAL" ]]; then
    [[ -f "$BSP_LOCAL" ]] || die "Local BSP file not found: $BSP_LOCAL"
    BSP_TARBALL="$BSP_LOCAL"
    ok "Using local BSP: $BSP_TARBALL"

# 2. Look for it next to the script or one level up
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    for candidate in \
        "$SCRIPT_DIR/dsboard_ornx_orin_nx_JP6_2_2_bsp.tar.xz" \
        "$SCRIPT_DIR/../dsboard_ornx_orin_nx_JP6_2_2_bsp.tar.xz" \
        "$SCRIPT_DIR/../dsboard_ornx_orin_nx_JP6_2_2_bsp_real.tar.xz"
    do
        if [[ -f "$candidate" ]]; then
            BSP_TARBALL="$(realpath "$candidate")"
            ok "Found local BSP: $BSP_TARBALL"
            break
        fi
    done
fi

# 3. Download from URL if still not found
if [[ -z "$BSP_TARBALL" ]]; then
    if [[ -z "$BSP_URL" ]]; then
        echo ""
        echo "  The Forecr BSP package was not found locally."
        echo "  Download it from the DSBOX-ORNX product page on forecr.io"
        echo "  and paste the direct download URL below."
        echo ""
        prompt BSP_URL "Forecr BSP direct download URL"
    fi

    BSP_DEST="$WORK_DIR/forecr_bsp.tar.xz"
    info "Downloading Forecr BSP..."
    if command -v curl &>/dev/null; then
        sudo -u "$REAL_USER" curl -L --progress-bar -o "$BSP_DEST" "$BSP_URL"
    else
        sudo -u "$REAL_USER" wget -q --show-progress -O "$BSP_DEST" "$BSP_URL"
    fi
    [[ -f "$BSP_DEST" && -s "$BSP_DEST" ]] || die "BSP download failed or file is empty."
    BSP_TARBALL="$BSP_DEST"
    ok "BSP downloaded."
fi

BSP_WORK="$WORK_DIR/bsp_extracted"
mkdir -p "$BSP_WORK"
info "Extracting BSP..."
tar -xf "$BSP_TARBALL" -C "$BSP_WORK" --strip-components=1
ok "BSP extracted."

for f in Image kernel_supplements.tbz2 \
          tegra234-p3768-0000+p3767-0000-nv.dtb \
          tegra234-mb1-bct-pinmux-p3767-dp-a03.dtsi \
          tegra234-mb1-bct-gpio-p3767-dp-a03.dtsi; do
    [[ -f "$BSP_WORK/$f" ]] || die "Expected file missing from BSP archive: $f"
done
ok "BSP contents verified."

# ═════════════════════════════════════════════════════════════════════════════
banner "Step 3/8 — Apply L4T Binaries"
# ═════════════════════════════════════════════════════════════════════════════

info "Running l4t_flash_prerequisites.sh..."
cd "$L4T"
./tools/l4t_flash_prerequisites.sh

info "Running apply_binaries.sh..."
./apply_binaries.sh
ok "L4T binaries applied."

# ═════════════════════════════════════════════════════════════════════════════
banner "Step 4/8 — Install Forecr BSP Files"
# ═════════════════════════════════════════════════════════════════════════════

cd "$BSP_WORK"

info "Copying kernel image..."
cp Image "$L4T/kernel/Image"

info "Copying kernel modules..."
cp kernel_supplements.tbz2 "$L4T/kernel/"

info "Copying device tree binaries..."
for dtb in \
    tegra234-p3768-0000+p3767-0000-nv.dtb \
    tegra234-p3768-0000+p3767-0000-nv-super.dtb \
    tegra234-p3768-0000+p3767-0001-nv.dtb \
    tegra234-p3768-0000+p3767-0001-nv-super.dtb; do
    [[ -f "$dtb" ]] && cp "$dtb" "$L4T/kernel/dtb/"
done

info "Copying camera overlays..."
for dtbo in \
    tegra234-p3767-camera-dsboard-ornx-imx219.dtbo \
    tegra234-p3767-camera-dsboard-ornx-imx477.dtbo; do
    if [[ -f "$dtbo" ]]; then
        cp "$dtbo" "$L4T/kernel/dtb/"
        cp "$dtbo" "$ROOTFS/boot/"
    fi
done

info "Copying pinmux and GPIO configs..."
cp tegra234-mb1-bct-pinmux-p3767-dp-a03.dtsi "$L4T/bootloader/generic/BCT/"
cp tegra234-mb1-bct-gpio-p3767-dp-a03.dtsi   "$L4T/bootloader/"

info "Extracting kernel modules into rootfs..."
cd "$ROOTFS"
tar -jxf "$L4T/kernel/kernel_supplements.tbz2"
sync

ok "BSP files installed."

# ═════════════════════════════════════════════════════════════════════════════
banner "Step 5/8 — Apply Board Config Patches"
# ═════════════════════════════════════════════════════════════════════════════

# Patch 1: Disable CVB EEPROM read (board has no EEPROM at that address)
MISC_BCT="$L4T/bootloader/generic/BCT/tegra234-mb2-bct-misc-p3767-0000.dts"
if grep -q 'cvb_eeprom_read_size = <0x100>' "$MISC_BCT" 2>/dev/null; then
    sed -i 's/cvb_eeprom_read_size = <0x100>;/cvb_eeprom_read_size = <0x0>;/' "$MISC_BCT"
    ok "Patch 1: CVB EEPROM read disabled."
elif grep -q 'cvb_eeprom_read_size = <0x0>' "$MISC_BCT" 2>/dev/null; then
    ok "Patch 1: CVB EEPROM already patched — skipping."
else
    warn "Patch 1: cvb_eeprom_read_size not found in $MISC_BCT — skipping."
fi

# Patch 2: Switch ODMDATA config-8 → config-9 (enables Realtek NIC)
P3767_CONF="$L4T/p3767.conf.common"
if grep -q 'gbe-uphy-config-8' "$P3767_CONF" 2>/dev/null; then
    sed -i 's/gbe-uphy-config-8/gbe-uphy-config-9/' "$P3767_CONF"
    ok "Patch 2: ODMDATA set to gbe-uphy-config-9 (Realtek NIC)."
elif grep -q 'gbe-uphy-config-9' "$P3767_CONF" 2>/dev/null; then
    ok "Patch 2: ODMDATA already set to config-9 — skipping."
else
    warn "Patch 2: gbe-uphy-config-8 not found in $P3767_CONF — skipping."
fi

# Patch 3: Add HDMI DCE overlay
BOARD_CONF="$L4T/p3768-0000-p3767-0000-a0.conf"
if grep -q 'tegra234-dcb-p3767-0000-hdmi.dtbo' "$BOARD_CONF" 2>/dev/null; then
    ok "Patch 3: HDMI DCE overlay already present — skipping."
elif [[ -f "$BOARD_CONF" ]]; then
    sed -i \
        's|OVERLAY_DTB_FILE+=\",tegra234-p3768-0000+p3767-0000-dynamic.dtbo\";|OVERLAY_DTB_FILE+=",tegra234-p3768-0000+p3767-0000-dynamic.dtbo,tegra234-dcb-p3767-0000-hdmi.dtbo";\nDCE_OVERLAY_DTB_FILE="tegra234-dcb-p3767-0000-hdmi.dtbo";|' \
        "$BOARD_CONF"
    ok "Patch 3: HDMI DCE overlay added."
else
    warn "Patch 3: $BOARD_CONF not found — skipping."
fi

# ═════════════════════════════════════════════════════════════════════════════
banner "Step 6/8 — Create Default User"
# ═════════════════════════════════════════════════════════════════════════════

info "Creating user '$BOARD_USER' with hostname '$BOARD_HOST'..."
cd "$L4T"
./tools/l4t_create_default_user.sh \
    -u "$BOARD_USER" \
    -p "$BOARD_PASS" \
    -a \
    -n "$BOARD_HOST" \
    --accept-license
ok "User '$BOARD_USER' created."

# ═════════════════════════════════════════════════════════════════════════════
if [[ "$INSTALL_DOCKER" == true ]]; then
banner "Step 7/8 — Pre-install Docker CE"

command -v qemu-aarch64-static &>/dev/null || \
    die "qemu-user-static not installed. Run: sudo apt install qemu-user-static"

info "Preparing chroot environment..."
cp /usr/bin/qemu-aarch64-static "$ROOTFS/usr/bin/"
cp /etc/resolv.conf "$ROOTFS/etc/resolv.conf"

mount --bind /proc    "$ROOTFS/proc"
mount --bind /sys     "$ROOTFS/sys"
mount --bind /dev     "$ROOTFS/dev"
mount --bind /dev/pts "$ROOTFS/dev/pts"

docker_cleanup() {
    umount "$ROOTFS/dev/pts" 2>/dev/null || true
    umount "$ROOTFS/dev"     2>/dev/null || true
    umount "$ROOTFS/sys"     2>/dev/null || true
    umount "$ROOTFS/proc"    2>/dev/null || true
    rm -f  "$ROOTFS/usr/bin/qemu-aarch64-static"
    rm -rf "$WORK_DIR"
}
trap docker_cleanup EXIT

# Fix any placeholder SOC repo entries left by SDK Manager
find "$ROOTFS/etc/apt/sources.list.d/" -type f \
    | xargs grep -l '<SOC>' 2>/dev/null \
    | while read -r f; do
        sed -i 's|/jetson/<SOC>|/jetson/t234|g' "$f"
    done

info "Installing Docker CE inside chroot (takes a few minutes)..."
chroot "$ROOTFS" /bin/bash << CHROOT
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo 'deb [arch=arm64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu jammy stable' \
    > /etc/apt/sources.list.d/docker.list
apt-get update -q
apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
usermod -aG docker "${BOARD_USER}"
systemctl enable docker
CHROOT

info "Writing Docker daemon config..."
mkdir -p "$ROOTFS/etc/docker"
cat > "$ROOTFS/etc/docker/daemon.json" << 'EOF'
{
  "ipv6": false,
  "ip6tables": false,
  "bridge": "none",
  "iptables": false
}
EOF
echo 'net.ipv4.ip_forward=1' > "$ROOTFS/etc/sysctl.d/99-docker.conf"

docker_cleanup
trap 'rm -rf "$WORK_DIR"' EXIT
ok "Docker CE pre-installed."

else
banner "Step 7/8 — Docker (skipped)"
info "Pass --docker to pre-install Docker CE into the rootfs."
fi

# ═════════════════════════════════════════════════════════════════════════════
banner "Step 8/8 — Flash the Board"
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo "  Put the board into recovery mode now:"
echo "    1. Hold the Recovery button"
echo "    2. Press and release Reset (or power cycle while holding Recovery)"
echo ""

WAIT_SECS=120
INTERVAL=2
ELAPSED=0
printf "  Waiting for board (USB 0955:7323) "
while ! lsusb | grep -q "0955:7323"; do
    if [[ $ELAPSED -ge $WAIT_SECS ]]; then
        echo ""
        die "Board not detected after ${WAIT_SECS}s. Check USB cable and retry recovery mode."
    fi
    printf "."
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done
echo ""
ok "Board detected in recovery mode."

# ── UFW: disable if active (blocks IPv6 link-local used by flash tool) ────────
UFW_WAS_ACTIVE=false
if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
    warn "UFW is active — disabling it for the duration of the flash."
    warn "(It will be re-enabled automatically when the script exits.)"
    ufw disable
    UFW_WAS_ACTIVE=true
fi

# ── IPv6: must be enabled — flash tool uses fe80:: link-local to reach board ──
if [[ "$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null)" == "1" ]]; then
    warn "IPv6 is disabled system-wide — enabling it for the flash."
    sysctl -w net.ipv6.conf.all.disable_ipv6=0
    sysctl -w net.ipv6.conf.default.disable_ipv6=0
fi

# ── NetworkManager: stop so it doesn't grab the USB RNDIS interface ───────────
info "Stopping NetworkManager to prevent USB interface conflicts..."
NM_WAS_RUNNING=false
if systemctl is-active --quiet NetworkManager; then
    NM_WAS_RUNNING=true
    systemctl stop NetworkManager
fi

pre_flash_cleanup() {
    if [[ "$NM_WAS_RUNNING" == true ]]; then
        info "Restarting NetworkManager..."
        systemctl start NetworkManager
    fi
    if [[ "$UFW_WAS_ACTIVE" == true ]]; then
        info "Re-enabling UFW..."
        ufw enable
    fi
    rm -rf "$WORK_DIR"
}
trap pre_flash_cleanup EXIT

info "Flashing — this takes 10–15 minutes..."
cd "$L4T"
./tools/kernel_flash/l4t_initrd_flash.sh \
    --external-device nvme0n1p1 \
    -c tools/kernel_flash/flash_l4t_external.xml \
    -p "-c bootloader/generic/cfg/flash_t234_qspi.xml" \
    --showlogs \
    --network usb0:192.168.55.2/24:192.168.55.1 \
    jetson-orin-nano-devkit internal

echo ""
ok "Flash complete. The board will reboot automatically."
echo ""
echo -e "${CYAN}Post-flash steps (on the board):${NC}"
echo "  Log in as '${BOARD_USER}' / '${BOARD_PASS}', press Ctrl+Alt+F2, then run:"
echo ""
echo "    sudo nmcli con add type ethernet ifname enP8p1s0 con-name \"wired-dhcp\" \\"
echo "        ipv4.method auto ipv6.method ignore autoconnect yes"
echo "    sudo nmcli con up \"wired-dhcp\""
echo "    ip a show enP8p1s0"
echo ""
echo "  Then SSH in from this machine: ssh ${BOARD_USER}@<ip-address>"
echo ""
if [[ "$INSTALL_DOCKER" == true ]]; then
    echo -e "${CYAN}Docker networking (bridge disabled on this board):${NC}"
    echo "  docker run --network=host <image>"
    echo "  -- or create a macvlan once after flash --"
    echo "  docker network create -d macvlan --subnet=10.1.0.0/20 --gateway=10.1.0.1 -o parent=enP8p1s0 local_net"
    echo ""
fi
