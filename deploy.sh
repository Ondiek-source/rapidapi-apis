#!/usr/bin/env bash
# =============================================================================
# Azure Functions — Root Deploy Script
# Loops through all subfolders, deploys each as a separate Function App.
# Folder name → fn-rapidapi-<folder-name>
#
# Usage:  ./deploy.sh              ← deploys all folders
#         ./deploy.sh <folder>     ← deploys only that folder
#
# Each API folder needs a .env file with at minimum:
#   RAPIDAPI_PROXY_SECRET=<your-secret-from-rapidapi-gateway>
# =============================================================================
set -euo pipefail

# ──────────────────────────────────────────────
# DEFAULTS (override via env)
# ──────────────────────────────────────────────
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-05bfd83f-202d-4f35-a8dd-4f7525f51434}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-rapidapis}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-st-$RESOURCE_GROUP-fns-$(date +%s)}"
LOCATION="${LOCATION:-eastus}"
NODE_VERSION="${NODE_VERSION:-~20}"
APP_SERVICE_PLAN="${APP_SERVICE_PLAN:-EastUSPlan}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ──────────────────────────────────────────────
# HELPERS
# ──────────────────────────────────────────────
log()     { echo -e "\033[1;34m▶\033[0m  $*"; }
success() { echo -e "\033[1;32m✔\033[0m  $*"; }
warn()    { echo -e "\033[1;33m⚠\033[0m  $*"; }
die()     { echo -e "\033[1;31m✖\033[0m  $*" >&2; exit 1; }
header()  { echo -e "\n\033[1;35m══════════════════════════════════════════\033[0m"; echo -e "\033[1;35m  $*\033[0m"; echo -e "\033[1;35m══════════════════════════════════════════\033[0m"; }

fail() {
  # fail <folder> <step> <remedy>
  local folder="$1" step="$2" remedy="$3"
  echo -e "\033[1;31m✖  FAILED: $folder @ $step\033[0m" >&2
  echo -e "\033[1;33m   ➜ $remedy\033[0m" >&2
}

# ──────────────────────────────────────────────
# PRE-FLIGHT CHECKS
# ──────────────────────────────────────────────
log "Checking required tools..."
command -v az   >/dev/null 2>&1 || die "'az' not found.\n   ➜ Install: https://aka.ms/installazurecli"
command -v func >/dev/null 2>&1 || die "'func' not found.\n   ➜ Run: npm install -g azure-functions-core-tools@4"
command -v npm  >/dev/null 2>&1 || die "'npm' not found.\n   ➜ Install Node.js from https://nodejs.org"
success "All tools present."

# ──────────────────────────────────────────────
# AZURE LOGIN & SUBSCRIPTION
# ──────────────────────────────────────────────
log "Checking Azure login..."
if ! az account show >/dev/null 2>&1; then
  warn "Not logged in — launching az login..."
  az login || die "Azure login failed.\n   ➜ Try: az login --use-device-code"
fi

log "Setting subscription..."
az account set --subscription "$SUBSCRIPTION_ID" \
  || die "Could not set subscription '$SUBSCRIPTION_ID'.\n   ➜ Check the SUBSCRIPTION_ID at the top of this script matches your Azure portal."
success "Subscription set."

# ──────────────────────────────────────────────
# RESOURCE GROUP (idempotent)
# ──────────────────────────────────────────────
log "Ensuring resource group '$RESOURCE_GROUP' exists..."
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --output none \
  || die "Could not create/find resource group '$RESOURCE_GROUP'.\n   ➜ Check your Azure permissions or change RESOURCE_GROUP at the top of this script."
success "Resource group ready."

# ──────────────────────────────────────────────
# APP SERVICE PLAN (idempotent)
# ──────────────────────────────────────────────
log "Ensuring App Service Plan '$APP_SERVICE_PLAN' exists..."
EXISTING_PLAN=$(az appservice plan show \
  --name "$APP_SERVICE_PLAN" \
  --resource-group "$RESOURCE_GROUP" \
  --query "name" -o tsv 2>/dev/null || true)

if [[ -z "$EXISTING_PLAN" ]]; then
  log "Creating App Service Plan '$APP_SERVICE_PLAN'..."
  az appservice plan create \
    --name "$APP_SERVICE_PLAN" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --sku Y1 \
    --is-linux \
    --output none \
    || die "Could not create App Service Plan '$APP_SERVICE_PLAN'.\
   ➜ Check your Azure permissions or region availability."
  success "App Service Plan created."
else
  success "App Service Plan already exists — skipping creation."
fi

# ──────────────────────────────────────────────
# STORAGE ACCOUNT (idempotent)
# ──────────────────────────────────────────────
log "Ensuring storage account '$STORAGE_ACCOUNT' exists..."
EXISTING_STORAGE=$(az storage account show \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --query "name" -o tsv 2>/dev/null || true)

if [[ -z "$EXISTING_STORAGE" ]]; then
  log "Creating storage account '$STORAGE_ACCOUNT'..."
  az storage account create \
    --name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    --output none \
    || die "Could not create storage account '$STORAGE_ACCOUNT'.\n   ➜ Name must be globally unique, 3-24 lowercase letters/numbers. Try changing STORAGE_ACCOUNT at the top of this script."
  success "Storage account created."
else
  success "Storage account already exists — skipping creation."
fi

# ──────────────────────────────────────────────
# DISCOVER FOLDERS TO DEPLOY
# ──────────────────────────────────────────────
declare -a TARGETS=()

