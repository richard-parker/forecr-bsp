# Forecr DSBOX-ORNX: From-Scratch Flash Guide

Covers everything needed to go from a bare Ubuntu host to a flashed Jetson Orin NX 16GB on the Forecr DSBOX-ORNX carrier board, without using the helper scripts in this repo.

**Hardware:** Jetson Orin NX 16GB (P3767) + Forecr DSBOX-ORNX carrier board  
**Software:** JetPack 6.2.2 / L4T, Ubuntu 22.04 (Jammy) rootfs

---

## Prerequisites

- Ubuntu x86_64 host machine (22.04 recommended)
- USB cable from host to the board's recovery USB port
- NVMe SSD installed in the board
- Monitor and keyboard connected to the board (for first boot only)
- Ethernet cable connected to the board's LAN port

---

## Step 1 — Install NVIDIA SDK Manager

Download SDK Manager from [developer.nvidia.com/sdk-manager](https://developer.nvidia.com/sdk-manager) and install it:

```bash
sudo apt install ./sdkmanager_*.deb
```

You need a free NVIDIA developer account (developer.nvidia.com) to download JetPack.

### Option A — Headless (CLI)

SDK Manager can run without a GUI using a response file. Create a file called `jetson.ini`:

```ini
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
sudo-password = <your-sudo-password>

[pre-flash-settings]
recovery = manual

[post-flash-settings]
post-flash = skip
```

Then run:

```bash
sdkmanager --cli \
    --user your@email.com \
    --password "yourpassword" \
    --response-file jetson.ini \
    --exit-on-finish
```

> **Note:** Do not run `sdkmanager` as root. Run it as your normal user — it will use `sudo` internally when needed (hence `sudo-password` in the response file).
> Delete `jetson.ini` after the download completes as it contains plaintext credentials.

### Option B — GUI

Run `sdkmanager` and select:
- **Product:** Jetson
- **Hardware:** Jetson Orin NX
- **JetPack version:** 6.2.2
- Install **host components** and **target components** (rootfs + L4T tools)
- When asked about flashing, choose **skip**

Either option downloads everything to:
```
~/nvidia/nvidia_sdk/JetPack_6.2.2_Linux_JETSON_ORIN_NX_TARGETS/Linux_for_Tegra/
```

The download is approximately 10 GB and takes 20–40 minutes.

---

## Step 2 — Download and Extract the Forecr BSP

Go to [forecr.io](https://forecr.io), find the DSBOX-ORNX product page, and copy the direct download URL for the **JetPack 6.2.2 BSP**.

The BSP files must land **directly inside the JetPack directory** (alongside `Linux_for_Tegra`), not in a subdirectory. `replace_bsp_files.sh` uses relative paths and will silently do nothing if run from the wrong location.

```bash
curl -L -o forecr_bsp.tar.xz "<paste-url-here>"

tar -xf forecr_bsp.tar.xz --strip-components=1 \
    -C ~/nvidia/nvidia_sdk/JetPack_6.2.2_Linux_JETSON_ORIN_NX_TARGETS/
```

Verify the files are in the right place:

```bash
ls ~/nvidia/nvidia_sdk/JetPack_6.2.2_Linux_JETSON_ORIN_NX_TARGETS/Image
ls ~/nvidia/nvidia_sdk/JetPack_6.2.2_Linux_JETSON_ORIN_NX_TARGETS/replace_bsp_files.sh
```

Both must exist before continuing. You should also see:

```
Image                                               # custom kernel
kernel_supplements.tbz2                            # kernel modules and drivers
tegra234-p3768-0000+p3767-0000-nv.dtb              # device trees (4 files)
tegra234-p3768-0000+p3767-0000-nv-super.dtb
tegra234-p3768-0000+p3767-0001-nv.dtb
tegra234-p3768-0000+p3767-0001-nv-super.dtb
tegra234-p3767-camera-dsboard-ornx-imx219.dtbo     # camera overlays
tegra234-p3767-camera-dsboard-ornx-imx477.dtbo
tegra234-mb1-bct-pinmux-p3767-dp-a03.dtsi          # pinmux config
tegra234-mb1-bct-gpio-p3767-dp-a03.dtsi            # GPIO config
replace_bsp_files.sh                               # Forecr copy script
rtc_config_tool.sh                                 # RTC utility
```

---

## Step 3 — Apply L4T Prerequisites and Rootfs Binaries

```bash
cd ~/nvidia/nvidia_sdk/JetPack_6.2.2_Linux_JETSON_ORIN_NX_TARGETS/Linux_for_Tegra
sudo ./tools/l4t_flash_prerequisites.sh
sudo ./apply_binaries.sh
```

> `apply_binaries.sh` overlays NVIDIA's compiled libraries and drivers into the rootfs. This must be done before copying Forecr files.

---

## Step 4 — Apply Forecr BSP Files into L4T

Run Forecr's copy script from the JetPack directory, where the BSP files were extracted in Step 2:

```bash
cd ~/nvidia/nvidia_sdk/JetPack_6.2.2_Linux_JETSON_ORIN_NX_TARGETS
sudo bash replace_bsp_files.sh
```

> **Important:** The script must be run from this directory — not from a subdirectory. It uses relative paths like `Linux_for_Tegra/kernel/Image` and will fail silently (printing "Done." regardless) if the source files are not in the current working directory.

### What this script does

**Copies files into L4T:**

| File | Destination |
|---|---|
| `Image` | `Linux_for_Tegra/kernel/Image` |
| `kernel_supplements.tbz2` | `Linux_for_Tegra/kernel/` (then extracted into rootfs) |
| 4× `.dtb` files | `Linux_for_Tegra/kernel/dtb/` |
| 2× `.dtbo` camera overlays | `Linux_for_Tegra/kernel/dtb/` and `rootfs/boot/` |
| `tegra234-mb1-bct-pinmux-*.dtsi` | `Linux_for_Tegra/bootloader/generic/BCT/` |
| `tegra234-mb1-bct-gpio-*.dtsi` | `Linux_for_Tegra/bootloader/` |

**Patches three config files:**

1. **Disables CVB EEPROM read** — the board has no EEPROM at the default address:
   ```
   File:   bootloader/generic/BCT/tegra234-mb2-bct-misc-p3767-0000.dts
   Change: cvb_eeprom_read_size = <0x100>  →  cvb_eeprom_read_size = <0x0>
   ```

2. **Enables the Realtek NIC** — changes USB/PHY routing so the NIC is reachable:
   ```
   File:   Linux_for_Tegra/p3767.conf.common
   Change: gbe-uphy-config-8  →  gbe-uphy-config-9
   ```

3. **Adds HDMI DCE overlay** — enables HDMI output:
   ```
   File:   Linux_for_Tegra/p3768-0000-p3767-0000-a0.conf
   Adds:   ,tegra234-dcb-p3767-0000-hdmi.dtbo  to OVERLAY_DTB_FILE
   Adds:   DCE_OVERLAY_DTB_FILE="tegra234-dcb-p3767-0000-hdmi.dtbo"
   ```

---

## Step 5 — Create a Default User

This pre-creates a user so the Ubuntu first-boot setup wizard is skipped:

```bash
cd ~/nvidia/nvidia_sdk/JetPack_6.2.2_Linux_JETSON_ORIN_NX_TARGETS/Linux_for_Tegra
sudo ./tools/l4t_create_default_user.sh -u <username> -p <password> -a -n <hostname> --accept-license
```

Replace `<username>`, `<password>`, and `<hostname>` with your own values. The `-a` flag grants the user sudo.

---

## Step 6 — (Optional) Pre-install Docker into the Rootfs

This installs Docker CE before flashing so it is ready on first boot. Skip this step if you do not need Docker.

Install the required host dependency:

```bash
sudo apt install qemu-user-static
```

Set a variable for convenience:

```bash
ROOTFS=~/nvidia/nvidia_sdk/JetPack_6.2.2_Linux_JETSON_ORIN_NX_TARGETS/Linux_for_Tegra/rootfs
```

Chroot into the ARM64 rootfs and install Docker CE:

```bash
cp /usr/bin/qemu-aarch64-static $ROOTFS/usr/bin/
cp /etc/resolv.conf $ROOTFS/etc/resolv.conf

mount --bind /proc    $ROOTFS/proc
mount --bind /sys     $ROOTFS/sys
mount --bind /dev     $ROOTFS/dev
mount --bind /dev/pts $ROOTFS/dev/pts

chroot $ROOTFS /bin/bash << 'EOF'
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
echo 'deb [arch=arm64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu jammy stable' \
    > /etc/apt/sources.list.d/docker.list
apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
usermod -aG docker <username>
systemctl enable docker
EOF

umount $ROOTFS/dev/pts $ROOTFS/dev $ROOTFS/sys $ROOTFS/proc
rm $ROOTFS/usr/bin/qemu-aarch64-static
```

> Replace `<username>` with the username you created in Step 5.

Write Docker's daemon config. Bridge networking must be disabled — the `bridge.ko` kernel module fails to load on this board due to a symbol CRC mismatch in `ipv6.ko`:

```bash
mkdir -p $ROOTFS/etc/docker
cat > $ROOTFS/etc/docker/daemon.json << 'EOF'
{
  "ipv6": false,
  "ip6tables": false,
  "bridge": "none",
  "iptables": false
}
EOF

echo 'net.ipv4.ip_forward=1' > $ROOTFS/etc/sysctl.d/99-docker.conf
```

---

## Step 7 — Prepare the Host for Flashing

The flash tool communicates with the board over **IPv6 link-local** during the initrd phase. Two things on the host commonly block this and cause a timeout.

### 7a — Disable UFW (firewall)

```bash
sudo ufw status
```

If it shows `Status: active`, disable it:

```bash
sudo ufw disable
```

> Re-enable it after flashing with `sudo ufw enable` if needed.

### 7b — Confirm IPv6 is enabled

```bash
sysctl net.ipv6.conf.all.disable_ipv6
```

If it returns `1`, re-enable IPv6:

```bash
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=0
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=0
```

### 7c — Stop NetworkManager

NetworkManager will try to claim the USB ethernet interface the moment the board enumerates, which breaks the flash tool's network setup.

```bash
sudo systemctl stop NetworkManager
```

> Start it again after flashing: `sudo systemctl start NetworkManager`

---

## Step 8 — Put the Board into Recovery Mode

If the board is **powered off**: hold **Recovery**, then power it on.
If the board is **already running**: hold **Recovery**, then press and release **Reset**.

Confirm it is detected:

```bash
lsusb | grep "0955:7323"
```

You must see a result before continuing. If nothing appears, repeat the recovery mode steps.

---

## Step 9 — Flash

```bash
cd ~/nvidia/nvidia_sdk/JetPack_6.2.2_Linux_JETSON_ORIN_NX_TARGETS/Linux_for_Tegra

sudo ./tools/kernel_flash/l4t_initrd_flash.sh \
    --external-device nvme0n1p1 \
    -c tools/kernel_flash/flash_l4t_external.xml \
    -p "-c bootloader/generic/cfg/flash_t234_qspi.xml" \
    --showlogs \
    --network usb0:192.168.55.2/24:192.168.55.1 \
    jetson-orin-nano-devkit internal
```

Takes approximately 10–15 minutes. The board reboots automatically when complete.

Once done, restart NetworkManager:

```bash
sudo systemctl start NetworkManager
```

---

## Step 10 — Post-Flash: Enable the Network

The Realtek NIC (`enP8p1s0`) is not automatically configured by NetworkManager after a fresh flash. You must create a connection profile once per flash.

Connect a monitor and keyboard to the board and log in. Press **Ctrl+Alt+F2** for a text console, then run:

```bash
sudo nmcli con add type ethernet ifname enP8p1s0 con-name "wired-dhcp" \
    ipv4.method auto ipv6.method ignore autoconnect yes
sudo nmcli con up "wired-dhcp"
ip a show enP8p1s0
```

Note the IP address shown. You can now SSH from any machine on the network:

```bash
ssh <username>@<ip-address>
```

---

## Docker Networking (if Docker was pre-installed)

Bridge networking is disabled on this board. Use one of these modes instead:

```bash
# Host networking — container shares the host network stack:
docker run --network=host <image>

# macvlan — container gets its own IP on the LAN (create once after each flash):
docker network create -d macvlan \
    --subnet=10.1.0.0/20 \
    --gateway=10.1.0.1 \
    -o parent=enP8p1s0 local_net

docker run --network=local_net --ip=10.1.11.100 <image>
```

> Adjust the subnet, gateway, and IP to match your network. The macvlan network must be recreated after each flash.

---

## Known Issues

| Issue | Cause | Fix |
|---|---|---|
| `bridge.ko` fails to load | `ipv6.ko` has a symbol CRC mismatch against the custom kernel | Set `"bridge": "none"` in `daemon.json` |
| Realtek NIC not up after flash | No NetworkManager profile for `enP8p1s0` | Run `nmcli con add ...` once after each flash |
| GRUB menu not accessible | No `/etc/default/grub` on this board | Use the UEFI 5-second timeout to interrupt boot |
| Flash fails mid-way | NetworkManager grabbed the USB interface | Stop NetworkManager before flashing (Step 7c) |
| `Error: Timeout` / `cannot connect to ssh server` during flash | UFW blocking IPv6 link-local, or IPv6 disabled on the host | Disable UFW (`sudo ufw disable`) and verify IPv6 is enabled (Step 7a/7b) |
| `ping6 fe80::1%<interface>` fails | Same as above, or board didn't enumerate USB RNDIS correctly | Disable UFW, re-enter recovery mode, retry |
