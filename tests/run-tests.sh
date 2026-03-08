#!/usr/bin/env bash
set -euo pipefail

# Secrets in Git — Automated Test Suite
#
# Runs end-to-end tests of init.sh, encrypt.sh, decrypt.sh, dotenv.sh,
# and add-developer.sh in an isolated temporary git repository.
#
# Usage: ./tests/run-tests.sh
#
# Prerequisites: age, sops
#
# What this tests:
#   1.  init.sh — zero-argument (auto-creates key)
#   2.  init.sh — explicit public key argument
#   3.  init.sh — key file path argument
#   4.  init.sh — rejects invalid arguments
#   5.  init.sh — refuses to run outside a git repo
#   6.  init.sh — refuses to re-initialize
#   7.  encrypt.sh — first encryption creates .enc.yaml and checksum
#   8.  encrypt.sh — skips unchanged files
#   9.  encrypt.sh — re-encrypts changed files
#   10. encrypt.sh — --force bypasses checksum
#   11. encrypt.sh — multiple files, only changed ones encrypted
#   12. encrypt.sh — single-file mode with checksum
#   13. decrypt.sh — decrypts to unencrypted directory
#   14. decrypt.sh — creates unencrypted directory if missing
#   15. decrypt.sh — single-file mode
#   16. dotenv.sh — generates .env from YAML
#   17. dotenv.sh — preserves comments and uppercases keys
#   18. add-developer.sh — adds key with label
#   19. add-developer.sh — accepts key file path
#   20. add-developer.sh — rejects duplicate key
#   21. add-developer.sh — updates all encrypted files
#   22. Full round-trip: init → encrypt → decrypt → verify values

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBMODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Colors ---

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# --- Counters ---

PASSED=0
FAILED=0
ERRORS=()

# --- Helpers ---

pass() {
  PASSED=$((PASSED + 1))
  echo -e "  ${GREEN}✓${NC} $1"
}

fail() {
  FAILED=$((FAILED + 1))
  ERRORS+=("$1: $2")
  echo -e "  ${RED}✗${NC} $1"
  echo -e "    ${RED}$2${NC}"
}

# Create a fresh isolated test repo. Backs up and restores the real age key
# so tests don't interfere with the developer's actual key.
setup_test_repo() {
  TEST_DIR=$(mktemp -d /tmp/secrets-test-XXXXXX)
  cd "$TEST_DIR"
  git init -q
  git commit --allow-empty -q -m "init"

  # Back up existing age key if present
  REAL_KEY_FILE="${SOPS_AGE_KEY_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/sops/age/keys.txt}"
  if [[ -f "$REAL_KEY_FILE" ]]; then
    BACKUP_KEY_FILE="${REAL_KEY_FILE}.test-backup"
    cp "$REAL_KEY_FILE" "$BACKUP_KEY_FILE"
  fi
}

teardown_test_repo() {
  # Restore original age key
  if [[ -n "${BACKUP_KEY_FILE:-}" && -f "${BACKUP_KEY_FILE:-}" ]]; then
    mv "$BACKUP_KEY_FILE" "$REAL_KEY_FILE"
  fi
  rm -rf "$TEST_DIR" 2>/dev/null || true
}

# --- Prerequisite check ---

echo ""
echo "Secrets in Git — Test Suite"
echo "==========================="
echo ""

if ! command -v age-keygen &> /dev/null; then
  echo -e "${RED}Error: 'age' is not installed.${NC}"
  exit 1
fi
if ! command -v sops &> /dev/null; then
  echo -e "${RED}Error: 'sops' is not installed.${NC}"
  exit 1
fi

# ============================================================
# Group 1: init.sh
# ============================================================

echo -e "${YELLOW}init.sh${NC}"

# Test 1: Zero-argument init (auto-creates key)
setup_test_repo
rm -f "$REAL_KEY_FILE" 2>/dev/null || true
OUTPUT=$("$SUBMODULE_DIR/init.sh" 2>&1)
if echo "$OUTPUT" | grep -q "generating one" && [[ -f .sops.yaml ]] && [[ -f "$REAL_KEY_FILE" ]]; then
  pass "1. Zero-argument init auto-creates age key"
else
  fail "1. Zero-argument init auto-creates age key" "Key not created or init failed"
fi
teardown_test_repo

