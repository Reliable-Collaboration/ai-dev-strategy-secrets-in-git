# Secrets in Git: Intentions, Considerations, and Decisions

**Status:** ICD file for [Secrets in Git](./secrets-in-git.md). Captures the reasoning journey behind the secrets management strategy.

---

## 1. Why Store Secrets in Git at All

### Context

Small teams need a way to share environment-specific secrets (API keys, database credentials, service tokens) across developers and environments. The common approaches are:

- **External secret managers** (AWS Secrets Manager, HashiCorp Vault, 1Password) — powerful but add infrastructure complexity, cost, and a runtime dependency.
- **Environment variables only** — no persistence, no version history, manual synchronization between developers.
- **Encrypted files in git** — version-controlled, reviewable, no external dependencies beyond the encryption tool.

### The decision

Use encrypted files in git as a "poor-man's key vault." For a small team of trusted developers, the simplicity of version-controlled encrypted files outweighs the benefits of a dedicated secret management service. Secrets travel with the code, are versioned alongside it, and require no external infrastructure.

### Why this matters for the future

If the team grows significantly or compliance requirements change, migrating to a dedicated secret manager may become necessary. The SOPS file format (YAML with encrypted values) makes migration straightforward — the structure is already machine-readable, and the unencrypted values can be piped directly into an external vault.

---

## 2. SOPS Over Raw age Encryption

### Context

The initial idea was whole-file encryption using age — encrypt a YAML file into an opaque binary blob. This works but has drawbacks for a version-controlled workflow.

### Alternatives considered

**Raw `age` encryption** — Encrypt the entire file. Simple, but the encrypted output is binary. Git diffs are meaningless. You cannot tell what changed between commits without decrypting both versions. Code review of secret changes is impossible.

**SOPS with age backend** — SOPS encrypts individual values within structured files (YAML, JSON, etc.) while leaving keys and structure visible. Git diffs show which keys changed, even though the values are opaque. SOPS also manages the encryption envelope (data key, recipient list) separately from the content.

### The decision

Use SOPS with age as the encryption backend. The per-value encryption preserves the structure of the secrets file in version control, making diffs meaningful and code review possible. SOPS also provides key rotation, multi-recipient support, and a `.sops.yaml` configuration file that declaratively defines encryption rules.

### Why this matters for the future

If someone proposes switching to raw age encryption for simplicity, the question is: can you review secret changes in a pull request? With SOPS, you can see that `database_password` changed even though you cannot see the new value. With raw age, you see only that a binary blob changed.

---

## 3. age Over PGP

### Context

SOPS supports multiple encryption backends: AWS KMS, GCP KMS, Azure Key Vault, PGP, and age. For an approach with no cloud dependencies, the choices are PGP and age.

### Alternatives considered

**PGP (GnuPG)** — The traditional choice for file encryption. Mature, widely supported, but notoriously difficult to use correctly. Key management is complex (key servers, trust models, subkeys, expiration). The tooling (`gpg`) has a steep learning curve and inconsistent behavior across platforms.

**age** — Designed as a modern replacement for PGP's encryption use case. Simple key format (one line), no configuration, no key servers, no trust model to manage. The tradeoff is fewer features — but the missing features (signing, trust models, key servers) are not needed for this use case.

### The decision

Use age. For encrypting secrets in a small-team context, age's simplicity is the right fit. Key generation is one command. Key format is one line. There is no configuration to get wrong.

---

## 4. Per-Developer Keys Over a Shared Secret

### Context

The original concept was a single pre-shared secret (possibly a UUID) that all developers would share. Each developer would place this shared secret in a local file, and encryption/decryption would use it.

### Alternatives considered

**Shared passphrase (UUID)** — One password shared by the whole team. Simple mental model. But SOPS does not support age's passphrase mode — it only works with age recipient keys. To make this work, the UUID would need to protect an age private key (adding a layer of indirection), or the team would need to skip SOPS and use raw age passphrase mode (losing per-value encryption and key rotation).

**Shared age private key** — All developers use the same age keypair. The private key is the shared secret. Works with SOPS natively. But offboarding a developer means generating a new key and redistributing to everyone — and re-encrypting all secrets. There is no way to revoke one person's access without affecting everyone.

**Per-developer age keys** — Each developer has their own keypair. All public keys are listed in `.sops.yaml`. SOPS encrypts the data key to every recipient independently. Any listed developer can decrypt. Adding or removing a developer means updating `.sops.yaml` and running `sops updatekeys` — no other developers are affected, no new keys need distributing.

