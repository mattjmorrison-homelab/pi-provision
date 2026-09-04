# pi-provision

Tooling for provisioning and managing Raspberry Pis in the homelab cluster — flashing microSD cards, joining k3s nodes, and orchestrating updates via GitHub Actions.

## Fleet

- **pi5-16**: Raspberry Pi 5 (16GB) — k3s cluster member
- **pi5-8**: Raspberry Pi 5 (8GB) — k3s cluster member
- **pizero**: Raspberry Pi Zero 2 W — standalone
- **pi1**: Raspberry Pi 1 Model B Rev 2 (512MB) — standalone

Each is reachable at `<hostname>.local` over SSH (e.g. `ssh pi@pi5-16.local`) once its hostname has been set post-flash. See `fleet.yaml` for the authoritative SSH targets and operation schedule.

### Setting a unique hostname (post-flash)

Both flash scripts leave the default hostname `raspberrypi`, which collides
across multiple devices on the same network. After flashing, bring boards up
**one at a time**, SSH in while `raspberrypi.local` is still unambiguous, and
rename:

```bash
ssh pi@raspberrypi.local
sudo hostnamectl set-hostname <name>   # e.g. pi5-16, pi5-8, pizero, pi1
sudo reboot
```

Once renamed, that Pi is reachable at `<name>.local` and the next board can
be powered on and claim `raspberrypi.local` in turn.

## Fleet management via GitHub Actions

All non-interactive, scheduled, and one-off Pi operations run through GitHub Actions workflows that read `fleet.yaml` to discover targets, authenticate to OpenBao to fetch SSH keys, and run the appropriate script against each Pi.

Three workflows handle different triggers:

### Sync workflow (`sync.yml`)

Runs on every merge to `main`. Executes all tasks marked `trigger: sync` against their declared targets. Currently: `install-node-exporter.sh` on `pi1` and `pizero`.

All scripts invoked here are idempotent, so rerunning unrelated ones on an unrelated change is harmless.

### Scheduled workflow (`scheduled.yml`)

Runs on a cron schedule. Currently: `check-updates.sh` daily at noon UTC against all Pis. The cron expression is hardcoded in the workflow (GitHub Actions limitation) and must be kept in sync with the `schedule:` declared in `fleet.yaml`.

### Adhoc workflow (`adhoc.yml`)

Manually triggered via `workflow_dispatch` in GitHub. Choose a script and Pi name from the dropdown inputs. Supports:
- `install-node-exporter.sh` — choose any Pi
- `join-node.sh` — choose any Pi (leaves target blank to interactively onboard a new cluster member)
- `label-node.sh` — currently presets to `pi5-8` for serial-HDMI labeling
- `apply-updates.sh` — choose any Pi to manually trigger upgrades
- `taint-existing-nodes.sh` — cluster-wide operation, leave target blank

To add a new Pi: update `fleet.yaml` and `admin-openbao`'s SSH key store first, then dispatch against it here.

## CI/automation mode

All scripts support non-interactive mode when run from CI by setting environment variables instead of prompting:

**Required for all scripts:**
- `PI_SSH` — SSH target (e.g. `pi@pi5-8.local`)
- `SSH_KEY_FILE` — path to SSH private key

**Required for `join-node.sh` only:**
- `K3S_JOIN_TOKEN` — k3s agent token (fetched from OpenBao in CI; the control plane operator would read it locally via `sudo cat /var/lib/rancher/k3s/server/node-token` instead)

**Optional:**
- `LABEL` — for `label-node.sh`, defaults to `hardware=serial-hdmi`
- `PI_NAME` — for `check-updates.sh` and `apply-updates.sh`, defaults to the hostname from `$PI_SSH`

The workflows authenticate to OpenBao using Kubernetes ServiceAccount tokens and the `pi-provision-deploy` role (pre-provisioned in `admin-openbao`) to fetch each Pi's SSH private key from `homelab/pi/<name>/private-key` and (for join operations) the shared k3s join token from `homelab/pi/k3s-join-token`.

All scripts bootstrap a `/etc/sudoers.d/pi-provision` NOPASSWD entry on first run so later runs (interactive or CI) don't hit a sudo password prompt. This happens once inside the first `sudo bash -s` elevation and is idempotent.

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

Both scripts expect the image at a hardcoded path under `~/Downloads` (see the `IMAGE_PATH` line near the top of each script — update the filename there if you download a newer release). They prompt for the disk identifier and a password, then write the image and configure a first-boot `firstrun.sh` for SSH access (including installing your public key).

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

The node is tainted `dedicated=pi:NoSchedule` by default (override with `NODE_TAINT`), so nothing schedules onto it unless a workload explicitly tolerates that taint. Safe to rerun against an already-joined Pi — it just rewrites the k3s-agent config (including the taint) and restarts the service, briefly flipping that node to `NotReady`.

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

## Check for apt updates

Run this to see which packages are upgradable on a Pi:

```bash
bash check-updates.sh
```

Prompts for the Pi's SSH target, then refreshes apt's package index and writes a Prometheus textfile metric (`node_apt_upgrades_pending`) so monitoring can alert when updates are available. This script never installs anything — it's notify-only.

Runs automatically on a daily cron schedule against all Pis (see `fleet.yaml`'s `scheduled` trigger and the `Scheduled` workflow).

**Requires:** The `/etc/sudoers.d/pi-provision` NOPASSWD entry. Run `install-node-exporter.sh` or `label-node.sh` against the Pi first if you haven't already.

## Apply apt updates

Run this to actually install pending apt upgrades on a Pi:

```bash
bash apply-updates.sh
```

Prompts for the Pi's SSH target and confirms the action (since this actually installs packages), then runs `apt-get upgrade -y` and refreshes the `node_apt_upgrades_pending` metric so the alert clears.

Available via the `Adhoc` workflow for one-off manual deployments when you've decided it's a good time to upgrade a Pi.

**Requires:** The `/etc/sudoers.d/pi-provision` NOPASSWD entry. Run `install-node-exporter.sh` or `label-node.sh` against the Pi first if you haven't already.
