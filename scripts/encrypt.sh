#!/usr/bin/env bash
set -euo pipefail

# Secrets in Git — Encrypt plaintext secret files
# Usage: ./secrets/encrypt.sh [--force] [name]
#   name (without extension) encrypts a single file: secrets/unencrypted/{name}.yaml
#   no arguments encrypts all CHANGED .yaml files in secrets/unencrypted/
#   --force re-encrypts even if unchanged (needed after key rotation)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECKSUMS_FILE="$SCRIPT_DIR/unencrypted/.checksums"

# --- Parse flags ---

FORCE=false
NAME=""
for arg in "$@"; do
  case "$arg" in
    --force|-f) FORCE=true ;;
    *) NAME="$arg" ;;
  esac
done

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

# --- Collect files to encrypt ---

if [[ -n "$NAME" ]]; then
  # Single file mode
  PLAINTEXT="$SCRIPT_DIR/unencrypted/${NAME}.yaml"
  if [[ ! -f "$PLAINTEXT" ]]; then
    echo "Error: $PLAINTEXT not found"
    exit 1
  fi
  FILES=("$PLAINTEXT")
else
  # All files mode
  shopt -s nullglob
  FILES=("$SCRIPT_DIR"/unencrypted/*.yaml)
  shopt -u nullglob

  if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "No .yaml files found in secrets/unencrypted/"
    exit 1
  fi
fi

# --- Encrypt ---

CHANGED=0
SKIPPED=0

for PLAINTEXT in "${FILES[@]}"; do
  BASENAME="$(basename "$PLAINTEXT" .yaml)"
  ENCRYPTED="$SCRIPT_DIR/encrypted/${BASENAME}.enc.yaml"
  CURRENT_HASH=$(sha256sum "$PLAINTEXT" | awk '{print $1}')

  # Skip if the plaintext hasn't changed since last encryption
  if [[ "$FORCE" == false && -f "$ENCRYPTED" ]]; then
    STORED_HASH=""
    if [[ -f "$CHECKSUMS_FILE" ]]; then
      STORED_HASH=$(awk -v name="${BASENAME}.yaml" '$2 == name {print $1}' "$CHECKSUMS_FILE")
    fi
    if [[ -n "$STORED_HASH" && "$CURRENT_HASH" == "$STORED_HASH" ]]; then
      echo "Unchanged: ${BASENAME}.yaml (skipped)"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
  fi

  sops --encrypt \
    --input-type yaml \
    --output-type yaml \
    "$PLAINTEXT" \
    > "$ENCRYPTED"

  # Store the checksum of the plaintext we just encrypted
  if [[ -f "$CHECKSUMS_FILE" ]]; then
    awk -v name="${BASENAME}.yaml" '$2 != name' "$CHECKSUMS_FILE" > "${CHECKSUMS_FILE}.tmp"
    mv "${CHECKSUMS_FILE}.tmp" "$CHECKSUMS_FILE"
  fi
  echo "$CURRENT_HASH  ${BASENAME}.yaml" >> "$CHECKSUMS_FILE"

  echo "Encrypted: secrets/unencrypted/${BASENAME}.yaml -> secrets/encrypted/${BASENAME}.enc.yaml"
  CHANGED=$((CHANGED + 1))
done

if [[ $SKIPPED -gt 0 ]]; then
  echo ""
  echo "$CHANGED file(s) encrypted, $SKIPPED unchanged file(s) skipped."
  if [[ "$FORCE" == false ]]; then
    echo "Use --force to re-encrypt all files (e.g., after key rotation)."
  fi
fi
