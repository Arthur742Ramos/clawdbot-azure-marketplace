# OpenClawVM - Azure Marketplace Image

Build and publish a production-ready Ubuntu 24.04 VM image for the Azure Marketplace with Clawdbot preinstalled and a delightful onboarding flow.

## Overview

This repository provides:
- Provisioning scripts to configure a fresh Ubuntu 24.04 VM
- Image preparation scripts for Azure image capture
- Azure CLI helpers for VM creation and SIG capture
- ARM templates and Marketplace UI definition
- Publishing guidance for Partner Center

## Architecture overview

- **System-wide CLI**: `clawdbot` and `opencode` live in `/usr/local/bin`
- **Onboarding**: `clawdbot-quickstart` handles GitHub auth + Copilot validation
- **Gateway service**: user-level systemd unit at `/etc/systemd/user/clawdbot-gateway.service`
- **Copilot token**: stored in `~/.config/clawdbot/env` (600) and loaded via `EnvironmentFile`
- **Playwright browsers**: shared at `/usr/local/share/ms-playwright` (`PLAYWRIGHT_BROWSERS_PATH`)

## Repository layout

- `scripts/setup.sh` - Install Node.js, Clawdbot, Playwright, OpenCode, and system config
- `scripts/first-boot.sh` - Cloud-init compatible first-boot setup
- `scripts/quickstart.sh` - End-user onboarding (GitHub auth, Copilot check, channels)
- `scripts/first-login.sh` - One-time first-SSH prompt for quickstart
- `scripts/prepare-image.sh` - Deprovision and cleanup before capture
- `scripts/create-vm.sh` - Create a VM for image building
- `scripts/capture-image.sh` - Capture VM to a Shared Image Gallery
- `systemd/clawdbot-gateway.service` - User-level gateway service unit
- `templates/azuredeploy.json` - Marketplace ARM template
- `templates/createUiDefinition.json` - Marketplace UI definition
- `docs/PUBLISHING.md` - Partner Center publishing guide

## Build the image

1) Create a build VM

```
chmod +x scripts/*.sh
./scripts/create-vm.sh
```

2) SSH into the VM and run setup

```
sudo ./scripts/setup.sh
```

Setup installs assets into `/opt/clawdbot` and creates system-wide symlinks:

```
clawdbot-setup
clawdbot-quickstart
clawdbot-first-login
clawdbot-first-boot
clawdbot-prepare-image
clawdbot-create-vm
clawdbot-capture-image
```

3) Optional: validate the gateway service

```
systemctl --user status clawdbot-gateway.service
```

4) Prepare the VM for capture

```
sudo clawdbot-prepare-image --force
```

5) Capture to Shared Image Gallery

```
IMAGE_VERSION=1.0.0 ./scripts/capture-image.sh
```

### Setup options

`scripts/setup.sh` supports the following environment variables:

- `NODE_MAJOR` (default: 22)
- `INSTALL_PLAYWRIGHT_BROWSERS=0` to skip browser download
- `INSTALL_OPENCODE=0` to skip OpenCode
- `OPENCODE_URL` to override the download URL
- `OPENCODE_SHA256` to verify the OpenCode archive

## Marketplace onboarding (end users)

After a customer deploys the VM from Azure Marketplace:

1) SSH into the VM
2) Run `clawdbot-quickstart`
3) Follow device flow or token prompts

Notes:
- Quickstart validates Copilot entitlement before declaring success.
- OpenCode requires a PTY. If SSH hangs, use `ssh -tt <user>@<host>`.
- Set `CLAWDBOT_SKIP_FIRST_LOGIN=1` to disable the first-login prompt.

## Non-interactive / enterprise usage

Quickstart supports non-interactive and cloud-init friendly flows.

Supported token sources:
- Env vars: `CLAWDBOT_GITHUB_TOKEN`, `GITHUB_TOKEN`, `GH_TOKEN`
- Token file: `~/.config/clawdbot/seed/github_token` or `/var/lib/clawdbot/secrets/github_token`

Non-interactive example:

```
clawdbot-quickstart --non-interactive --auth-method token --no-channels
```

GitHub Enterprise example:

```
clawdbot-quickstart --github-host github.example.com --non-interactive --auth-method token --no-channels
```

Cloud-init example:

```
#cloud-config
write_files:
  - path: /var/lib/clawdbot/secrets/github_token
    owner: azureuser:azureuser
    permissions: '0600'
    content: ghp_xxx
runcmd:
  - [ sudo, -u, azureuser, "--", "clawdbot-quickstart", "--non-interactive", "--auth-method", "token", "--no-channels" ]
```

## Service management

```
systemctl --user enable --now clawdbot-gateway.service
systemctl --user status clawdbot-gateway.service
journalctl --user -u clawdbot-gateway.service -f
```

To keep the gateway running after logout:

```
sudo loginctl enable-linger $USER
```

## Troubleshooting

- **Auth hangs or fails**: confirm network access to `github.com` and `api.github.com`, then re-run `clawdbot-quickstart`.
- **No Copilot subscription**: quickstart will report this. Ensure the GitHub account has Copilot access.
- **OpenCode hangs**: allocate a PTY: `ssh -tt <user>@<host>`.
- **Service not starting**: verify `clawdbot` is on PATH and inspect `journalctl --user -u clawdbot-gateway.service`.
- **Playwright browser missing**: re-run `npx playwright install chromium` (or set `INSTALL_PLAYWRIGHT_BROWSERS=1` during setup).

## Security notes

- GitHub CLI stores tokens in `~/.config/gh/hosts.yml` (600).
- Quickstart writes `~/.config/clawdbot/env` (600) for Copilot exports.
- `clawdbot-prepare-image` removes tokens, histories, and logs before capture.

## Publishing

See `docs/PUBLISHING.md` for full Partner Center steps.
