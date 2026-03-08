#!/usr/bin/env bash
set -euo pipefail

# Secrets in Git — Convert a decrypted YAML secrets file to .env
# Usage: ./secrets/dotenv.sh [name]
#   name defaults to "secrets", reads secrets/unencrypted/{name}.yaml
#   outputs .env to the project root

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Verify .gitignore protections ---

if ! git -C "$PROJECT_ROOT" check-ignore -q "$SCRIPT_DIR/unencrypted/" 2>/dev/null; then
  echo "ERROR: secrets/unencrypted/ is NOT ignored by .gitignore"
  echo ""
  echo "Refusing to proceed — plaintext secrets could be accidentally committed."
  echo "Add the following line to your .gitignore:"
  echo "  secrets/unencrypted/"
  exit 1
fi

if ! git -C "$PROJECT_ROOT" check-ignore -q "$PROJECT_ROOT/.env" 2>/dev/null; then
  echo "ERROR: .env is NOT ignored by .gitignore"
  echo ""
  echo "Refusing to proceed — .env files could be accidentally committed."
  echo "Add the following lines to your .gitignore:"
  echo "  .env"
  echo "  .env.*"
  exit 1
fi

# --- Convert YAML to .env ---

NAME="${1:-secrets}"
INPUT="$SCRIPT_DIR/unencrypted/${NAME}.yaml"
OUTPUT="$PROJECT_ROOT/.env"

if [[ ! -f "$INPUT" ]]; then
  echo "Error: $INPUT not found"
  echo "Have you run ./secrets/decrypt.sh first?"
  exit 1
fi

awk '
  /^[[:space:]]*$/ { print; next }
  /^[[:space:]]*#/ { print; next }
  /^[a-zA-Z_][a-zA-Z0-9_-]*[[:space:]]*:/ {
    key = $0
    sub(/[[:space:]]*:.*/, "", key)
    gsub(/-/, "_", key)
    val = $0
    sub(/^[^:]*:[[:space:]]*/, "", val)
    # Strip surrounding quotes from YAML
    if (val ~ /^".*"$/ || val ~ /^'\''.*'\''$/) {
      val = substr(val, 2, length(val) - 2)
    }
    # Uppercase the key
    key = toupper(key)
    # Quote values that contain spaces, #, or = characters
    if (val ~ /[[:space:]#=]/) {
      printf "%s=\"%s\"\n", key, val
    } else {
      printf "%s=%s\n", key, val
    }
    next
  }
  {
    # Lines that do not match (e.g. nested YAML) — pass through as warnings
    print "# WARN: could not convert: " $0
  }
' "$INPUT" > "$OUTPUT"

echo "Generated .env from secrets/unencrypted/${NAME}.yaml"
