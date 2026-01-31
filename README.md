# Clawdbot Azure Marketplace VM

Build and publish a production-ready Ubuntu 24.04 VM image for the Azure Marketplace with Clawdbot preinstalled.

## Overview

This repository provides:
- Provisioning scripts to configure a fresh Ubuntu 24.04 VM
- Image preparation scripts for Azure image capture
- Azure CLI helpers for VM creation and SIG capture
- ARM templates and Marketplace UI definition
- Publishing guidance for Partner Center

## Repository layout

- `scripts/setup.sh` - Install Node.js, Clawdbot, Playwright, and service configuration
- `scripts/first-boot.sh` - Cloud-init compatible first-boot setup
- `scripts/quickstart.sh` - End-user onboarding (GitHub auth, channels, Copilot env)
- `scripts/first-login.sh` - One-time first-SSH prompt for quickstart
- `scripts/prepare-image.sh` - Deprovision and cleanup before capture
- `scripts/create-vm.sh` - Create a VM for image building
- `scripts/capture-image.sh` - Capture VM to a Shared Image Gallery
- `templates/azuredeploy.json` - Marketplace ARM template
- `templates/createUiDefinition.json` - Marketplace UI definition
- `docs/PUBLISHING.md` - Partner Center publishing guide

## Requirements

- Ubuntu 24.04 LTS for the build VM
- Azure CLI (`az`) installed and logged in
- Azure subscription with permissions for VM, SIG, and Marketplace

## Quick start

1) Create a build VM

```
chmod +x scripts/*.sh
./scripts/create-vm.sh
```

2) SSH into the VM and run the setup

```
sudo ./scripts/setup.sh
```

3) Optional: verify the service

```
systemctl --user status clawdbot-gateway.service
```

4) Prepare the VM for capture

```
sudo ./scripts/prepare-image.sh --force
```

5) Capture to Shared Image Gallery

```
IMAGE_VERSION=1.0.0 ./scripts/capture-image.sh
```

## Marketplace onboarding (end users)

After a customer deploys the VM from Azure Marketplace:

1) SSH into the VM
2) Run `clawdbot-quickstart`
3) Follow the prompts to authenticate GitHub Copilot and optionally connect channels

Enterprise or non-interactive setup options:

- Provide a token via env vars: `CLAWDBOT_GITHUB_TOKEN`, `GITHUB_TOKEN`, or `GH_TOKEN`
- Or drop a token file at `~/.config/clawdbot/seed/github_token` or `/var/lib/clawdbot/secrets/github_token` (must be user-readable)
- Token must belong to a user with Copilot access
- Run: `clawdbot-quickstart --non-interactive --auth-method token --no-channels`
- For GitHub Enterprise, add `--github-host github.example.com`

Example cloud-init:

```
#cloud-config
write_files:
  - path: /home/azureuser/.config/clawdbot/seed/github_token
    owner: azureuser:azureuser
    permissions: '0600'
    content: ghp_xxx
runcmd:
  - [ sudo, -u, azureuser, "--", "clawdbot-quickstart", "--non-interactive", "--auth-method", "token", "--no-channels" ]
```

Security notes:

- GitHub CLI stores tokens in `~/.config/gh/hosts.yml` (600)
- Quickstart writes `~/.config/clawdbot/env` (600) to export `COPILOT_GITHUB_TOKEN` and configures the gateway service when present
- Seed token files are removed after successful login (unless provided via `--token-file`)
- Remove those files and run `gh auth logout` to revoke

If auth fails:

- Re-run `clawdbot-quickstart`, or skip with `--skip-auth` to continue without Copilot

## Script details

### `scripts/setup.sh`

Installs:
- Node.js 22.x (NodeSource)
- npm global prefix under `~/.npm-global`
- Clawdbot, agent-browser, Playwright
- Chromium system package
- GitHub CLI (`gh`)
- Onboarding helpers (`clawdbot-quickstart`, first-login prompt)
- User systemd service for `clawdbot-gateway`

Environment variables:
- `CLAWDBOT_USER` (optional) target username for user-level config
- `NODE_MAJOR` (optional) Node.js major version (default: 22)
- `INSTALL_OPENCODE=1` to enable OpenCode install
- `OPENCODE_URL` download URL for OpenCode binary
- `OPENCODE_SHA256` optional checksum for verification

Notes:
- The script sets `UNDICI_NO_HTTP2=1` for shell sessions and the systemd service.
- The service uses `%h/.npm-global/bin/clawdbot gateway start` by default.
- Login shells source `~/.config/clawdbot/env` when present (for Copilot auth export).
- Set `CLAWDBOT_SKIP_FIRST_LOGIN=1` to disable the first-login quickstart prompt.

### `scripts/first-boot.sh`

Cloud-init compatible script that:
- Writes a welcome MOTD
- Drops a completion marker in `/var/lib/clawdbot/first-boot.done`

Example cloud-init usage:

```
#cloud-config
runcmd:
  - [ bash, -c, "/opt/clawdbot/first-boot.sh" ]
```

### `scripts/quickstart.sh`

Interactive onboarding for end users that:
- Authenticates GitHub Copilot (device flow or token)
- Exports Copilot token to `~/.config/clawdbot/env`
- Optionally configures `clawdbot-gateway.service` to load the token
- Prompts to add messaging channels

### `scripts/first-login.sh`

First-login prompt that runs `clawdbot-quickstart` once per user (opt-out via `CLAWDBOT_SKIP_FIRST_LOGIN=1`).

### `scripts/prepare-image.sh`

Removes sensitive data and deprovisions the VM. Requires `--force` to run.

### `scripts/create-vm.sh`

Creates a B1ms VM in a new resource group with SSH access. Override defaults with env vars:

```
RESOURCE_GROUP=clawdbot-image-rg
LOCATION=eastus
VM_NAME=clawdbot-image-builder
ADMIN_USERNAME=clawdbot
VM_SIZE=Standard_B1ms
OS_DISK_SIZE_GB=30
```

### `scripts/capture-image.sh`

Captures the VM to a Shared Image Gallery image version.

Required:
- `IMAGE_VERSION` (format `X.Y.Z`)

Optional:
- `SIG_RESOURCE_GROUP`, `GALLERY_NAME`, `IMAGE_DEF_NAME`
- `PUBLISHER`, `OFFER`, `SKU`, `HYPERV_GEN`
- `TARGET_REGIONS` (comma-separated)

## Marketplace templates

The ARM template (`templates/azuredeploy.json`) provisions a VM with a public IP, NSG, VNet, and NIC. The Marketplace UI definition (`templates/createUiDefinition.json`) collects the VM name, region, SSH key, VM size, and DNS label prefix.

If your Partner Center IDs differ, update these defaults in both templates:
- `publisher`
- `offer`
- `sku`

## Operations

Service management:

```
systemctl --user status clawdbot-gateway.service
systemctl --user restart clawdbot-gateway.service
journalctl --user -u clawdbot-gateway.service -f
```

## Troubleshooting

- Playwright download failures: verify outbound internet access and rerun `playwright install chromium`.
- Service not starting: check PATH includes `~/.npm-global/bin` and review `journalctl --user -u clawdbot-gateway.service`.
- Azure capture errors: ensure `prepare-image.sh --force` was run before generalizing.

## Publishing

See `docs/PUBLISHING.md` for full Partner Center publishing steps.