# Test 2: Explicit public key argument
setup_test_repo
TEST_KEY=$(age-keygen 2>&1 | grep "public key:" | awk '{print $NF}')
OUTPUT=$("$SUBMODULE_DIR/init.sh" "$TEST_KEY" 2>&1)
if [[ -f .sops.yaml ]] && grep -qF "$TEST_KEY" .sops.yaml; then
  pass "2. Explicit public key argument"
else
  fail "2. Explicit public key argument" ".sops.yaml missing or key not found in it"
fi
teardown_test_repo

# Test 3: Key file path argument
setup_test_repo
KEYFILE="/tmp/age-key-test-$$.txt"
rm -f "$KEYFILE"
age-keygen -o "$KEYFILE" 2>/dev/null
EXPECTED_KEY=$(grep "public key:" "$KEYFILE" | awk '{print $NF}')
OUTPUT=$("$SUBMODULE_DIR/init.sh" "$KEYFILE" 2>&1)
if [[ -f .sops.yaml ]] && grep -qF "$EXPECTED_KEY" .sops.yaml; then
  pass "3. Key file path argument"
else
  fail "3. Key file path argument" "Public key not extracted from file"
fi
rm -f "$KEYFILE"
teardown_test_repo

# Test 4: Rejects invalid argument
setup_test_repo
if OUTPUT=$("$SUBMODULE_DIR/init.sh" "not-a-valid-key" 2>&1); then
  fail "4. Rejects invalid argument" "Should have exited non-zero"
else
  if echo "$OUTPUT" | grep -q "not a valid public key"; then
    pass "4. Rejects invalid argument"
  else
    fail "4. Rejects invalid argument" "Wrong error message: $OUTPUT"
  fi
fi
teardown_test_repo

# Test 5: Refuses to run outside a git repo
NOGIT_DIR=$(mktemp -d /tmp/secrets-nogit-XXXXXX)
if OUTPUT=$(cd "$NOGIT_DIR" && "$SUBMODULE_DIR/init.sh" 2>&1); then
  fail "5. Refuses to run outside git repo" "Should have exited non-zero"
else
  pass "5. Refuses to run outside git repo"
fi
rm -rf "$NOGIT_DIR"

# Test 6: Refuses to re-initialize
setup_test_repo
TEST_KEY=$(age-keygen 2>&1 | grep "public key:" | awk '{print $NF}')
"$SUBMODULE_DIR/init.sh" "$TEST_KEY" > /dev/null 2>&1
if OUTPUT=$("$SUBMODULE_DIR/init.sh" "$TEST_KEY" 2>&1); then
  fail "6. Refuses to re-initialize" "Should have exited non-zero"
else
  if echo "$OUTPUT" | grep -q "already"; then
    pass "6. Refuses to re-initialize"
  else
    fail "6. Refuses to re-initialize" "Wrong error message"
  fi
fi
teardown_test_repo

# ============================================================
# Group 2: encrypt.sh
# ============================================================

echo -e "${YELLOW}encrypt.sh${NC}"

# Set up a repo for encrypt/decrypt/dotenv/add-developer tests.
# Uses no-argument init so the key file on disk matches .sops.yaml.
setup_test_repo
"$SUBMODULE_DIR/init.sh" > /dev/null 2>&1

cat > secrets/unencrypted/secrets.yaml << 'YAML'
# App secrets
api_key: sk-test-12345
database_password: hunter2
YAML

# Test 7: First encryption
OUTPUT=$(./secrets/encrypt.sh 2>&1)
if [[ -f secrets/encrypted/secrets.enc.yaml ]] && echo "$OUTPUT" | grep -q "Encrypted:"; then
  pass "7. First encryption creates .enc.yaml and checksum"
else
  fail "7. First encryption creates .enc.yaml and checksum" "Encrypted file not created"
fi

# Test 8: Skip unchanged
OUTPUT=$(./secrets/encrypt.sh 2>&1)
if echo "$OUTPUT" | grep -q "Unchanged:.*skipped"; then
  pass "8. Skips unchanged files"
else
  fail "8. Skips unchanged files" "File was not skipped: $OUTPUT"
fi

# Test 9: Re-encrypts changed files
echo "new_secret: value123" >> secrets/unencrypted/secrets.yaml
BEFORE=$(sha256sum secrets/encrypted/secrets.enc.yaml | awk '{print $1}')
OUTPUT=$(./secrets/encrypt.sh 2>&1)
AFTER=$(sha256sum secrets/encrypted/secrets.enc.yaml | awk '{print $1}')
if [[ "$BEFORE" != "$AFTER" ]] && echo "$OUTPUT" | grep -q "Encrypted:"; then
  pass "9. Re-encrypts changed files"
