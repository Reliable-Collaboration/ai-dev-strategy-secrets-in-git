# Secrets in Git

A strategy for storing encrypted secrets directly in git repositories using [SOPS](https://github.com/getsops/sops) and [age](https://github.com/FiloSottile/age). Designed for small teams who need a simple, version-controlled key vault without external infrastructure.

## How It Works

- Each developer has their own age keypair (public key committed, private key local-only)
- SOPS encrypts individual YAML values — git diffs show which keys changed, not the values
- A break-glass master key provides disaster recovery
- Convenience scripts make the workflow simple: `decrypt.sh` → edit → `encrypt.sh`

## Usage

This repository is intended to be added as a **git submodule** in consuming projects. It provides:

- **Documentation** — the full strategy specification and design rationale
- **`init.sh`** — scaffolds the secrets directory structure, generates a break-glass key, and sets up `.sops.yaml`
- **Template scripts** — `encrypt.sh`, `decrypt.sh`, and `dotenv.sh` are copied into the consuming project

### Quick Start

```bash
# Add as a submodule
git submodule add <repo-url> dev-strategies-tooling/ai-dev-strategy-secrets-in-git

# Initialize (auto-detects or creates your age key — no copy-pasting)
./dev-strategies-tooling/ai-dev-strategy-secrets-in-git/init.sh

# Store the break-glass master key that is printed — it won't be shown again

# Edit and encrypt your first secrets
nano secrets/unencrypted/secrets.yaml
./secrets/encrypt.sh
git add .sops.yaml secrets/encrypted/ secrets/*.sh .gitignore
git commit -m "Initialize encrypted secrets"
```

### Prerequisites (Ubuntu)

```bash
# age
sudo apt update && sudo apt install -y age

# SOPS (download .deb from GitHub releases)
SOPS_LATEST=$(curl -s https://api.github.com/repos/getsops/sops/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
curl -Lo /tmp/sops.deb "https://github.com/getsops/sops/releases/download/${SOPS_LATEST}/sops_${SOPS_LATEST#v}_amd64.deb"
sudo dpkg -i /tmp/sops.deb && rm /tmp/sops.deb
```

## Documentation

| Document | Purpose |
|----------|---------|
| [secrets-in-git.md](./secrets-in-git.md) | Full strategy specification — file structure, workflows, safeguards |
| [secrets-in-git-ICD.md](./secrets-in-git-ICD.md) | Design rationale — why each decision was made |

## License

[Apache 2.0](./LICENSE)
