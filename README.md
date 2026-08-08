# homelab-raspberrypi

Tooling for provisioning a Raspberry Pi 5 headless over direct Ethernet from macOS.

## Flash a microSD card

```bash
bash flash-pi.sh
```

Prompts for the image path, disk identifier, and a password, then writes the image and configures cloud-init for SSH access on first boot.

**Requirements:**
- Raspberry Pi OS Lite 64-bit (Trixie, November 2025+)
- An SSH public key at `~/.ssh/id_ed25519.pub` or `~/.ssh/id_rsa.pub`

**After flashing:**
```bash
ssh pi@raspberrypi.local
```