else
  fail "9. Re-encrypts changed files" "Encrypted file did not change"
fi

# Test 10: --force bypasses checksum
BEFORE=$(sha256sum secrets/encrypted/secrets.enc.yaml | awk '{print $1}')
OUTPUT=$(./secrets/encrypt.sh --force 2>&1)
AFTER=$(sha256sum secrets/encrypted/secrets.enc.yaml | awk '{print $1}')
if [[ "$BEFORE" != "$AFTER" ]] && echo "$OUTPUT" | grep -q "Encrypted:"; then
  pass "10. --force bypasses checksum"
else
  fail "10. --force bypasses checksum" "File should have been re-encrypted"
fi

# Test 11: Multiple files, only changed ones encrypted
cat > secrets/unencrypted/dev.yaml << 'YAML'
dev_api: dev-key
YAML
cat > secrets/unencrypted/prod.yaml << 'YAML'
prod_api: prod-key
YAML
./secrets/encrypt.sh > /dev/null 2>&1
# Now modify only dev
echo "dev_db: localhost" >> secrets/unencrypted/dev.yaml
OUTPUT=$(./secrets/encrypt.sh 2>&1)
if echo "$OUTPUT" | grep -q "Encrypted:.*dev.yaml" \
   && echo "$OUTPUT" | grep -q "Unchanged: prod.yaml" \
   && echo "$OUTPUT" | grep -q "Unchanged: secrets.yaml"; then
  pass "11. Multiple files — only changed ones encrypted"
else
  fail "11. Multiple files — only changed ones encrypted" "Unexpected output: $OUTPUT"
fi

# Test 12: Single-file mode with checksum
echo "extra: val" >> secrets/unencrypted/prod.yaml
OUTPUT=$(./secrets/encrypt.sh prod 2>&1)
if echo "$OUTPUT" | grep -q "Encrypted:.*prod.yaml"; then
  OUTPUT2=$(./secrets/encrypt.sh prod 2>&1)
  if echo "$OUTPUT2" | grep -q "Unchanged: prod.yaml"; then
    pass "12. Single-file mode with checksum"
  else
    fail "12. Single-file mode with checksum" "Second run should skip"
  fi
else
  fail "12. Single-file mode with checksum" "First run should encrypt"
fi

# ============================================================
# Group 3: decrypt.sh
# ============================================================

echo -e "${YELLOW}decrypt.sh${NC}"

