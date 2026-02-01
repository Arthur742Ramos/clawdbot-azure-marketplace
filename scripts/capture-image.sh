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
Usage: ./capture-image.sh

Environment variables:
  RESOURCE_GROUP        VM resource group (default: openclaw-image-rg)
  VM_NAME               VM name (default: openclaw-image-builder)
  LOCATION              Azure region (default: eastus)
  SIG_RESOURCE_GROUP    SIG resource group (default: RESOURCE_GROUP)
  GALLERY_NAME          SIG gallery name (default: openclawGallery)
  IMAGE_DEF_NAME        Image definition name (default: openclawUbuntu2404)
  IMAGE_VERSION         Image version (required, format: X.Y.Z)
  MANAGED_IMAGE_NAME    Managed image name (default: derived from IMAGE_DEF_NAME/VERSION)
  PUBLISHER             Image publisher (default: openclaw)
  OFFER                 Image offer (default: openclaw-vm)
  SKU                   Image SKU (default: openclaw-ubuntu-2404)
  HYPERV_GEN            Hyper-V generation (default: V2)
  REPLICA_COUNT         Replica count (default: 1)
  STORAGE_ACCOUNT_TYPE  Storage account type (default: Standard_LRS)
  TARGET_REGIONS        Comma-separated regions (default: LOCATION)
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
VM_NAME="${VM_NAME:-openclaw-image-builder}"
LOCATION="${LOCATION:-eastus}"
SIG_RESOURCE_GROUP="${SIG_RESOURCE_GROUP:-$RESOURCE_GROUP}"
GALLERY_NAME="${GALLERY_NAME:-openclawGallery}"
IMAGE_DEF_NAME="${IMAGE_DEF_NAME:-openclawUbuntu2404}"
IMAGE_VERSION="${IMAGE_VERSION:-}"
PUBLISHER="${PUBLISHER:-openclaw}"
OFFER="${OFFER:-openclaw-vm}"
SKU="${SKU:-openclaw-ubuntu-2404}"
HYPERV_GEN="${HYPERV_GEN:-V2}"
REPLICA_COUNT="${REPLICA_COUNT:-1}"
STORAGE_ACCOUNT_TYPE="${STORAGE_ACCOUNT_TYPE:-Standard_LRS}"
TARGET_REGIONS="${TARGET_REGIONS:-$LOCATION}"

if [[ -z "$IMAGE_VERSION" ]]; then
  die "IMAGE_VERSION is required (format: X.Y.Z)"
fi

if [[ ! "$IMAGE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  die "IMAGE_VERSION must match X.Y.Z"
fi

MANAGED_IMAGE_NAME="${MANAGED_IMAGE_NAME:-${IMAGE_DEF_NAME}-$(echo "$IMAGE_VERSION" | tr '.' '-')}"

log "Deallocating VM"
az vm deallocate --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" >/dev/null

log "Generalizing VM"
az vm generalize --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" >/dev/null

log "Creating managed image: $MANAGED_IMAGE_NAME"
az image create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$MANAGED_IMAGE_NAME" \
  --source "$VM_NAME" \
  --location "$LOCATION" >/dev/null

MANAGED_IMAGE_ID="$(az image show --resource-group "$RESOURCE_GROUP" --name "$MANAGED_IMAGE_NAME" --query id -o tsv)"

if ! az sig show --resource-group "$SIG_RESOURCE_GROUP" --gallery-name "$GALLERY_NAME" >/dev/null 2>&1; then
  log "Creating Shared Image Gallery: $GALLERY_NAME"
  az sig create --resource-group "$SIG_RESOURCE_GROUP" --gallery-name "$GALLERY_NAME" --location "$LOCATION" >/dev/null
fi

if ! az sig image-definition show \
  --resource-group "$SIG_RESOURCE_GROUP" \
  --gallery-name "$GALLERY_NAME" \
  --gallery-image-definition "$IMAGE_DEF_NAME" >/dev/null 2>&1; then
  log "Creating image definition: $IMAGE_DEF_NAME"
  az sig image-definition create \
    --resource-group "$SIG_RESOURCE_GROUP" \
    --gallery-name "$GALLERY_NAME" \
    --gallery-image-definition "$IMAGE_DEF_NAME" \
    --publisher "$PUBLISHER" \
    --offer "$OFFER" \
    --sku "$SKU" \
    --os-type Linux \
    --os-state Generalized \
    --hyper-v-generation "$HYPERV_GEN" >/dev/null
fi

IFS=',' read -r -a REGION_LIST <<< "$TARGET_REGIONS"
TARGET_ARGS=()
for region in "${REGION_LIST[@]}"; do
  region="$(echo "$region" | xargs)"
  if [[ -n "$region" ]]; then
    TARGET_ARGS+=("${region}=${REPLICA_COUNT}=${STORAGE_ACCOUNT_TYPE}")
  fi
done

log "Creating image version: $IMAGE_VERSION"
az sig image-version create \
  --resource-group "$SIG_RESOURCE_GROUP" \
  --gallery-name "$GALLERY_NAME" \
  --gallery-image-definition "$IMAGE_DEF_NAME" \
  --gallery-image-version "$IMAGE_VERSION" \
  --managed-image "$MANAGED_IMAGE_ID" \
  --target-regions "${TARGET_ARGS[@]}" >/dev/null

log "Image version created. SIG image: $GALLERY_NAME/$IMAGE_DEF_NAME/$IMAGE_VERSION"