### The decision

Use per-developer age keys. This eliminates the need for a shared secret entirely. Onboarding is "generate a keypair, send me your public key." Offboarding is "remove their public key, run updatekeys." The multi-recipient model is native to both age and SOPS — this is how they are designed to be used.

### Why this matters for the future

The shared-secret approach feels simpler at first, but it creates a fragile single point of coordination: every team change requires redistributing the secret to everyone. Per-developer keys distribute trust naturally. The `.sops.yaml` file is a readable, auditable record of exactly who can decrypt the secrets.

---

## 5. Break-Glass Master Key

### Context

With per-developer keys, there is a risk scenario: if all developers lose their private keys (or if the only developer with a key leaves unexpectedly), the secrets become permanently unrecoverable.

### The decision

Generate one additional age keypair as a break-glass recovery key. The public key is added to `.sops.yaml` alongside the developer keys. The private key is stored in a secure external location — a password manager, a physical safe, or similar — never on a developer machine and never in the repository.

This key is never used in normal operations. It exists solely as a recovery mechanism. It can also serve as a bootstrap key for onboarding the very first developer into a new project.

### Why this matters for the future

The irony of storing one key externally to protect an in-repo key vault is intentional. The value proposition is reducing the external secret surface from many secrets across many environments to exactly one key in one secure location.

---

## 6. File Structure and Naming

### Context

The strategy needs a directory layout that keeps encrypted and unencrypted files clearly separated, prevents accidental commits of plaintext secrets, and is consistent across all consuming projects.

### The decision

```
secrets/
  unencrypted/          # .gitignored — never committed
  encrypted/            # committed to git
  encrypt.sh
  decrypt.sh
```

The `unencrypted/` directory is `.gitignored` at the project level. Encrypted files use a `.enc.yaml` extension to distinguish them from their plaintext counterparts. The convenience scripts live alongside the directories they operate on.

`.sops.yaml` lives at the project root rather than inside `secrets/` because SOPS looks for it by walking up from the encrypted file's location, and because it is project-level configuration (like `.gitignore` or `.editorconfig`), not a secret itself.

---

## 7. Submodule Includes Tooling, Not Just Documentation

### Context

The initial design was documentation-only — the submodule would describe the strategy and each consuming project would implement the scripts. This created a bootstrapping problem: the first thing a developer does after reading the strategy is manually create directories, write scripts, and set up `.sops.yaml`. That manual setup is both tedious and error-prone, and it is the same for every project.

### The decision

The submodule includes an `init.sh` script and template convenience scripts (`scripts/encrypt.sh`, `scripts/decrypt.sh`, `scripts/dotenv.sh`). The init script scaffolds the entire structure in the consuming project: directories, `.gitignore` entries, `.sops.yaml`, and copies of the convenience scripts. This means adopting the strategy is one command.

The convenience scripts are copied (not symlinked) into the consuming project so they work independently of the submodule path and can be customized per-project if needed.

---

## 8. Multiple Environments via Separate Files, Same Keys

### Context

Projects often have different secrets per environment (development, staging, production). The strategy needs a convention for this.

### Alternatives considered

**Single file with environment sections** — One `secrets.yaml` with top-level keys like `dev:`, `staging:`, `prod:`. Keeps everything in one place but means every developer always decrypts every environment's secrets, and the file grows large. Also complicates the `.env` export (which environment's values do you flatten?).

**Separate files, different recipient keys per environment** — `dev.yaml` encrypted to all developers, `prod.yaml` encrypted to only senior developers. Provides access control but adds complexity: multiple creation rules in `.sops.yaml`, careful key management per environment, and confusion when a developer can decrypt some files but not others.

**Separate files, same keys for all environments** — One file per environment (`dev.yaml`, `staging.yaml`, `prod.yaml`), all encrypted to the same set of recipients. Simple, consistent, and sufficient for a small trusted team.

### The decision

Separate files, same keys. Each environment gets its own YAML file. The convenience scripts (`encrypt.sh`, `decrypt.sh`) operate on all files in their directories automatically — no arguments needed. The `dotenv.sh` script takes an environment name argument to select which file to export.

Per-environment access control is explicitly out of scope. If access control per environment is needed, the team has outgrown this strategy and should use a dedicated secret manager.

### Why this matters for the future

