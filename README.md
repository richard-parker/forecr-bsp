# Forecr DSBOX-ORNX Flash Guide

Flashes a Forecr DSBOX-ORNX (Jetson Orin NX 16GB) with JetPack 6.2.2.

## Prerequisites

- Board connected via USB to this host
- Monitor and keyboard connected to the board (for first boot)
- Ethernet cable connected to the board's LAN port

## Scripts

| Script | Purpose |
|---|---|
| `flash_forecr.sh` | Main flash script — runs the JetPack flash |
| `setup_docker_rootfs.sh` | Pre-installs Docker into the rootfs before flashing |

---

## First-time setup (or after rootfs changes)

Before flashing for the first time, or after changing rootfs configuration, run:

```bash
sudo bash setup_docker_rootfs.sh
```

---

## Flashing

### 1. Put the board into recovery mode

Hold the **Recovery** button on the board, then press and release **Reset** (or power cycle).
Confirm the board is in recovery mode:

```bash
lsusb | grep "0955:7323"
```

You should see a line with `0955:7323`. If not, retry recovery mode.

### 2. Run the flash script

```bash
sudo bash flash_forecr.sh
```

This takes approximately 10–15 minutes. The script will:
- Stop NetworkManager to prevent USB interface conflicts
- Flash QSPI bootloader and NVMe rootfs via USB RNDIS over IPv4 (`192.168.55.x`)
- Restart NetworkManager on exit (success or failure)

### 3. First boot

The board will reboot automatically after flashing. It boots directly to the Ubuntu desktop — no setup wizard runs.

**Login credentials:**
- Username: `jetson`
- Password: `jetson`

---

## Post-flash network setup

The Realtek NIC (`enP8p1s0`) requires a NetworkManager connection profile to be created once after each flash. SSH is pre-enabled, but you need a network connection first.

Connect a monitor and keyboard, log in, then press **Ctrl+Alt+F2** for a text console and run:

```bash
sudo nmcli con add type ethernet ifname enP8p1s0 con-name "wired-dhcp" \
    ipv4.method auto ipv6.method ignore autoconnect yes
sudo nmcli con up "wired-dhcp"
ip a show enP8p1s0
```

Note the IP address — you can SSH from this point on:

```bash
ssh jetson@<ip-address>
```

---

## Docker

Docker CE is pre-installed in the rootfs and starts automatically on boot.

Docker is configured with:
- Bridge networking disabled (kernel `bridge.ko` module has a symbol mismatch on this board)
- IPv6 disabled
- iptables disabled

**Available network modes:**

```bash
# Host networking (simplest — container shares host network):
docker run --network=host <image>

# macvlan (container gets its own LAN IP — create once after flash):
docker network create -d macvlan \
    --subnet=10.1.0.0/20 \
    --gateway=10.1.0.1 \
    -o parent=enP8p1s0 local_net

docker run --network=local_net --ip=10.1.11.100 <image>
```

> **Note:** The `local_net` macvlan network must be recreated after each flash.
> Adjust the `--ip` address to one that is free on your network.

---

## Skipping rootfs rebuild

The flash script rebuilds `boot0.img` (the recovery initrd) if any of the initrd scripts have changed. To force-skip this rebuild:

```bash
touch ~/nvidia/nvidia_sdk/JetPack_6.2.2_Linux_JETSON_ORIN_NX_TARGETS/Linux_for_Tegra/bootloader/boot0.img
```

---

## Known issues

| Issue | Cause | Status |
|---|---|---|
| `bridge.ko` fails to load | `ipv6.ko` has symbol CRC mismatch against running kernel (`__skb_flow_dissect`) | Workaround: Docker uses `"bridge": "none"` |
| Container-to-container networking limited | No bridge networking | Use `--network=host` or macvlan |
| Network interface not up after flash | NM connection profile not created | Run `nmcli con add ...` after each flash (see above) |
| GRUB menu not accessible | No `/etc/default/grub` on this board | Use UEFI 5-second timeout to interrupt boot |
