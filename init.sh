#!/usr/bin/env bash
set -euo pipefail

# Secrets in Git — Project Initialization Script
# This script scaffolds the secrets directory structure in a consuming project.
#
# Usage (zero-friction — auto-detects or creates your age key):
#   ./path/to/this/submodule/init.sh
#
# Or pass your public key explicitly:
#   ./path/to/this/submodule/init.sh age1your-public-key...
#
# Or pass the path to your key file:
#   ./path/to/this/submodule/init.sh ~/.config/sops/age/keys.txt

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Validate we're in a git repository ---

if ! git rev-parse --is-inside-work-tree &> /dev/null; then
  echo "Error: Not inside a git repository."
  echo "Run this script from the root of your project's git repository."
  exit 1
fi

# --- Check prerequisites ---

if ! command -v age-keygen &> /dev/null; then
  echo "Error: 'age' is not installed. Install it first:"
  echo "  apt install age  (Debian/Ubuntu)"
  echo "  brew install age  (macOS)"
  exit 1
fi

if ! command -v sops &> /dev/null; then
  echo "Error: 'sops' is not installed. Install it first:"
  echo "  https://github.com/getsops/sops/releases"
  exit 1
fi

# --- Resolve developer public key ---

DEFAULT_KEY_FILE="${SOPS_AGE_KEY_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/sops/age/keys.txt}"

extract_public_key() {
  local file="$1"
  grep "public key:" "$file" | head -1 | awk '{print $NF}'
}