This is a deliberate simplicity choice. SOPS supports per-path recipient lists, and the strategy could be extended to use them. But for the intended audience (small, trusted team), the added complexity of per-environment access control is not worth the marginal security benefit — anyone trusted enough to be on the team is trusted with all environments.

---

## 9. The dotenv Script and Flat YAML Constraint

### Context

Many applications read configuration from `.env` files or environment variables. Developers need a way to go from encrypted YAML in git to a `.env` file their application can consume.

### Alternatives considered

**Use a YAML parser (yq, python)** — Proper YAML parsing handles edge cases (nested keys, multi-line values, anchors) but adds a dependency. More importantly, most YAML parsers discard comments, and preserving comments was an explicit requirement — comments in a secrets file document what each secret is for, and that context should survive the conversion.

**Line-by-line conversion with awk** — Handles flat YAML (key-value pairs) and preserves comments and blank lines exactly. Cannot handle nested YAML, but this limitation can be turned into a convention: secrets files are flat.

### The decision

Use awk-based line-by-line conversion. The script converts `key: value` to `KEY=value` (uppercased), passes comments and blank lines through unchanged, and emits warnings for lines it cannot convert (e.g., nested YAML).

The flat-YAML-only constraint is prescribed as part of the strategy. Secrets files should be flat key-value pairs, not nested structures. This keeps them compatible with `.env` export, simple to read, and easy to diff. If a project needs nested configuration, that configuration is not a secret — it belongs in a regular config file.

### Why this matters for the future

If someone needs nested YAML secrets, the right answer is not to make the dotenv script smarter — it is to question whether nested configuration belongs in the secrets file at all. Keeping secrets flat enforces a healthy separation between secrets (credentials, API keys) and configuration (feature flags, URLs, thresholds).

---

## 10. Safeguards: Defense in Depth and AI Agent Rules

### Context

The `.gitignore` entry for `secrets/unencrypted/` prevents accidental commits in most cases. But `.gitignore` can be overridden with `git add --force`, and AI code agents working in the repository may not understand the secrets management conventions unless explicitly told. The strategy needs a defense-in-depth approach that addresses both human and AI failure modes.

### Alternatives considered

**Pre-commit hooks only** — Local hooks provide early feedback but are not enforced. They live in `.git/hooks/` (not committed), must be manually installed by each developer, and can be bypassed with `--no-verify`. They are a convenience, not a control.

**CI checks only** — Server-side checks are the only truly unbypassable safeguard, but they provide late feedback — the secret is already in the commit history by the time CI catches it. (Though it can block the PR merge, preventing the secret from reaching the main branch.)

**Defense in depth** — Layer multiple safeguards: `.gitignore` (prevents accidental staging), pre-commit hooks (catches mistakes locally), CI checks (catches anything that slips through), and explicit AI agent rules in the specification (prevents AI tools from generating insecure code).

### The decision

Use all layers. The specification includes:

1. **`.gitignore`** as the primary, always-present defense (set up by the init script)
2. **A recommended pre-commit hook** with installation instructions (opt-in per developer)
3. **A recommended CI check** with a ready-to-use GitHub Actions example (the only enforceable safeguard)
4. **Explicit rules for AI code agents** written directly into the specification

The AI agent rules are written as direct prohibitions ("NEVER write secrets into...", "NEVER commit files in...") because AI agents operating in a repository will read the specification (or a CLAUDE.md / AGENTS.md that references it) and need unambiguous instructions. The rules cover the most common AI failure modes: hardcoding secret values in source code, logging secrets, creating unencrypted copies, and failing to flag suspicious files.

### Why this matters for the future

The AI agent rules are an unusual addition to a specification — most specs describe what humans should do. But in a codebase where AI agents routinely generate and modify code, the specification is the natural place to encode constraints that the agent must follow. If the rules were only in a CLAUDE.md or similar file, they would not travel with the strategy when it is adopted by new projects. Embedding them in the specification ensures they are discoverable by any agent that reads the strategy documentation.

---

## 11. sops edit Mode Not Supported

### Context

SOPS provides a built-in `sops edit` command that decrypts a file to a temporary location, opens the user's editor, and re-encrypts on save. This is a convenient single-command workflow. The question was whether to support it alongside the decrypt → edit → encrypt workflow.

### Alternatives considered

**Support both workflows** — Document `sops edit` as an alternative for quick changes. But `sops edit` bypasses `secrets/unencrypted/` entirely — the plaintext exists only in a temp file during the edit session. After a `sops edit`, the encrypted file has new values but `secrets/unencrypted/` still has the old ones. Any process reading from `secrets/unencrypted/` (including `dotenv.sh` and the application itself) silently uses stale data. A developer would need to remember to run `decrypt.sh` after every `sops edit` to re-sync — a step that is easy to forget and produces no error when skipped.

