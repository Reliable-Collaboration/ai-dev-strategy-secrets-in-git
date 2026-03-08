---
title: "Secrets in Git"
---

# Secrets in Git

> **Intentional Specification**
> This document follows [Intentional Specification](../intentional-specification/intentional-specification.md). Design history: [ICD](./secrets-in-git-ICD.md). **Completeness: Working Draft** — 0 open questions

## What This Is

**Secrets in Git** is a strategy for storing encrypted secrets directly in a git repository using [SOPS](https://github.com/getsops/sops) and [age](https://github.com/FiloSottile/age). It acts as a simple, version-controlled key vault for small teams.

Each developer has their own age keypair. All public keys are committed to the repository in a `.sops.yaml` configuration file. Any developer whose public key is listed can decrypt the secrets. A break-glass master key provides recovery if all developers lose their keys.

This strategy is distributed as a git submodule and pulled into projects that adopt it. The submodule contains this documentation and an `init.sh` script that scaffolds the required file structure in the consuming project.

---

## Prerequisites

### age

[age](https://github.com/FiloSottile/age) is a simple file encryption tool. On Ubuntu 22.04+, it is available in the standard repositories:

```bash
sudo apt update && sudo apt install -y age
```

Verify the installation:

```bash
age --version
```

### SOPS

[SOPS](https://github.com/getsops/sops) is not available in the Ubuntu repositories. Install it from the GitHub releases page by downloading the `.deb` package:

```bash
# Download the latest .deb (amd64)
SOPS_LATEST=$(curl -s https://api.github.com/repos/getsops/sops/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
curl -Lo /tmp/sops.deb "https://github.com/getsops/sops/releases/download/${SOPS_LATEST}/sops_${SOPS_LATEST#v}_amd64.deb"
sudo dpkg -i /tmp/sops.deb
rm /tmp/sops.deb
```

Or download a specific version directly (e.g., v3.12.1):

```bash
curl -Lo /tmp/sops.deb https://github.com/getsops/sops/releases/download/v3.12.1/sops_3.12.1_amd64.deb
sudo dpkg -i /tmp/sops.deb
rm /tmp/sops.deb
```

For arm64 systems, replace `amd64` with `arm64` in the URLs above.

Verify the installation:

```bash
sops --version
```

---

## File Structure

After initialization, the consuming project will have:

```
project-root/
  .sops.yaml                  # SOPS config with all recipient public keys (committed)
  .env                        # generated from secrets, .gitignored — never committed
  secrets/
    unencrypted/              # .gitignored — never committed
      secrets.yaml            # plaintext secrets (or per-environment: dev.yaml, prod.yaml)
    encrypted/                # committed to git
      secrets.enc.yaml        # SOPS-encrypted secrets (or dev.enc.yaml, prod.enc.yaml)
    encrypt.sh                # encrypts all files in unencrypted/
    decrypt.sh                # decrypts all files in encrypted/
    dotenv.sh                 # generates .env from a decrypted YAML file
```

The `secrets/unencrypted/` directory and all `.env` files (`.env`, `.env.*`) are `.gitignored` and must never be committed. The `secrets/encrypted/` directory is committed and contains only SOPS-encrypted files.

### .gitignore

The init script adds the following entries to `.gitignore`:

```
secrets/unencrypted/
.env
.env.*
```

This covers `.env`, `.env.local`, `.env.production`, `.env.dev`, and any other dotenv variant.

### Multiple Environments

Use one YAML file per environment. The naming convention is:

| Environment | Plaintext | Encrypted |
|-------------|-----------|-----------|
| Default | `secrets.yaml` | `secrets.enc.yaml` |
| Development | `dev.yaml` | `dev.enc.yaml` |
| Staging | `staging.yaml` | `staging.enc.yaml` |
| Production | `prod.yaml` | `prod.enc.yaml` |

All three scripts accept an optional name argument (without extension) to operate on a single file. With no arguments, `encrypt.sh` and `decrypt.sh` process **all** files in their respective directories. The `dotenv.sh` script defaults to `secrets` if no name is given.

```bash
# Single file (recommended for daily use — avoids re-encrypting unchanged files)
./secrets/encrypt.sh dev
./secrets/decrypt.sh dev
./secrets/dotenv.sh dev

# All files (useful after key rotation or initial setup)
./secrets/encrypt.sh
./secrets/decrypt.sh
```

---

## Getting Started: Initializing Your Secrets and Storing Your Break-Glass Key as the Initial Developer

This walkthrough is for the first person setting up secrets in a project. By the end, you will have a working secrets directory, a break-glass recovery key stored safely, and your own developer key configured.

### Step 1: Install prerequisites

Make sure `age` and `sops` are installed:

```bash
age --version
sops --version
```

### Step 2: Generate your developer key (if you don't already have one)

If you haven't used age before, generate your personal keypair:

```bash
age-keygen -o ~/.config/sops/age/keys.txt
```

This prints your public key to the terminal:

```
Public key: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
```

Save this public key — you'll need it in the next step. If you already have a key, find your public key with:

```bash
grep "public key:" ~/.config/sops/age/keys.txt
```

### Step 3: Run the init script

From the project root, run the init script provided by this submodule. Pass your public key as an argument:

```bash
./dev-strategies-tooling/ai-dev-strategy-secrets-in-git/init.sh age1ql3z7hjy...your-public-key
```

The script will:

1. Create `secrets/unencrypted/` and `secrets/encrypted/`
2. Add `secrets/unencrypted/`, `.env`, and `.env.*` to `.gitignore`
3. Generate a break-glass master keypair
4. Create `.sops.yaml` with both your public key and the master public key
5. Copy `encrypt.sh`, `decrypt.sh`, and `dotenv.sh` into `secrets/`
6. Create a starter `secrets/unencrypted/secrets.yaml`

### Step 4: Store the break-glass private key

The init script prints the break-glass master private key to your terminal. It looks like:

```
AGE-SECRET-KEY-1QQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQ
```

**Store this key in a secure external location immediately.** Good options:

- A team password manager (1Password, Bitwarden, etc.)
- A physical safe
- A printed copy in a secure location

This is the only time this key is displayed. It is not saved anywhere on your machine or in the repository. If all developers lose their keys, this is the only way to recover the secrets.

### Step 5: Add your first secrets and commit

Edit the starter secrets file:

```bash
vim secrets/unencrypted/secrets.yaml
```

Encrypt it:

```bash
./secrets/encrypt.sh
```

Commit the encrypted file, `.sops.yaml`, and the scripts:

```bash
git add .sops.yaml secrets/encrypted/ secrets/encrypt.sh secrets/decrypt.sh secrets/dotenv.sh .gitignore
git commit -m "Initialize encrypted secrets"
```

You're done. The secrets are now version-controlled and encrypted. Only you and the break-glass key can decrypt them.

---

## How-To: Adding a New Developer

This walkthrough is for an existing developer who needs to grant a new team member access to the secrets.

### What the new developer does

1. Install `age` and `sops` (see [Prerequisites](#prerequisites))

2. Generate their keypair (if they don't already have one):

   ```bash
   age-keygen -o ~/.config/sops/age/keys.txt
   ```

3. Send their public key (`age1...`) to an existing developer via any channel — it is safe to share publicly

### What the existing developer does

1. Add the new developer's public key to `.sops.yaml`:

   ```yaml
   creation_rules:
     - path_regex: secrets/.*\.yaml$
       age: >-
         age1existing...,
         age1newdev...,
         age1master...
   ```

2. Re-encrypt the secrets so the new developer can decrypt them:

   ```bash
   sops updatekeys secrets/encrypted/secrets.enc.yaml
   ```

   Repeat for each encrypted file if you have more than one.

3. Commit and push:

   ```bash
   git add .sops.yaml secrets/encrypted/
   git commit -m "Add [name] to secrets recipients"
   git push
   ```

### What the new developer does next

After pulling the updated branch:

```bash
./secrets/decrypt.sh
```

The secrets are now decrypted locally. They can edit, re-encrypt, and commit changes like any other developer.

---

## How-To: Adding a CI/CD Agent

CI/CD systems that need access to secrets get their own age keypair, just like a developer. The difference is where the private key is stored.

### Step 1: Generate a keypair for CI/CD

On any machine (your own is fine):

```bash
age-keygen
```

This prints both the public and private key to the terminal. Copy both.

### Step 2: Store the private key as a CI/CD secret

Store the private key (`AGE-SECRET-KEY-1...`) in your CI/CD platform's secret storage:

| Platform | Where to store it |
|----------|------------------|
| **GitHub Actions** | Repository Settings → Secrets → `AGE_PRIVATE_KEY` |
| **GitLab CI** | Settings → CI/CD → Variables → `AGE_PRIVATE_KEY` (masked, protected) |
| **Other** | Whatever secret/environment variable mechanism the platform provides |

### Step 3: Add the public key to `.sops.yaml`

Add the CI/CD public key alongside the developer keys:

```yaml
creation_rules:
  - path_regex: secrets/.*\.yaml$
    age: >-
      age1dev1...,
      age1dev2...,
      age1cicd...,
      age1master...
```

Run `sops updatekeys` on each encrypted file, then commit and push.

### Step 4: Decrypt in the pipeline

In your CI/CD pipeline, set the `SOPS_AGE_KEY` environment variable and decrypt. Use the convenience script to decrypt all environment files, or specify a single file:

```bash
export SOPS_AGE_KEY="$AGE_PRIVATE_KEY"

# Decrypt all secret files
./secrets/decrypt.sh

# Or decrypt a specific environment
./secrets/decrypt.sh prod
```

**GitHub Actions example:**

```yaml
- name: Decrypt secrets
  env:
    SOPS_AGE_KEY: ${{ secrets.AGE_PRIVATE_KEY }}
  run: ./secrets/decrypt.sh
```

---

## Creating or Editing Secrets

Once initialized, the day-to-day workflow is:

```bash
# Decrypt the file you need to edit
./secrets/decrypt.sh dev

# Edit the plaintext file
vim secrets/unencrypted/dev.yaml

# Re-encrypt only that file
./secrets/encrypt.sh dev

# Commit the encrypted file
git add secrets/encrypted/dev.enc.yaml
git commit -m "Update dev secrets"
```

Use the single-file form (`encrypt.sh dev`) for daily work. Running `encrypt.sh` with no arguments re-encrypts **all** files, which produces git changes in every encrypted file even if only one plaintext changed (SOPS generates a new data key each time). Save the no-argument form for key rotation or initial setup.

Always use this decrypt → edit → encrypt workflow. Do **not** use `sops edit` (which edits encrypted files in-place via a temp file) — it bypasses the `secrets/unencrypted/` directory, leaving it stale and out of sync with the encrypted files. The `dotenv.sh` script and any application reading from `secrets/unencrypted/` would silently use outdated values.

### Resolving Merge Conflicts in Encrypted Files

If two developers edit and encrypt the same secrets file on different branches, the encrypted file will conflict on merge. Encrypted YAML cannot be merged by git — the ciphertext is meaningless to merge tools.

To resolve:

1. Accept the incoming (target branch) version of the encrypted file
2. Decrypt it: `./secrets/decrypt.sh dev`
3. Manually re-apply your plaintext changes to `secrets/unencrypted/dev.yaml`
4. Re-encrypt: `./secrets/encrypt.sh dev`
5. Stage and complete the merge

---

## Generating a .env File

The `dotenv.sh` script converts a decrypted YAML secrets file into a `.env` file at the project root. This is useful for applications that read configuration from environment variables.

```bash
# Generate .env from secrets/unencrypted/secrets.yaml (the default)
./secrets/dotenv.sh

# Generate .env from a specific environment file
./secrets/dotenv.sh dev
./secrets/dotenv.sh prod
```

The script:

- Converts YAML keys to UPPERCASE (e.g., `database_host` becomes `DATABASE_HOST`)
- Preserves comments from the YAML file
- Quotes values that contain spaces or special characters
- Requires flat YAML (no nested keys) — this is a deliberate constraint to keep secrets files simple and .env-compatible

**Example input** (`secrets/unencrypted/dev.yaml`):

```yaml
# Database
database_host: localhost
database_port: 5432

# External services
api_key: sk-abc123
```

**Example output** (`.env`):

```env
# Database
DATABASE_HOST=localhost
DATABASE_PORT=5432

# External services
API_KEY=sk-abc123
```

The `.env` file is `.gitignored` and must never be committed.

---

## Offboarding a Developer

1. Remove their public key from `.sops.yaml`
2. Run `sops updatekeys` on all encrypted files
3. Commit and push
4. Consider rotating any secrets the departing developer had access to — they may have copies of decrypted values

---

## Reference

### .sops.yaml Configuration

The `.sops.yaml` file lives at the project root and lists all recipient public keys:

```yaml
creation_rules:
  - path_regex: secrets/.*\.yaml$
    age: >-
      age1dev1...,
      age1dev2...,
      age1master...
    # dev1-name, dev2-name, master (break-glass)
```

The `path_regex` ensures SOPS only applies these rules to YAML files under the `secrets/` directory. This covers both the unencrypted input files (used during `sops --encrypt`) and the encrypted output files.

### Convenience Scripts

The init script copies three scripts into the consuming project's `secrets/` directory:

| Script | Usage | Purpose |
|--------|-------|---------|
| `encrypt.sh [name]` | `./secrets/encrypt.sh` or `./secrets/encrypt.sh dev` | Encrypts `.yaml` files in `unencrypted/` to `.enc.yaml` files in `encrypted/` |
| `decrypt.sh [name]` | `./secrets/decrypt.sh` or `./secrets/decrypt.sh dev` | Decrypts `.enc.yaml` files in `encrypted/` to `.yaml` files in `unencrypted/` |
| `dotenv.sh [name]` | `./secrets/dotenv.sh` or `./secrets/dotenv.sh dev` | Converts a decrypted YAML file to `.env` at the project root |

All three scripts verify that `secrets/unencrypted/` and `.env` are gitignored before proceeding.

### Key Locations

| Key | Location | Committed? |
|-----|----------|-----------|
| Developer private key | `~/.config/sops/age/keys.txt` | Never |
| Developer public key | Listed in `.sops.yaml` | Yes |
| Break-glass private key | External secure storage | Never |
| Break-glass public key | Listed in `.sops.yaml` | Yes |
| CI/CD private key | CI/CD platform secret store | Never |
| CI/CD public key | Listed in `.sops.yaml` | Yes |

---

## Safeguards and Best Practices

### Defense in Depth

This strategy uses multiple layers to prevent plaintext secrets from being committed:

1. **`.gitignore`** — The primary defense. `secrets/unencrypted/`, `.env`, and `.env.*` are gitignored. Git will not track these files, and `git add .` will not stage them. A developer would have to explicitly `git add --force` to override this.

2. **Directory separation** — Plaintext and encrypted files live in clearly named, separate directories. There is no ambiguity about which files are safe to commit.

3. **File extension convention** — Encrypted files use `.enc.yaml`. Any `.yaml` file in `secrets/encrypted/` without the `.enc.` prefix is suspicious and should be investigated.

### Rules for AI Code Agents

AI agents working in repositories that use this strategy must follow these rules:

- **NEVER write secrets, credentials, API keys, passwords, tokens, or connection strings into any file outside of `secrets/unencrypted/`.** If code needs a secret value, it should read it from an environment variable or from `secrets/unencrypted/*.yaml` at runtime.
- **NEVER commit, stage, or suggest staging files in `secrets/unencrypted/`** or any `.env` / `.env.*` file.
- **NEVER hardcode secret values in source code, configuration files, CI/CD pipelines, Dockerfiles, or documentation.** Use environment variable references (`$VARIABLE_NAME`, `${VARIABLE_NAME}`, `process.env.VARIABLE_NAME`, `os.environ["VARIABLE_NAME"]`, etc.) instead.
- **NEVER log, print, or echo secret values** in scripts, application code, or CI/CD output. If debugging is needed, confirm the variable *exists* (e.g., `echo "API_KEY is set: ${API_KEY:+yes}"`) without revealing its value.
- **NEVER create unencrypted copies of secrets** outside of `secrets/unencrypted/` — no temp files, no backup copies, no inline values in test fixtures.
- **If a `.env` file, `.env.local` file, or any file matching common secret patterns (`*.pem`, `*.key`, `*credentials*`, `*secret*`) is encountered outside of `secrets/`**, flag it for review. It may contain plaintext secrets that should be managed through this strategy instead.
- **When adding a new secret** that an application needs, add it to the appropriate `secrets/unencrypted/*.yaml` file, document the key name, and reference it via environment variable in the application code.
- **When reviewing code changes**, verify that no diff introduces a literal secret value. Look for patterns such as: strings that look like API keys (`sk-`, `pk_`, `ghp_`, `AKIA`), base64-encoded blobs in config files, and connection strings with embedded passwords.

### Recommended CI Check

Add a CI step that fails the build if plaintext secrets or common secret patterns are detected in the committed tree. This is the only safeguard that cannot be bypassed by a developer or AI agent.

**GitHub Actions example:**

```yaml
- name: Check for plaintext secrets
  run: |
    # Fail if any file in secrets/unencrypted/ is tracked
    if git ls-files --error-unmatch secrets/unencrypted/ 2>/dev/null; then
      echo "::error::Plaintext secrets are tracked in git!"
      exit 1
    fi

    # Fail if any .env file is tracked
    ENV_FILES=$(git ls-files | grep -E '(^|/)\.env(\..*)?$' || true)
    if [[ -n "$ENV_FILES" ]]; then
      echo "::error::.env files are tracked in git:"
      echo "$ENV_FILES"
      exit 1
    fi

    # Warn on common secret file patterns in the tree (outside secrets/encrypted/)
    SUSPECT=$(git ls-files | grep -E '\.(pem|key|pfx|p12)$|credentials' | grep -v 'secrets/encrypted/' || true)
    if [[ -n "$SUSPECT" ]]; then
      echo "::warning::Potentially sensitive files detected:"
      echo "$SUSPECT"
    fi
```

### Recommended Pre-Commit Hook

For local development, a pre-commit hook provides an early warning before code reaches CI. The init script does not install this automatically — developers opt in.

To install manually, create `.git/hooks/pre-commit`:

```bash
#!/bin/bash
# Prevent committing plaintext secrets or .env files

STAGED=$(git diff --cached --name-only)

# Check for files in secrets/unencrypted/
if echo "$STAGED" | grep -q "^secrets/unencrypted/"; then
  echo "ERROR: Plaintext secret files are staged for commit:"
  echo "$STAGED" | grep "^secrets/unencrypted/"
  echo ""
  echo "These files must never be committed. Remove them with:"
  echo "  git reset HEAD secrets/unencrypted/"
  exit 1
fi

# Check for .env files
if echo "$STAGED" | grep -qE '(^|/)\.env(\..*)?$'; then
  echo "ERROR: .env file is staged for commit:"
  echo "$STAGED" | grep -E '(^|/)\.env(\..*)?$'
  echo ""
  echo "The .env file must never be committed. Remove it with:"
  echo "  git reset HEAD .env"
  exit 1
fi
```

Make it executable: `chmod +x .git/hooks/pre-commit`

Projects using the [pre-commit](https://pre-commit.com/) framework can add equivalent checks to `.pre-commit-config.yaml` for version-controlled, team-shared hook definitions.
