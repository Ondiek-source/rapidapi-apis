#!/usr/bin/env bash
# =============================================================================
# Bootstrap — Scaffold a new RapidAPI Azure Function
# Usage:  ./bootstrap.sh <api-name>
#         ./bootstrap.sh motivational-insult
#
# Creates:
#   <api-name>/
#   ├── src/functions/<api-name>.ts   ← handler + health check
#   ├── host.json
#   ├── local.settings.json
#   ├── package.json
#   ├── tsconfig.json
#   ├── .env.example
#   └── .env                          ← created empty, fill in proxy secret
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ──────────────────────────────────────────────
# HELPERS
# ──────────────────────────────────────────────
log()     { echo -e "\033[1;34m▶\033[0m  $*"; }
success() { echo -e "\033[1;32m✔\033[0m  $*"; }
warn()    { echo -e "\033[1;33m⚠\033[0m  $*"; }
die()     { echo -e "\033[1;31m✖\033[0m  $*" >&2; exit 1; }

# ──────────────────────────────────────────────
# ARGS
# ──────────────────────────────────────────────
if [[ -z "${1:-}" ]]; then
  read -rp "Enter API name (e.g. motivational-insult): " RAW_NAME
else
  RAW_NAME="$1"
fi

# Sanitise: lowercase, spaces to hyphens
API_NAME=$(echo "$RAW_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
# Handler function name: kebab-case → camelCase (e.g. my-api → myApi)
HANDLER_NAME=$(echo "$API_NAME" | sed -E 's/-([a-z])/\U\1/g' | sed -E 's/^([A-Z])/\l\1/')

TARGET_DIR="$ROOT_DIR/$API_NAME"

[[ -d "$TARGET_DIR" ]] && die "Folder '$API_NAME' already exists."

log "Scaffolding '$API_NAME' → fn-rapidapi-$API_NAME"

# ──────────────────────────────────────────────
# CREATE FOLDER STRUCTURE
# ──────────────────────────────────────────────
mkdir -p "$TARGET_DIR/src/functions"

# ── package.json ──────────────────────────────
cat > "$TARGET_DIR/package.json" << PKGJSON
{
  "name": "$API_NAME",
  "version": "1.0.0",
  "description": "",
  "main": "dist/src/functions/*.js",
  "scripts": {
    "build": "tsc",
    "watch": "tsc -w",
    "clean": "rimraf dist",
    "prestart": "npm run clean && npm run build",
    "start": "func start",
    "test": "echo \"No tests yet...\""
  },
  "dependencies": {
    "@azure/functions": "^4.0.0"
  },
  "devDependencies": {
    "@types/node": "^18.19.130",
    "azure-functions-core-tools": "^4.x",
    "rimraf": "^5.0.0",
    "typescript": "^5.0.0"
  }
}
PKGJSON

# ── host.json ─────────────────────────────────
cat > "$TARGET_DIR/host.json" << 'HOSTJSON'
{
  "version": "2.0",
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true,
        "excludedTypes": "Request"
      }
    }
  },
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[4.*, 5.0.0)"
  }
}
HOSTJSON

# ── local.settings.json ───────────────────────
cat > "$TARGET_DIR/local.settings.json" << 'LOCALSETTINGS'
{
  "IsEncrypted": false,
  "Values": {
    "FUNCTIONS_WORKER_RUNTIME": "node",
    "AzureWebJobsStorage": "UseDevelopmentStorage=true"
  }
}
LOCALSETTINGS

# ── tsconfig.json ─────────────────────────────
cat > "$TARGET_DIR/tsconfig.json" << 'TSCONFIG'
{
  "compilerOptions": {
    "module": "commonjs",
    "target": "es6",
    "outDir": "dist",
    "rootDir": ".",
    "sourceMap": true,
    "strict": false,
    "esModuleInterop": true,
    "types": ["node"]
  }
}
TSCONFIG

# ── .env.example ──────────────────────────────
cat > "$TARGET_DIR/.env.example" << 'ENVEXAMPLE'
# Copy this file to .env and fill in your values
# Find RAPIDAPI_PROXY_SECRET in: API Studio → Your API → Gateway tab
RAPIDAPI_PROXY_SECRET=your-proxy-secret-from-rapidapi-gateway
ENVEXAMPLE

# ── .env (empty, ready to fill) ───────────────
cat > "$TARGET_DIR/.env" << 'ENVFILE'
RAPIDAPI_PROXY_SECRET=
ENVFILE

# ── src/functions/<api-name>.ts ───────────────
cat > "$TARGET_DIR/src/functions/${API_NAME}.ts" << TSFILE
import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';

export async function ${HANDLER_NAME}Handler(request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  const proxySecret = request.headers.get('x-rapidapi-proxy-secret');
  const expectedSecret = process.env.RAPIDAPI_PROXY_SECRET;

  if (!expectedSecret || !proxySecret || proxySecret !== expectedSecret) {
    return {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ error: 'Unauthorized' })
    };
  }

  // TODO: implement your API logic here
  return {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ message: 'Hello from ${API_NAME}' })
  };
}

// RapidAPI health check — no auth, confirms the service is alive
export async function healthHandler(_request: HttpRequest, _context: InvocationContext): Promise<HttpResponseInit> {
  return {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ status: 'ok' })
  };
}

app.http('${HANDLER_NAME}', {
  methods: ['GET'],
  authLevel: 'anonymous',
  handler: ${HANDLER_NAME}Handler
});

app.http('health', {
  methods: ['GET'],
  route: 'health',
  authLevel: 'anonymous',
  handler: healthHandler
});
TSFILE

# ──────────────────────────────────────────────
# DONE
# ──────────────────────────────────────────────
success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
success "Scaffolded: $API_NAME"
echo ""
echo "  📁 $API_NAME/"
echo "  ├── src/functions/$API_NAME.ts"
echo "  ├── host.json"
echo "  ├── local.settings.json"
echo "  ├── package.json"
echo "  ├── tsconfig.json"
echo "  ├── .env.example"
echo "  └── .env  ← add your RAPIDAPI_PROXY_SECRET here"
echo ""
warn "Next steps:"
echo "  1. Get proxy secret from RapidAPI: API Studio → $API_NAME → Gateway"
echo "  2. Add it to $API_NAME/.env"
echo "  3. Implement your logic in $API_NAME/src/functions/$API_NAME.ts"
echo "  4. Change directory into the folder with: cd $API_NAME"
echo "  5. npm install then npm run build"
echo "  6. Test locally with: npm start"
echo "  7. Create API on RapidAPI → get proxy secret enter it in ~/$API_NAME/.env file"
echo "  7. Run ./deploy.sh $API_NAME from root folder"
success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