**Support only sops edit** — Drop the two-file workflow and `secrets/unencrypted/` directory entirely. But then there is no persistent plaintext for the application to read at runtime, and the `dotenv.sh` script has nothing to convert.

**Support only the two-file workflow** — One way to edit secrets: decrypt, edit the plaintext, encrypt. No ambiguity about which files are current. `secrets/unencrypted/` is always the source of truth for plaintext values.

### The decision

Do not support `sops edit`. The two-file decrypt → edit → encrypt workflow is the only prescribed method. The specification explicitly warns against using `sops edit` because it creates silent state drift between the encrypted and unencrypted directories.

### Why this matters for the future

If someone proposes adding `sops edit` support for convenience, the question is: what happens when a developer forgets to run `decrypt.sh` afterward? The answer is nothing visible — no error, no warning, just stale plaintext that the application silently consumes. The two-file workflow avoids this entirely because the developer always edits the plaintext directly.

---

## 12. Pre-Release Script Hardening

### Context

A full review of the scripts and specification before first use revealed several issues that would cause friction or safety gaps in real-world usage.

### Issues found and fixes applied

**encrypt.sh re-encrypts ALL files every time.** SOPS generates a new random data key on every `sops --encrypt`, so even unchanged plaintext produces different ciphertext. Running `encrypt.sh` with no arguments would show git changes in every encrypted file. Fixed by adding optional single-file mode: `encrypt.sh dev` encrypts only `dev.yaml`. The no-argument batch mode is preserved for key rotation and initial setup.

**init.sh .gitignore gap.** The `.env` entry was only added when `secrets/unencrypted/` was also being added. If `secrets/unencrypted/` already existed in `.gitignore` from a previous partial run, `.env` would not be added. Fixed by checking and adding each gitignore entry independently.

**Incomplete .env coverage in .gitignore.** Only `.env` was gitignored. Variants like `.env.local`, `.env.production`, `.env.dev` were unprotected. Fixed by adding `.env.*` to `.gitignore` alongside `.env`, and broadening the CI check and pre-commit hook to catch all `.env` variants.

**dotenv.sh missing gitignore check.** `encrypt.sh` and `decrypt.sh` verified `.gitignore` protected the unencrypted directory, but `dotenv.sh` — which writes the equally sensitive `.env` file — did not. Fixed by adding the same gitignore verification to `dotenv.sh`, checking both `secrets/unencrypted/` and `.env`.

**init.sh no git repo check.** If someone ran the init script outside a git repository, files would be created but the gitignore protection would be meaningless. Fixed by adding a `git rev-parse --is-inside-work-tree` check.

**decrypt.sh gitignore check before mkdir.** On a fresh clone, `secrets/unencrypted/` doesn't exist. The gitignore check ran before `mkdir -p`, creating a potential evaluation issue. Fixed by moving `mkdir -p` before the gitignore check.

**Starter example had indented keys.** The template `secrets.yaml` used `#   api_key:` with indentation, resembling nested YAML. The strategy prescribes flat YAML. Fixed to use flat formatting.

**No merge conflict guidance.** Two developers encrypting the same file on different branches would produce an unresolvable encrypted merge conflict. Added a "Resolving Merge Conflicts" section documenting the resolution workflow: accept theirs, decrypt, re-apply changes, re-encrypt.

**CI/CD section used hardcoded filename.** The CI example showed `sops --decrypt secrets/encrypted/secrets.enc.yaml` — a single file. Updated to use the `decrypt.sh` convenience script, which handles single or multiple files.

### Why this matters for the future

These fixes follow a pattern: every script that writes sensitive output (plaintext secrets, `.env` files) should verify its safety preconditions before proceeding. If a new script is added to the strategy, it should include the same gitignore verification pattern used by the existing scripts.

---

## Unanswered Questions and Considerations

~~1. **Should the strategy include a template `.sops.yaml` and scaffold script?**~~ — Resolved in §7.

~~2. **How should multiple secret files be handled?**~~ — Resolved in §8.

~~3. **Should the convenience scripts support `sops edit` mode?**~~ — Resolved in §11.

~~4. **What pre-commit hooks or CI checks should be recommended?**~~ — Resolved in §10.

All questions resolved.
