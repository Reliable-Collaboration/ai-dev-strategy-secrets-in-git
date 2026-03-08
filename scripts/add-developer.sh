#!/usr/bin/env bash
set -euo pipefail

# Secrets in Git — Add a developer's public key and update all encrypted files
# Usage: ./secrets/add-developer.sh <age-public-key-or-keyfile> [label]
#   age-public-key   The new developer's public key (starts with 'age1')
#   keyfile          Path to the developer's age key file (public key is extracted)
#   label            Optional name for the .sops.yaml comment

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOPS_FILE="$PROJECT_ROOT/.sops.yaml"

# --- Validate arguments ---

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <age-public-key-or-keyfile> [label]"
  echo ""
  echo "  age-public-key   Public key (starts with 'age1')"
  echo "  keyfile          Path to an age key file (public key is extracted)"
  echo "  label            Optional name/label for the comment in .sops.yaml"
  echo ""
  echo "Examples:"
  echo "  $0 age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p alice"
  echo "  $0 ~/alice-keys.txt alice"
  exit 1
fi

# --- Resolve the public key ---

if [[ "$1" =~ ^age1 ]]; then
  NEW_KEY="$1"
elif [[ -f "$1" ]]; then
  NEW_KEY=$(grep "public key:" "$1" | head -1 | awk '{print $NF}')
  if [[ -z "$NEW_KEY" ]]; then
    echo "Error: Could not extract a public key from $1"
    echo "The file should contain a line like: # public key: age1..."
    exit 1
  fi
  echo "Extracted public key from $1"
else
  echo "Error: '$1' is not a valid public key (must start with 'age1') or file path."
  exit 1
fi

LABEL="${2:-}"

if [[ ! "$NEW_KEY" =~ ^age1 ]]; then
  echo "Error: Resolved key does not start with 'age1'. Got: $NEW_KEY"
  exit 1
fi

# --- Validate environment ---

if [[ ! -f "$SOPS_FILE" ]]; then
  echo "Error: $SOPS_FILE not found."
  echo "Has this project been initialized with init.sh?"
  exit 1
fi

if grep -qF "$NEW_KEY" "$SOPS_FILE"; then
  echo "Error: This key is already in .sops.yaml"
  exit 1
fi

if ! command -v sops &> /dev/null; then
  echo "Error: 'sops' is not installed."
  exit 1
fi

# --- Add key to .sops.yaml ---

# Find the last age1 line, add a trailing comma if needed, then insert the new key after it.
awk -v new_key="$NEW_KEY" '
{
  lines[NR] = $0
  if ($0 ~ /age1/) last = NR
}
END {
  for (i = 1; i <= NR; i++) {
    if (i == last) {
      line = lines[i]
      if (line !~ /,[[:space:]]*$/) {
        sub(/[[:space:]]*$/, ",", line)
      }
      print line
      match(lines[i], /^[[:space:]]+/)
      indent = substr(lines[i], 1, RLENGTH)
      print indent new_key
    } else {
      print lines[i]
    }
  }
}' "$SOPS_FILE" > "${SOPS_FILE}.tmp" && mv "${SOPS_FILE}.tmp" "$SOPS_FILE"

# Update the comment line if a label was provided
if [[ -n "$LABEL" ]]; then
  if grep -q "# .*, master" "$SOPS_FILE"; then
    sed -i "s/# \(.*\), master/# \1, ${LABEL}, master/" "$SOPS_FILE"
  fi
fi

echo "Added key to .sops.yaml"

# --- Run sops updatekeys on all encrypted files ---

ENCRYPTED_DIR="$SCRIPT_DIR/encrypted"

if [[ ! -d "$ENCRYPTED_DIR" ]]; then
  echo "No encrypted/ directory found. No files to update."
  exit 0
fi

FOUND=false
for f in "$ENCRYPTED_DIR"/*.enc.yaml; do
  [[ -f "$f" ]] || continue
  FOUND=true
  echo "Updating keys for $(basename "$f")..."
  sops updatekeys -y "$f"
done

if [[ "$FOUND" == false ]]; then
  echo "No .enc.yaml files found in encrypted/. Nothing to update."
else
  echo ""
  echo "Done. Commit and push:"
  echo "  git add .sops.yaml secrets/encrypted/"
  echo "  git commit -m \"Add ${LABEL:-new developer} to secrets recipients\""
  echo "  git push"
fi
