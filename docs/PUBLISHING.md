# Partner Center Publishing Guide

This guide walks through publishing the Clawdbot VM image to Azure Marketplace.

## Prerequisites

- Partner Center account with marketplace permissions
- Azure subscription for Shared Image Gallery (SIG)
- Azure CLI logged in with sufficient permissions

## 1) Build and prepare the image

1. Create a build VM

```
./scripts/create-vm.sh
```

2. SSH into the VM and run the setup

```
sudo ./scripts/setup.sh
```

3. Validate the gateway service

```
systemctl --user status clawdbot-gateway.service
```

4. Prepare the VM for capture

```
sudo clawdbot-prepare-image --force
```

## 2) Capture to Shared Image Gallery

Choose a new version and capture the image:

```
IMAGE_VERSION=1.0.0 ./scripts/capture-image.sh
```

Get the SIG image version ID for Partner Center:

```
az sig image-version show \
  --resource-group <sig-rg> \
  --gallery-name <gallery> \
  --gallery-image-definition <image-def> \
  --gallery-image-version <version> \
  --query id -o tsv
```

## 3) Create the VM offer in Partner Center

1. Create a new VM offer and plan.
2. Record the plan IDs:
   - Publisher ID
   - Offer ID
   - Plan SKU
3. Update `templates/azuredeploy.json` and `templates/createUiDefinition.json` to match these IDs.

## 4) Technical configuration

In the Technical configuration section:

- Set the image source to Azure Compute Gallery.
- Provide the SIG image version ID from step 2.
- Ensure the OS type is Linux and generation is V2.
- Restrict authentication to SSH keys (no passwords).

## 5) Complete listing details

- Add offer summary, description, and support info.
- Upload required icons and screenshots.
- Configure pricing and availability.

## 6) Validation and publish

Run validation, fix any issues, and submit the offer for review. Once approved, publish to Marketplace.

## 7) Update workflow

For new releases:

1. Build and capture a new SIG image version.
2. Update the offer technical configuration to reference the new version.
3. If you pin a version in `templates/azuredeploy.json`, update `version` there as well.
