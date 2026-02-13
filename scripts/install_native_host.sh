#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <native_host_binary_path> <chrome_extension_id>"
  exit 1
fi

BINARY_PATH="$1"
EXTENSION_ID="$2"
MANIFEST_DIR="${NATIVE_MESSAGING_HOST_DIR:-$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts}"
MANIFEST_PATH="$MANIFEST_DIR/com.usege.sync.host.json"

mkdir -p "$MANIFEST_DIR"

cat > "$MANIFEST_PATH" <<JSON
{
  "name": "com.usege.sync.host",
  "description": "usege native messaging host",
  "path": "$BINARY_PATH",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://$EXTENSION_ID/"
  ]
}
JSON

chmod 644 "$MANIFEST_PATH"

echo "Installed manifest at: $MANIFEST_PATH"
