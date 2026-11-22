# pi-provision

Tooling for provisioning and managing Raspberry Pis in the homelab cluster — flashing microSD cards, joining k3s nodes, and orchestrating updates via GitHub Actions.

## Fleet

- **pi5-16**: Raspberry Pi 5 (16GB) — k3s cluster member
- **pi5-8**: Raspberry Pi 5 (8GB) — k3s cluster member
- **pizero**: Raspberry Pi Zero 2 W — standalone
- **pi1**: Raspberry Pi 1 Model B Rev 2 (512MB) — standalone

Each is reachable at `<hostname>.local` over SSH (e.g. `ssh pi@pi5-16.local`) once its hostname has been set post-flash. See `pi-fleet`'s `fleet.yaml` for the authoritative SSH targets, and this repo's `fleet/` directory for each Pi's provisioning steps.

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

All non-interactive, scheduled, and one-off Pi operations run through GitHub Actions workflows. Each run signs an ephemeral SSH certificate through OpenBao's SSH CA (via GitHub OIDC and `actions-openbao/sign-ssh`, under the `pi-fleet` OpenBao role), resolves the target's SSH host/user through `pi-fleet`'s `resolve-target` action, then runs the appropriate script or `fleet/<name>/provision.sh` against it.

Each Pi has its own `fleet/<name>/provision.sh`, which chains together whatever that Pi's role needs from `scripts/`:
- `fleet/pi1/provision.sh`, `fleet/pizero/provision.sh` (standalone): `scripts/ca-trust.sh` then `scripts/install-node-exporter.sh`
- `fleet/pi5-16/provision.sh` (cluster): `scripts/ca-trust.sh` then `scripts/join-node.sh`
- `fleet/pi5-8/provision.sh` (cluster, serial-HDMI): `scripts/ca-trust.sh`, `scripts/join-node.sh`, then `scripts/label-node.sh`

Three workflows handle different triggers:

### Sync workflow (`sync.yml`)

Runs on every merge to `main`. Provisions every Pi under `fleet/` by running its `provision.sh`.

All scripts invoked here are idempotent, so rerunning a Pi's `provision.sh` on an unrelated change is harmless.

### Scheduled workflow (`scheduled.yml`)

Runs on a cron schedule. Currently: `scripts/check-updates.sh` daily at noon UTC against every Pi under `fleet/`. The cron expression is hardcoded in the workflow (a GitHub Actions limitation).

### Adhoc workflow (`adhoc.yml`)

Manually triggered via `workflow_dispatch` in GitHub. Choose an action and (except for `taint-existing-nodes.sh`) a Pi name from the dropdown inputs. Supports:
- `provision` — runs the chosen Pi's `fleet/<name>/provision.sh`
- `apply-updates.sh` — choose any Pi to manually trigger upgrades
- `taint-existing-nodes.sh` — cluster-wide operation, leave target blank

`install-node-exporter.sh`, `join-node.sh`, and `label-node.sh` are only reachable via `provision` now — they aren't direct-dispatch options.

To add a new Pi: add it to `admin-openbao`'s `locals.tf`, `pi-fleet`'s `fleet.yaml`, and this repo's `fleet/<name>/provision.sh` first, then dispatch against it here.

## CI/automation mode

All scripts support non-interactive mode when run from CI by setting environment variables instead of prompting:

**Required for all scripts:**
- `PI_SSH` — SSH target (e.g. `pi@pi5-8.local`)
- `SSH_KEY_FILE` — path to SSH private key

**Required for `scripts/join-node.sh` only:**
- `K3S_JOIN_TOKEN` — k3s agent token (fetched from OpenBao in CI; the control plane operator would read it locally via `sudo cat /var/lib/rancher/k3s/server/node-token` instead)

**Optional:**
- `LABEL` — for `scripts/label-node.sh`, defaults to `hardware=serial-hdmi`
- `PI_NAME` — for `scripts/check-updates.sh` and `scripts/apply-updates.sh`, defaults to the hostname from `$PI_SSH`

Each workflow run signs its own ephemeral SSH key/certificate through OpenBao's SSH CA via GitHub OIDC (no static per-Pi key stored anywhere) and fetches the shared k3s join token from `homelab/pi/k3s-join-token` using Kubernetes ServiceAccount auth and the `pi-provision-deploy` role (pre-provisioned in `admin-openbao`) — that token fetch is unrelated to SSH access and unchanged from before.

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
bash scripts/join-node.sh
```

Prompts for the Pi's SSH target, reads the local join token, enables the cgroup memory controller if needed (rebooting the Pi if it has to), disables swap, and installs `k3s` as an agent pointed at the control plane (`control.morrisons.site` by default, override with `CONTROL_HOST`).

The node is tainted `dedicated=pi:NoSchedule` by default (override with `NODE_TAINT`), so nothing schedules onto it unless a workload explicitly tolerates that taint. Safe to rerun against an already-joined Pi — it just rewrites the k3s-agent config (including the taint) and restarts the service, briefly flipping that node to `NotReady`.

## Label a node

Run this against a Pi already joined to the cluster:

```bash
bash scripts/label-node.sh
```

Prompts for the Pi's SSH target, then SSHes in to set a `node-label` in `/etc/rancher/k3s/config.yaml` and restarts `k3s-agent` so it takes effect. Defaults to `hardware=serial-hdmi` (for the Pi wired into serial hardware), override with `LABEL`.

Verify from the control plane with:

```bash
kubectl get nodes --show-labels
```

## Check for apt updates

Run this to see which packages are upgradable on a Pi:

```bash
bash scripts/check-updates.sh
```

Prompts for the Pi's SSH target, then refreshes apt's package index and writes a Prometheus textfile metric (`node_apt_upgrades_pending`) so monitoring can alert when updates are available. This script never installs anything — it's notify-only.

Runs automatically on a daily cron schedule against every Pi under `fleet/` (see the `Scheduled` workflow).

**Requires:** The `/etc/sudoers.d/pi-provision` NOPASSWD entry. Run `scripts/install-node-exporter.sh` or `scripts/label-node.sh` against the Pi first if you haven't already.

## Apply apt updates

Run this to actually install pending apt upgrades on a Pi:

```bash
bash scripts/apply-updates.sh
```

Prompts for the Pi's SSH target and confirms the action (since this actually installs packages), then runs `apt-get upgrade -y` and refreshes the `node_apt_upgrades_pending` metric so the alert clears.

Available via the `Adhoc` workflow for one-off manual deployments when you've decided it's a good time to upgrade a Pi.

**Requires:** The `/etc/sudoers.d/pi-provision` NOPASSWD entry. Run `scripts/install-node-exporter.sh` or `scripts/label-node.sh` against the Pi first if you haven't already.
