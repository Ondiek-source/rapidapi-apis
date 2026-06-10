#!/usr/bin/env bash
# =============================================================================
# generate-postman-collection.sh — Generate a Postman collection for an API
# Called automatically by deploy.sh after a successful deploy.
#
# Usage:  ./generate-postman-collection.sh <folder> <app-url>
#         ./generate-postman-collection.sh profanity-filter https://fn-rapidapi-profanity-filter.azurewebsites.net
#
# Outputs: <folder>/<folder>.postman_collection.json
# =============================================================================
set -euo pipefail

log()     { echo -e "\033[1;34m▶\033[0m  $*"; }
success() { echo -e "\033[1;32m✔\033[0m  $*"; }
warn()    { echo -e "\033[1;33m⚠\033[0m  $*"; }
die()     { echo -e "\033[1;31m✖\033[0m  $*" >&2; exit 1; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ -z "${1:-}" ]] && die "Usage: ./generate-postman-collection.sh <folder> <app-url>"
[[ -z "${2:-}" ]] && die "Usage: ./generate-postman-collection.sh <folder> <app-url>"

FOLDER="$1"
APP_URL="$2"
DIR="$ROOT_DIR/$FOLDER"
OUTPUT="$DIR/${FOLDER}.postman_collection.json"

[[ -d "$DIR" ]] || die "Folder '$FOLDER' not found."

# Derive display name: kebab-case → Title Case
DISPLAY_NAME=$(echo "$FOLDER" | sed -E 's/(^|-)([a-z])/\U\2/g' | sed 's/-/ /g')

# Unique IDs (deterministic from folder name, no external tools needed)
COLLECTION_ID=$(echo "$FOLDER-collection" | cksum | awk '{print $1}')
MAIN_ID=$(echo "$FOLDER-main" | cksum | awk '{print $1}')
HEALTH_ID=$(echo "$FOLDER-health" | cksum | awk '{print $1}')

log "Generating Postman collection for '$FOLDER'..."

cat > "$OUTPUT" << EOF
{
  "info": {
    "_postman_id": "${COLLECTION_ID}",
    "name": "${DISPLAY_NAME}",
    "description": "Auto-generated Postman collection for ${DISPLAY_NAME} API. Import this file into Postman and submit to the Postman API Network.",
    "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
  },
  "item": [
    {
      "name": "Filter Text",
      "event": [
        {
          "listen": "test",
          "script": {
            "exec": [
              "pm.test('Status code is 200', function () { pm.response.to.have.status(200); });",
              "pm.test('Response has clean field', function () { var json = pm.response.json(); pm.expect(json).to.have.property('clean'); });"
            ],
            "type": "text/javascript"
          }
        }
      ],
      "request": {
        "method": "GET",
        "header": [
          {
            "key": "x-rapidapi-proxy-secret",
            "value": "{{RAPIDAPI_PROXY_SECRET}}",
            "type": "text"
          }
        ],
        "url": {
          "raw": "${APP_URL}/api/${FOLDER}?text=This is a sample text to filter",
          "protocol": "https",
          "host": ["${APP_URL#https://}"],
          "path": ["api", "${FOLDER}"],
          "query": [
            {
              "key": "text",
              "value": "This is a sample text to filter"
            }
          ]
        },
        "description": "Analyze and clean text for profanity. Returns flagged words, severity level, cleaned text, word count, and character count."
      },
      "response": [],
      "_postman_id": "${MAIN_ID}"
    },
    {
      "name": "Health Check",
      "request": {
        "method": "GET",
        "header": [],
        "url": {
          "raw": "${APP_URL}/api/health",
          "protocol": "https",
          "host": ["${APP_URL#https://}"],
          "path": ["api", "health"]
        },
        "description": "Internal health check endpoint. Confirms the service is running."
      },
      "response": [],
      "_postman_id": "${HEALTH_ID}"
    }
  ],
  "variable": [
    {
      "key": "RAPIDAPI_PROXY_SECRET",
      "value": "",
      "type": "secret"
    }
  ]
}
EOF

success "Postman collection saved to: $FOLDER/${FOLDER}.postman_collection.json"
success "Next: Import into Postman → API Network → Submit for publishing"