if [[ $# -ge 1 ]]; then
  if [[ "$1" =~ ^age1 ]]; then
    # Direct public key provided (backward compatible)
    DEVELOPER_KEY="$1"
  elif [[ -f "$1" ]]; then
    # File path provided — extract public key from it
    DEVELOPER_KEY=$(extract_public_key "$1")
    if [[ -z "$DEVELOPER_KEY" ]]; then
      echo "Error: Could not extract a public key from $1"
      echo "The file should contain a line like: # public key: age1..."
      exit 1
    fi
    echo "Extracted public key from $1"
  else
    echo "Error: '$1' is not a valid public key (must start with 'age1') or file path."
    echo ""
    echo "Usage: $0 [age1-public-key | /path/to/keys.txt]"
    echo ""
    echo "Or run with no arguments to auto-detect your key."
    exit 1
  fi
else
  # No arguments — auto-detect or create key at the default location
  if [[ -f "$DEFAULT_KEY_FILE" ]]; then
    DEVELOPER_KEY=$(extract_public_key "$DEFAULT_KEY_FILE")
    if [[ -z "$DEVELOPER_KEY" ]]; then
      echo "Error: Found $DEFAULT_KEY_FILE but could not extract a public key from it."
      exit 1
    fi
    echo "Found existing age key: $DEVELOPER_KEY"
  else
    echo "No age key found at $DEFAULT_KEY_FILE — generating one..."
    mkdir -p "$(dirname "$DEFAULT_KEY_FILE")"
    age-keygen -o "$DEFAULT_KEY_FILE" 2>&1
    DEVELOPER_KEY=$(extract_public_key "$DEFAULT_KEY_FILE")
    if [[ -z "$DEVELOPER_KEY" ]]; then
      echo "Error: Failed to generate age key."
      exit 1
    fi
    echo ""
    echo "Generated new age key: $DEVELOPER_KEY"
    echo "Private key saved to: $DEFAULT_KEY_FILE"
  fi
fi

if [[ ! "$DEVELOPER_KEY" =~ ^age1 ]]; then
  echo "Error: Resolved key does not start with 'age1'. Got: $DEVELOPER_KEY"
  exit 1
fi

# --- Check for existing setup ---

if [[ -f ".sops.yaml" ]]; then
  echo "Error: .sops.yaml already exists in the project root."
  echo "This project appears to already be initialized. Aborting."
  exit 1
fi

# --- Create directory structure ---

mkdir -p secrets/unencrypted
mkdir -p secrets/encrypted

echo "Created secrets/unencrypted/ and secrets/encrypted/"

# --- Update .gitignore ---
# Each entry is checked and added independently to avoid gaps.

GITIGNORE_CHANGED=false

add_gitignore_entry() {
  local entry="$1"
  if [[ -f ".gitignore" ]]; then
    if ! grep -qxF "$entry" .gitignore; then
      echo "$entry" >> .gitignore
      GITIGNORE_CHANGED=true
    fi
  else
    echo "$entry" > .gitignore
    GITIGNORE_CHANGED=true
  fi
}

# Add a header comment if we're about to add entries and none exist yet
if [[ -f ".gitignore" ]]; then
  if ! grep -qxF "secrets/unencrypted/" .gitignore; then
    echo "" >> .gitignore
    echo "# Secrets in Git — plaintext secrets and .env files must never be committed" >> .gitignore
  fi
else
  echo "# Secrets in Git — plaintext secrets and .env files must never be committed" > .gitignore
fi

add_gitignore_entry "secrets/unencrypted/"
add_gitignore_entry ".env"
add_gitignore_entry ".env.*"

if [[ "$GITIGNORE_CHANGED" == true ]]; then
  echo "Updated .gitignore with secrets/unencrypted/, .env, and .env.*"
else
  echo ".gitignore already contains all required entries"
fi

# --- Generate break-glass master keypair ---

MASTER_OUTPUT=$(age-keygen 2>&1)
MASTER_PUBLIC=$(echo "$MASTER_OUTPUT" | grep "public key:" | awk '{print $NF}')
MASTER_PRIVATE=$(echo "$MASTER_OUTPUT" | grep "AGE-SECRET-KEY-")

echo ""
echo "============================================================"
echo "  BREAK-GLASS MASTER KEY — SAVE THIS NOW"
echo "============================================================"
echo ""
echo "  Private key (SAVE THIS SECURELY, it will not be shown again):"
echo ""
echo "  $MASTER_PRIVATE"
echo ""
echo "  Public key (stored in .sops.yaml):"
echo "  $MASTER_PUBLIC"
echo ""
echo "  Store the private key in a password manager, physical safe,"
echo "  or other secure external location. It must NOT be stored"
echo "  on a developer machine or in the repository."
echo ""
echo "============================================================"
echo ""

# --- Create .sops.yaml ---

cat > .sops.yaml << EOF
creation_rules:
  - path_regex: secrets/.*\.yaml\$
    age: >-
      ${DEVELOPER_KEY},
      ${MASTER_PUBLIC}
    # initial-developer, master (break-glass)
EOF

echo "Created .sops.yaml with your key and the master key"

# --- Copy convenience scripts ---

cp "$SCRIPT_DIR/scripts/encrypt.sh" secrets/encrypt.sh
cp "$SCRIPT_DIR/scripts/decrypt.sh" secrets/decrypt.sh
cp "$SCRIPT_DIR/scripts/dotenv.sh" secrets/dotenv.sh
cp "$SCRIPT_DIR/scripts/add-developer.sh" secrets/add-developer.sh
chmod +x secrets/encrypt.sh secrets/decrypt.sh secrets/dotenv.sh secrets/add-developer.sh

echo "Copied encrypt.sh, decrypt.sh, dotenv.sh, and add-developer.sh to secrets/"

# --- Create starter secrets file ---

cat > secrets/unencrypted/secrets.yaml << 'EOF'
# Secrets in Git — plaintext secrets
# Edit this file, then run ./secrets/encrypt.sh to encrypt.
# This file is .gitignored and must never be committed.
# Keys must be flat (no nesting) for .env compatibility.

# api_key: your-api-key-here
# database_password: your-db-password
EOF

echo "Created starter secrets/unencrypted/secrets.yaml"

# --- Done ---

echo ""
echo "Initialization complete. Next steps:"
echo ""
echo "  1. STORE THE BREAK-GLASS PRIVATE KEY (shown above) in a secure location"
echo "  2. Edit secrets/unencrypted/secrets.yaml with your secrets"
echo "  3. Run ./secrets/encrypt.sh to encrypt"
echo "  4. Commit: git add .sops.yaml secrets/encrypted/ secrets/*.sh .gitignore"
echo ""
