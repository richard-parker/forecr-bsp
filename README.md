# Forecr DSBOX-ORNX — JetPack 6.2.2 Flash Guide

One script flashes a **Jetson Orin NX 16GB** on the **Forecr DSBOX-ORNX** carrier board end-to-end: downloads JetPack, applies the Forecr BSP, and flashes over USB. Tested and hardened on Ubuntu 24.04.

---

## Prerequisites

Before you start, make sure you have:

| Requirement | Notes |
|---|---|
| Ubuntu x86_64 host (22.04 or 24.04) | Other distros untested |
| NVIDIA SDK Manager | `sudo apt install ./sdkmanager_*.deb` — download from developer.nvidia.com/sdk-manager |
| NVIDIA developer account | Free — register at developer.nvidia.com |
| Forecr BSP tarball | `dsboard_ornx_orin_nx_JP6_2_2_bsp_real.tar.xz` — from the DSBOX-ORNX product page at forecr.io |
| USB-C cable | Board's **recovery port** → host |
| NVMe SSD | Must be installed in the board before flashing |

> **Note:** If JetPack 6.2.2 is already installed by SDK Manager on this host, the script detects it and skips the download (saves 30–40 minutes). On subsequent flashes it also reuses the pre-built flash images (saves another ~5 minutes).

---

## Step 1 — Put the board into recovery mode

The board must be in **APX recovery mode** before the script starts polling. The correct sequence is:

1. **Power off completely** — disconnect the DC barrel jack
2. **Hold the FORCE RECOVERY button** — keep holding it
3. **Reconnect DC power** — while still holding Recovery
4. **Hold for 2 full seconds**, then release

Confirm it worked:

```bash
lsusb | grep "0955:7323"
```

You must see `NVIDIA Corp. APX`. If nothing shows, retry — the most common mistake is pressing Reset instead of power-cycling from off.

> **USB port:** Use the board's USB-C **OTG/recovery port** connected directly to the host. A regular USB hub may not work.

---

## Step 2 — Run the flash script

Place the Forecr BSP tarball alongside the script (or pass `--bsp <path>`), then:

```bash
sudo bash deploy/flash_board.sh
```

The script will:

1. Detect or download JetPack 6.2.2 via SDK Manager
2. Extract and verify the Forecr BSP
3. Apply L4T binaries to the rootfs
4. Install the custom kernel, DTBs, pinmux and GPIO configs
5. Apply board-specific patches (CVB EEPROM, ODMDATA, HDMI overlay)
6. Create the default user account
7. Flash QSPI bootloader and NVMe rootfs over USB (~10–20 minutes)

When it's done you'll see:

```
[ OK ]  Flash complete. The board will reboot automatically.
```

The board reboots on its own — do not unplug it.

---

## Step 3 — First boot

The board boots straight to the Ubuntu desktop (no setup wizard). Default login:

| | |
|---|---|
| Username | `jetson` |
| Password | `jetson` |

If you don't have a monitor, wait ~90 seconds then continue with the network setup below.

---

## Step 4 — Post-flash network setup

The Realtek NIC (`enP8p1s0`) needs a NetworkManager profile created once after each flash. Connect a monitor and keyboard, log in, and press **Ctrl+Alt+F2** for a text console, then run:

```bash
sudo nmcli con add type ethernet ifname enP8p1s0 con-name "wired-dhcp" \
    ipv4.method auto ipv6.method ignore autoconnect yes
sudo nmcli con up "wired-dhcp"
ip a show enP8p1s0
```

Note the IP address. You can SSH in from the host from this point:

```bash
ssh jetson@<ip-address>
```

---

## Options

```
sudo bash deploy/flash_board.sh [options]

  --bsp <path>       Local path to the Forecr BSP tarball
  --bsp-url <url>    Download URL for the BSP tarball (if not local)
  --l4t <path>       Path to an existing Linux_for_Tegra (skips SDK Manager)
  --user <name>      Board username (default: jetson)
  --pass <pass>      Board password (default: jetson)
  --host <name>      Board hostname (default: jetson-ornx)
  --docker           Pre-install Docker CE into the rootfs before flashing
  --rebuild          Force full rebuild even if flash images already exist
                     (required if you change --user, --pass, --host, or --docker)
  --nvidia-user      NVIDIA account email (prompted if omitted)
  --nvidia-pass      NVIDIA account password (prompted if omitted)
```

### Re-flashing the same board

On the second run and beyond, the script detects that images are already built and uses `--flash-only` to jump straight to flashing (no BSP rebuild, no `apply_binaries.sh`). Just put the board in recovery mode and run the same command:

```bash
sudo bash deploy/flash_board.sh --bsp /path/to/bsp.tar.xz
```

If you changed credentials, added Docker, or want a clean slate:

```bash
sudo bash deploy/flash_board.sh --bsp /path/to/bsp.tar.xz --rebuild
```

---

## Docker (optional)

Pass `--docker` to pre-install Docker CE into the rootfs before flashing:

```bash
sudo bash deploy/flash_board.sh --bsp /path/to/bsp.tar.xz --docker
```

Docker is configured with bridge networking disabled (a kernel module CRC mismatch on this board prevents it loading). Use host networking or macvlan instead:

```bash
# Host networking — simplest:
docker run --network=host <image>

# macvlan — container gets its own LAN IP (create once after flash):
docker network create -d macvlan \
    --subnet=10.1.0.0/20 --gateway=10.1.0.1 \
    -o parent=enP8p1s0 local_net

docker run --network=local_net --ip=10.1.11.100 <image>
```

> The `local_net` macvlan network must be recreated after each flash.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `lsusb` shows nothing | Board not in recovery mode | Power off completely, hold Recovery, reapply power. Do not just press Reset. |
| `lsusb` shows `0955:7035` instead of `0955:7323` | Board is in leftover initrd mode from a failed flash | Power-cycle (remove DC) to get back to `0955:7323` APX mode |
| "Board not detected after 300s" | USB cable or port issue | Use a data-capable USB-C cable directly to the host, not a hub |
| Flash fails partway, board has no lights | Partial flash of QSPI | Power-cycle, retry recovery mode — the bootloader survives partial NVMe flashes |
| "SSH timeout" during rootfs extraction | Old L4T SSH keepalive settings | Ensure you're running the latest `flash_board.sh` — it patches the keepalive values automatically |
| NetworkManager loses internet during flash | Old version of script stopped NM | Latest script keeps NM running and only unmanages the USB flash interface |
| `enP8p1s0` has no IP after boot | NM profile not created | Run the `nmcli con add ...` command above (once per flash) |
| Docker bridge fails to load | `bridge.ko` CRC mismatch against custom kernel | Use `--network=host` or macvlan — `daemon.json` already has `"bridge": "none"` |

---

## Known issues

| Issue | Detail |
|---|---|
| NM profile must be recreated after each flash | The rootfs is reflashed from scratch each time |
| macvlan network must be recreated after each flash | Docker volumes and networks are on the NVMe rootfs |
| No GRUB menu | Use UEFI 5-second timeout to interrupt boot if needed |
