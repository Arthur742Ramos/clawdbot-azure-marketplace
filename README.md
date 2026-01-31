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

## Script details

### `scripts/setup.sh`

Installs:
- Node.js 22.x (NodeSource)
- npm global prefix under `~/.npm-global`
- Clawdbot, agent-browser, Playwright
- Chromium system package
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