if [[ -n "${1:-}" ]]; then
  [[ -d "$ROOT_DIR/$1" ]] || die "Folder '$1' not found.\n   ➜ Run ./bootstrap.sh $1 to create it first."
  TARGETS=("$1")
else
  for dir in "$ROOT_DIR"/*/; do
    folder=$(basename "$dir")
    if [[ -f "$dir/package.json" ]]; then
      TARGETS+=("$folder")
    fi
  done
fi

[[ ${#TARGETS[@]} -eq 0 ]] && die "No deployable folders found.\n   ➜ Run ./bootstrap.sh <name> to scaffold your first API."

log "Found ${#TARGETS[@]} function(s) to process: ${TARGETS[*]}"

# ──────────────────────────────────────────────
# DEPLOY EACH FUNCTION
# ──────────────────────────────────────────────
DEPLOYED=()
FAILED=()

deploy_function() {
  local folder="$1"
  local dir="$ROOT_DIR/$folder"
  local raw_name app_name
  raw_name=$(echo "$folder" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
  app_name="fn-rapidapi-${raw_name}"

  header "📦 $folder → $app_name"

  # ── .env ──────────────────────────────────────
  local env_file="$dir/.env"
  local proxy_secret=""

  if [[ ! -f "$env_file" ]]; then
    fail "$folder" ".env check" "Create $folder/.env — copy $folder/.env.example and fill in RAPIDAPI_PROXY_SECRET from RapidAPI → API Studio → Gateway tab."
    return 1
  fi

  proxy_secret=$(grep -E '^RAPIDAPI_PROXY_SECRET=' "$env_file" | cut -d '=' -f2- | tr -d '"' | tr -d "'" || true)

  if [[ -z "$proxy_secret" ]]; then
    fail "$folder" ".env check" "RAPIDAPI_PROXY_SECRET is empty in $folder/.env — get the value from RapidAPI → API Studio → $folder → Gateway tab."
    return 1
  fi
  success ".env loaded."

  # ── Required files ────────────────────────────
  for required in package.json host.json tsconfig.json; do
    if [[ ! -f "$dir/$required" ]]; then
      fail "$folder" "file check" "$required is missing — run ./bootstrap.sh $folder to regenerate the folder structure."
      return 1
    fi
  done

  # ── Function App (idempotent) ─────────────────
  log "Checking if '$app_name' exists on Azure..."
  local existing
  existing=$(az functionapp show \
    --name "$app_name" \
    --resource-group "$RESOURCE_GROUP" \
    --query "name" -o tsv 2>/dev/null || true)

  if [[ -z "$existing" ]]; then
    log "Creating Function App '$app_name'..."
    az functionapp create \
      --name "$app_name" \
      --resource-group "$RESOURCE_GROUP" \
      --storage-account "$STORAGE_ACCOUNT" \
      --plan "$APP_SERVICE_PLAN" \
      --runtime node \
      --runtime-version "$NODE_VERSION" \
      --functions-version 4 \
      --os-type Linux \
      --output none \
      || { fail "$folder" "az functionapp create" "Check that storage account '$STORAGE_ACCOUNT' and plan '$APP_SERVICE_PLAN' exist in resource group '$RESOURCE_GROUP'."; return 1; }
    success "Function App created."
  else
    success "Function App already exists — skipping creation."
  fi

  # ── Azure env vars ────────────────────────────
  log "Setting RAPIDAPI_PROXY_SECRET on Azure..."
  az functionapp config appsettings set \
    --name "$app_name" \
    --resource-group "$RESOURCE_GROUP" \
    --settings "RAPIDAPI_PROXY_SECRET=${proxy_secret}" \
    --output none \
    || { fail "$folder" "appsettings set" "Could not set env vars on '$app_name' — check your Azure permissions."; return 1; }
  success "Azure env vars updated."

  # ── npm install ───────────────────────────────
  log "Installing dependencies..."
  (cd "$dir" && npm ci) \
    || { fail "$folder" "npm ci" "Dependency install failed — check $folder/package.json or delete node_modules and retry."; return 1; }

  # ── Build ─────────────────────────────────────
  log "Building TypeScript..."
  (cd "$dir" && npm run build) \
    || { fail "$folder" "npm run build" "TypeScript build failed — check $folder/src for type errors. Run: cd $folder && npm run build"; return 1; }

  # ── Publish ───────────────────────────────────
  log "Publishing '$app_name'..."
  (cd "$dir" && func azure functionapp publish "$app_name" --typescript) \
    || { fail "$folder" "func publish" "Publish failed — ensure you're logged in (az login) and '$app_name' exists in Azure portal."; return 1; }

  success "✔ $app_name deployed."
  success "Portal: https://portal.azure.com/#resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$app_name/overview"
}

for folder in "${TARGETS[@]}"; do
  if deploy_function "$folder"; then
    DEPLOYED+=("$folder")
  else
    FAILED+=("$folder")
  fi
done

# ──────────────────────────────────────────────
# SUMMARY
# ──────────────────────────────────────────────
header "📊 Deploy Summary"
[[ ${#DEPLOYED[@]} -gt 0 ]] && success "Deployed (${#DEPLOYED[@]}): ${DEPLOYED[*]}"
if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo -e "\033[1;31m✖  Failed  (${#FAILED[@]}): ${FAILED[*]}\033[0m" >&2
  echo -e "\033[1;33m   ➜ Scroll up for per-failure remedies.\033[0m" >&2
  exit 1
fi
