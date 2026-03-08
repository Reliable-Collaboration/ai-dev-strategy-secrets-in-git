#!/usr/bin/env bash
set -euo pipefail

# Secrets in Git — Encrypt plaintext secret files
# Usage: ./secrets/encrypt.sh [name]
#   name (without extension) encrypts a single file: secrets/unencrypted/{name}.yaml
#   no arguments encrypts ALL .yaml files in secrets/unencrypted/

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

# --- Collect files to encrypt ---

if [[ $# -ge 1 ]]; then
  # Single file mode
  PLAINTEXT="$SCRIPT_DIR/unencrypted/${1}.yaml"
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

for PLAINTEXT in "${FILES[@]}"; do
  BASENAME="$(basename "$PLAINTEXT" .yaml)"
  ENCRYPTED="$SCRIPT_DIR/encrypted/${BASENAME}.enc.yaml"

  sops --encrypt \
    --input-type yaml \
    --output-type yaml \
    "$PLAINTEXT" \
    > "$ENCRYPTED"

  echo "Encrypted: secrets/unencrypted/${BASENAME}.yaml -> secrets/encrypted/${BASENAME}.enc.yaml"
done
