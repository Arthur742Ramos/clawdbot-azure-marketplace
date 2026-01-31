# Clawdbot Azure Marketplace VM

## Goal
Create everything needed to publish a Clawdbot VM image to Azure Marketplace.

## What We're Building

### 1. VM Setup Script (`scripts/setup.sh`)
Automated installation script that configures a fresh Ubuntu 24.04 VM with:
- Node.js 22.x (via NodeSource)
- npm global prefix configuration
- Clawdbot (npm global)
- Playwright + Chromium browser
- OpenCode binary (optional AI coding agent)
- agent-browser (npm global)
- Required system packages (git, curl, jq, chromium-browser)
- Systemd user service for clawdbot-gateway
- Environment variables (UNDICI_NO_HTTP2=1 for 421 fix)
- loginctl enable-linger for persistent service

### 2. First-Boot Script (`scripts/first-boot.sh`)
Cloud-init compatible script that runs on first boot:
- Creates welcome MOTD
- Marks initialization complete
- Guides user to run `clawdbot-quickstart`

### 3. Image Prep Script (`scripts/prepare-image.sh`)
Script to run before capturing the VM image:
- Removes sensitive data (credentials, sessions, history)
- Clears SSH keys (Azure injects new ones)
- Runs waagent -deprovision

### 4. Azure CLI Deployment Scripts
- `scripts/create-vm.sh` - Create new B1ms VM for image building
- `scripts/capture-image.sh` - Generalize and capture VM to Shared Image Gallery

### 5. ARM Template (`templates/`)
- `azuredeploy.json` - ARM template for marketplace deployment
- `createUiDefinition.json` - Custom UI for marketplace

### 6. Documentation
- `README.md` - Full documentation
- `docs/PUBLISHING.md` - Partner Center publishing guide

## Reference: Current Working VM Configuration

### VM Specs
- Azure Size: Standard_B2ms (current), target B1ms for marketplace
- OS: Ubuntu 24.04 LTS
- Region: eastus

### Software Stack
```
Node.js: v22.22.0
npm: 10.9.4
Clawdbot: 2026.1.24-3
OpenCode: 1.1.36
Playwright: chromium-1208
```

### npm Global Packages
- clawdbot
- @github (copilot SDK)
- agent-browser
- playwright
- puppeteer-core

### Systemd Service (user-level)
Path: /etc/systemd/user/clawdbot-gateway.service
Enabled with: systemctl --user enable --now clawdbot-gateway.service

### Environment Variables
- PATH includes ~/.npm-global/bin
- UNDICI_NO_HTTP2=1 (fixes 421 errors after idle)

### Disk Usage
- Clawdbot + deps: ~1.6 GB
- Playwright browsers: ~622 MB
- OpenCode: ~142 MB
- Total: ~2.5 GB (30 GB disk sufficient)

## Target VM for Marketplace
- Size: Standard_B1ms (1 vCPU, 2 GB RAM, ~$15/mo)
- Disk: 30 GB Standard SSD
- OS: Ubuntu 24.04 LTS

## Files to Create
1. scripts/setup.sh
2. scripts/first-boot.sh
3. scripts/prepare-image.sh
4. scripts/create-vm.sh
5. scripts/capture-image.sh
6. templates/azuredeploy.json
7. templates/createUiDefinition.json
8. docs/PUBLISHING.md
9. README.md (comprehensive)
10. .gitignore
11. systemd/clawdbot-gateway.service
