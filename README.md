# homelab-raspberrypi

Tooling for provisioning a Raspberry Pi 5 headless over direct Ethernet from macOS.

## Fleet

- Raspberry Pi 5 (8GB)
- Raspberry Pi 5 (16GB)
- Raspberry Pi Zero 2 W
- Raspberry Pi 1 Model B Rev 2 (512MB)

## Flash a microSD card

For Pi 5, Zero 2 W, and other 64-bit-capable boards:

```bash
bash flash-pi.sh
```

**Requirements:**
- Raspberry Pi OS Lite (64-bit) — Trixie
- An SSH public key at `~/.ssh/id_ed25519.pub` or `~/.ssh/id_rsa.pub`

For the original Pi 1 Model B (ARMv6 — not supported by 64-bit images):

```bash
bash flash-pi-legacy.sh
```

**Requirements:**
- Raspberry Pi OS Lite (32-bit) — Trixie (the 32-bit build supports all Raspberry Pi models, including ARMv6 boards)
- An SSH public key at `~/.ssh/id_ed25519.pub` or `~/.ssh/id_rsa.pub`

Both scripts prompt for the image path, disk identifier, and a password, then write the image and configure a first-boot `firstrun.sh` for SSH access (including installing your public key).

**After flashing:**
```bash
ssh pi@raspberrypi.local
```

Note: on this old hardware, first boot can take noticeably longer than on newer Pis — give it a few extra minutes before assuming something's wrong.

## Join a node to the k3s cluster

Run this **on the control plane** (it reads the join token locally, then reaches out over SSH to the Pi):

```bash
bash join-node.sh
```

Prompts for the Pi's SSH target, reads the local join token, enables the cgroup memory controller if needed (rebooting the Pi if it has to), disables swap, and installs `k3s` as an agent pointed at the control plane (`control.morrisons.site` by default, override with `CONTROL_HOST`).

## Label a node

Run this against a Pi already joined to the cluster:

```bash
bash label-node.sh
```

Prompts for the Pi's SSH target, then SSHes in to set a `node-label` in `/etc/rancher/k3s/config.yaml` and restarts `k3s-agent` so it takes effect. Defaults to `hardware=serial-hdmi` (for the Pi wired into serial hardware), override with `LABEL`.

Verify from the control plane with:

```bash
kubectl get nodes --show-labels
```
