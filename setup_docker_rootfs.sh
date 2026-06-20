#!/bin/bash
set -e

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
ROOTFS="$REAL_HOME/nvidia/nvidia_sdk/JetPack_6.2.2_Linux_JETSON_ORIN_NX_TARGETS/Linux_for_Tegra/rootfs"

echo "=== Installing Docker into ARM64 rootfs ==="

# Copy QEMU into rootfs so ARM64 binaries can run on x86
cp /usr/bin/qemu-aarch64-static "${ROOTFS}/usr/bin/"

# Save existing resolv.conf and use host DNS for internet access
cp "${ROOTFS}/etc/resolv.conf" "${ROOTFS}/etc/resolv.conf.bak" 2>/dev/null || true
cp /etc/resolv.conf "${ROOTFS}/etc/resolv.conf"

# Mount filesystems
mount --bind /proc    "${ROOTFS}/proc"
mount --bind /sys     "${ROOTFS}/sys"
mount --bind /dev     "${ROOTFS}/dev"
mount --bind /dev/pts "${ROOTFS}/dev/pts"

cleanup() {
    echo "Cleaning up..."
    umount "${ROOTFS}/dev/pts" 2>/dev/null || true
    umount "${ROOTFS}/dev"     2>/dev/null || true
    umount "${ROOTFS}/sys"     2>/dev/null || true
    umount "${ROOTFS}/proc"    2>/dev/null || true
    mv "${ROOTFS}/etc/resolv.conf.bak" "${ROOTFS}/etc/resolv.conf" 2>/dev/null || true
    rm -f "${ROOTFS}/usr/bin/qemu-aarch64-static"
    echo "Done."
}
trap cleanup EXIT

echo "--- Fixing broken NVIDIA SOC repo placeholder ---"
find "${ROOTFS}/etc/apt/sources.list.d/" -type f | xargs grep -l '<SOC>' 2>/dev/null | while read f; do
    sed -i 's|/jetson/<SOC>|/jetson/t234|g' "${f}"
    echo "Fixed: ${f}"
done

echo "--- Entering chroot, installing Docker CE ---"
chroot "${ROOTFS}" /bin/bash << 'CHROOT'
set -e
export DEBIAN_FRONTEND=noninteractive

apt-get update -q || apt-get update -q -o Acquire::AllowInsecureRepositories=true
apt-get install -y -q ca-certificates curl

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo 'deb [arch=arm64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu jammy stable' \
    > /etc/apt/sources.list.d/docker.list

apt-get update -q
apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

usermod -aG docker jetson
systemctl enable docker
echo "--- Docker installed inside chroot ---"
CHROOT

echo "--- Writing daemon.json ---"
mkdir -p "${ROOTFS}/etc/docker"
cat > "${ROOTFS}/etc/docker/daemon.json" << 'EOF'
{
  "ipv6": false,
  "ip6tables": false,
  "bridge": "none",
  "iptables": false
}
EOF

echo "--- Enabling IPv4 forwarding ---"
echo 'net.ipv4.ip_forward=1' > "${ROOTFS}/etc/sysctl.d/99-docker.conf"

echo "=== Done. Docker will be pre-installed after next flash. ==="
