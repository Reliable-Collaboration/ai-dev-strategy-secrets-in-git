#!/usr/bin/env bash
set -euo pipefail

# Secrets in Git — Decrypt encrypted secret files
# Usage: ./secrets/decrypt.sh [name]
#   name (without extension) decrypts a single file: secrets/encrypted/{name}.enc.yaml
#   no arguments decrypts ALL .enc.yaml files in secrets/encrypted/

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Ensure unencrypted directory exists (needed on fresh clone) ---

mkdir -p "$SCRIPT_DIR/unencrypted"

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

# --- Collect files to decrypt ---

if [[ $# -ge 1 ]]; then
  # Single file mode
  ENCRYPTED="$SCRIPT_DIR/encrypted/${1}.enc.yaml"
  if [[ ! -f "$ENCRYPTED" ]]; then
    echo "Error: $ENCRYPTED not found"
    exit 1
  fi
  FILES=("$ENCRYPTED")
else
  # All files mode
  shopt -s nullglob
  FILES=("$SCRIPT_DIR"/encrypted/*.enc.yaml)
  shopt -u nullglob

  if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "No .enc.yaml files found in secrets/encrypted/"
    exit 1
  fi
fi

# --- Decrypt ---

for ENCRYPTED in "${FILES[@]}"; do
  BASENAME="$(basename "$ENCRYPTED" .enc.yaml)"
  PLAINTEXT="$SCRIPT_DIR/unencrypted/${BASENAME}.yaml"

  sops --decrypt \
    --input-type yaml \
    --output-type yaml \
    "$ENCRYPTED" \
    > "$PLAINTEXT"

  echo "Decrypted: secrets/encrypted/${BASENAME}.enc.yaml -> secrets/unencrypted/${BASENAME}.yaml"
done
