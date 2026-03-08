#!/usr/bin/env bash
set -euo pipefail

# Secrets in Git — Project Initialization Script
# This script scaffolds the secrets directory structure in a consuming project.
# Run from the project root: ./path/to/this/submodule/init.sh <your-age-public-key>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Validate we're in a git repository ---

if ! git rev-parse --is-inside-work-tree &> /dev/null; then
  echo "Error: Not inside a git repository."
  echo "Run this script from the root of your project's git repository."
  exit 1
fi

# --- Validate arguments ---

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <your-age-public-key>"
  echo ""
  echo "  your-age-public-key   Your age public key (starts with 'age1')"
  echo ""
  echo "If you don't have one yet, generate it with:"
  echo "  age-keygen -o ~/.config/sops/age/keys.txt"
  exit 1
fi

DEVELOPER_KEY="$1"

if [[ ! "$DEVELOPER_KEY" =~ ^age1 ]]; then
  echo "Error: Public key must start with 'age1'. Got: $DEVELOPER_KEY"
  echo "Make sure you're passing your PUBLIC key, not your private key."
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
chmod +x secrets/encrypt.sh secrets/decrypt.sh secrets/dotenv.sh

echo "Copied encrypt.sh, decrypt.sh, and dotenv.sh to secrets/"

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
echo "  4. Commit: git add .sops.yaml secrets/encrypted/ secrets/encrypt.sh secrets/decrypt.sh secrets/dotenv.sh .gitignore"
echo ""