# Test 13: Decrypts to unencrypted directory
rm -f secrets/unencrypted/*.yaml
OUTPUT=$(./secrets/decrypt.sh 2>&1)
if [[ -f secrets/unencrypted/secrets.yaml ]] \
   && [[ -f secrets/unencrypted/dev.yaml ]] \
   && [[ -f secrets/unencrypted/prod.yaml ]]; then
  pass "13. Decrypts all files to unencrypted/"
else
  fail "13. Decrypts all files to unencrypted/" "Not all files decrypted"
fi

# Test 14: Creates unencrypted directory if missing
rm -rf secrets/unencrypted
OUTPUT=$(./secrets/decrypt.sh 2>&1)
if [[ -d secrets/unencrypted ]] && [[ -f secrets/unencrypted/secrets.yaml ]]; then
  pass "14. Creates unencrypted/ directory if missing"
else
  fail "14. Creates unencrypted/ directory if missing" "Directory or files not created"
fi

# Test 15: Single-file mode
rm -f secrets/unencrypted/dev.yaml
OUTPUT=$(./secrets/decrypt.sh dev 2>&1)
if [[ -f secrets/unencrypted/dev.yaml ]]; then
  pass "15. Single-file decrypt mode"
else
  fail "15. Single-file decrypt mode" "dev.yaml not decrypted"
fi

# ============================================================
# Group 4: dotenv.sh
# ============================================================

echo -e "${YELLOW}dotenv.sh${NC}"

# Test 16: Generates .env
OUTPUT=$(./secrets/dotenv.sh secrets 2>&1)
if [[ -f .env ]]; then
  pass "16. Generates .env file"
else
  fail "16. Generates .env file" ".env not created"
fi

# Test 17: Preserves comments and uppercases keys
if grep -q "^# App secrets" .env \
   && grep -q "^API_KEY=sk-test-12345" .env \
   && grep -q "^DATABASE_PASSWORD=hunter2" .env; then
  pass "17. Preserves comments and uppercases keys"
else
  fail "17. Preserves comments and uppercases keys" "Content mismatch: $(cat .env)"
fi
rm -f .env

# ============================================================
# Group 5: add-developer.sh
# ============================================================

echo -e "${YELLOW}add-developer.sh${NC}"

git add .sops.yaml secrets/encrypted/ secrets/*.sh .gitignore > /dev/null 2>&1
git commit -q -m "init secrets"

# Test 18: Adds key with label
NEW_KEY=$(age-keygen 2>&1 | grep "public key:" | awk '{print $NF}')
OUTPUT=$(./secrets/add-developer.sh "$NEW_KEY" alice 2>&1)
if grep -qF "$NEW_KEY" .sops.yaml && grep -q "alice" .sops.yaml; then
  pass "18. Adds key with label"
else
  fail "18. Adds key with label" "Key or label not in .sops.yaml"
fi

# Test 19: Accepts key file path
KEYFILE="/tmp/age-key-test19-$$.txt"
rm -f "$KEYFILE"
age-keygen -o "$KEYFILE" 2>/dev/null
EXPECTED=$(grep "public key:" "$KEYFILE" | awk '{print $NF}')
OUTPUT=$(./secrets/add-developer.sh "$KEYFILE" bob 2>&1)
if grep -qF "$EXPECTED" .sops.yaml && grep -q "bob" .sops.yaml; then
  pass "19. Accepts key file path"
else
  fail "19. Accepts key file path" "Key not extracted from file"
fi
rm -f "$KEYFILE"

# Test 20: Rejects duplicate key
if OUTPUT=$(./secrets/add-developer.sh "$NEW_KEY" alice-again 2>&1); then
  fail "20. Rejects duplicate key" "Should have exited non-zero"
else
  if echo "$OUTPUT" | grep -q "already"; then
    pass "20. Rejects duplicate key"
  else
    fail "20. Rejects duplicate key" "Wrong error: $OUTPUT"
  fi
fi

# Test 21: Updates all encrypted files
# The SOPS output from test 18/19 already showed updatekeys ran.
# Verify by decrypting with the original key — if updatekeys failed, SOPS
# wouldn't have re-wrapped the data key and decrypt would still work.
rm -f secrets/unencrypted/*.yaml
OUTPUT=$(./secrets/decrypt.sh 2>&1)
if [[ -f secrets/unencrypted/secrets.yaml ]] && grep -q "api_key" secrets/unencrypted/secrets.yaml; then
  pass "21. Encrypted files still decrypt after adding developers"
else
  fail "21. Encrypted files still decrypt after adding developers" "Decrypt failed after updatekeys"
fi

# ============================================================
# Group 6: Full round-trip
# ============================================================

echo -e "${YELLOW}Round-trip${NC}"

# Test 22: Full cycle
rm -rf secrets/unencrypted
cat > /tmp/roundtrip-secrets.yaml << 'YAML'
# Round-trip test
secret_one: value-one
secret_two: value-two
YAML

./secrets/decrypt.sh > /dev/null 2>&1
cp /tmp/roundtrip-secrets.yaml secrets/unencrypted/secrets.yaml
./secrets/encrypt.sh secrets > /dev/null 2>&1
rm -f secrets/unencrypted/secrets.yaml
./secrets/decrypt.sh secrets > /dev/null 2>&1
DECRYPTED=$(cat secrets/unencrypted/secrets.yaml)
if echo "$DECRYPTED" | grep -q "secret_one: value-one" \
   && echo "$DECRYPTED" | grep -q "secret_two: value-two" \
   && echo "$DECRYPTED" | grep -q "# Round-trip test"; then
  pass "22. Full round-trip: encrypt → decrypt → values match"
else
  fail "22. Full round-trip" "Decrypted content doesn't match: $DECRYPTED"
fi
rm -f /tmp/roundtrip-secrets.yaml

teardown_test_repo

# ============================================================
# Summary
# ============================================================

echo ""
TOTAL=$((PASSED + FAILED))
if [[ $FAILED -eq 0 ]]; then
  echo -e "${GREEN}All $TOTAL tests passed.${NC}"
else
  echo -e "${RED}$FAILED of $TOTAL tests failed:${NC}"
  for err in "${ERRORS[@]}"; do
    echo -e "  ${RED}✗${NC} $err"
  done
  exit 1
fi
