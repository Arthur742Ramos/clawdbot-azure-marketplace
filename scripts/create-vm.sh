#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"

log() { printf '[%s] %s\n' "$SCRIPT_NAME" "$*"; }
err() { printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2; }
die() { err "$*"; exit 1; }

trap 'err "Failed at line $LINENO: $BASH_COMMAND"' ERR
trap 'err "Cancelled by user."; exit 130' INT TERM

usage() {
  cat <<'EOF'
Usage: ./create-vm.sh

Environment variables:
  RESOURCE_GROUP        Resource group name (default: openclaw-image-rg)
  LOCATION              Azure region (default: eastus)
  VM_NAME               VM name (default: openclaw-image-builder)
  ADMIN_USERNAME        Admin username (default: openclaw)
  VM_SIZE               VM size (default: Standard_B1ms)
  OS_DISK_SIZE_GB       OS disk size in GB (default: 30)
  IMAGE                 Azure image (default: Ubuntu2404)
  SSH_PUBLIC_KEY        SSH public key string
  SSH_PUBLIC_KEY_PATH   SSH public key path (default: use generated keys)
  TAGS                  Tags string (default: role=openclaw-image-builder)
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v az >/dev/null 2>&1; then
  die "Azure CLI (az) is required"
fi

az account show >/dev/null 2>&1 || die "Not logged in to Azure CLI. Run: az login"

RESOURCE_GROUP="${RESOURCE_GROUP:-openclaw-image-rg}"
LOCATION="${LOCATION:-eastus}"
VM_NAME="${VM_NAME:-openclaw-image-builder}"
ADMIN_USERNAME="${ADMIN_USERNAME:-openclaw}"
VM_SIZE="${VM_SIZE:-Standard_B1ms}"
OS_DISK_SIZE_GB="${OS_DISK_SIZE_GB:-30}"
IMAGE="${IMAGE:-Ubuntu2404}"
TAGS="${TAGS:-role=openclaw-image-builder}"
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY:-}"
SSH_PUBLIC_KEY_PATH="${SSH_PUBLIC_KEY_PATH:-}"

SSH_ARGS=()
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
  SSH_ARGS+=(--ssh-key-values "$SSH_PUBLIC_KEY")
elif [[ -n "$SSH_PUBLIC_KEY_PATH" ]]; then
  SSH_ARGS+=(--ssh-key-values "$SSH_PUBLIC_KEY_PATH")
else
  SSH_ARGS+=(--generate-ssh-keys)
fi

log "Creating resource group: $RESOURCE_GROUP ($LOCATION)"
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --tags "$TAGS" >/dev/null

log "Creating VM: $VM_NAME"
az vm create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --location "$LOCATION" \
  --image "$IMAGE" \
  --size "$VM_SIZE" \
  --admin-username "$ADMIN_USERNAME" \
  --authentication-type ssh \
  --os-disk-size-gb "$OS_DISK_SIZE_GB" \
  --storage-sku StandardSSD_LRS \
  --public-ip-sku Standard \
  --nsg-rule SSH \
  --tags "$TAGS" \
  "${SSH_ARGS[@]}" >/dev/null

PUBLIC_IP="$(az vm show -d --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" --query publicIps -o tsv)"
log "VM created. SSH: ssh $ADMIN_USERNAME@$PUBLIC_IP"
