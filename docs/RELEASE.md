# Release Guide

## Quick Reference

```bash
# 1. Bump version in scripts/make-app.sh (CFBundleShortVersionString + CFBundleVersion)
# 2. Commit and push via PR (master is protected — direct push is blocked)
git checkout -b release/X.Y.Z
git add scripts/make-app.sh && git commit -m "chore: bump version to X.Y.Z (build N)"
git push -u origin release/X.Y.Z
gh pr create --title "chore: bump version to X.Y.Z" --body "Release prep"
gh pr merge --merge

# 3. One-time local notarization helper (do not commit)
cat > .zion-release.local <<'EOF'
export CODESIGN_IDENTITY="Developer ID Application: Your Name"
export NOTARY_KEYCHAIN_PROFILE="your-notary-profile"
EOF

# 4. Build, sign, notarize, and upload (from master)
git checkout master && git pull
./scripts/release.sh upload
```

That's it. The script handles everything else.

---

## What the Script Does

`scripts/release.sh` runs 6 build/release steps, plus an optional upload step:

| Step | What happens |
|------|-------------|
| 1. Build app | Runs `make-app.sh` — compiles release binary, assembles `dist/Zion.app` with Info.plist, icon, fonts, and Sparkle framework |
| 2. Notarize app | If `.zion-release.local` is present, zips `Zion.app`, submits via `notarytool`, and staples the ticket |
| 3. Create DMG | Runs `make-dmg.sh` — packages `Zion.app` + Applications symlink into `dist/Zion.dmg` via `hdiutil` |
| 4. Notarize DMG | If `.zion-release.local` is present, signs `Zion.dmg` with Developer ID, notarizes it, and staples it |
| 5. Sign DMG | Runs Sparkle's `sign_update` — signs the final DMG with the EdDSA private key from macOS Keychain |
| 6. Generate appcast | Creates `dist/appcast.xml` with version, build number, download URL, signature, and file size |
| Upload | Creates (or updates) a GitHub Release tagged `vX.Y.Z`, uploading both `Zion.dmg` and `appcast.xml` |

The upload step only runs if you pass the `upload` argument. Without it, the script stops after generating the appcast locally.

---

## How Sparkle Auto-Updates Work

The update chain:

```
Zion.app launches
  → reads SUFeedURL from Info.plist
  → fetches appcast.xml from GitHub Releases (latest)
  → compares sparkle:version (build number) with current build
  → if newer: downloads Zion.dmg from the URL in <enclosure>
  → verifies EdDSA signature using SUPublicEDKey embedded in Info.plist
  → installs update
```

Key Info.plist keys (set in `make-app.sh`):

| Key | Value | Purpose |
|-----|-------|---------|
| `SUFeedURL` | `https://github.com/nicolaregattieri/zion-code/releases/latest/download/appcast.xml` | Where to check for updates |
| `SUPublicEDKey` | `4UJJHDAuD5klxnaOjA8q/4pd/tVSygoSNWZ2W/IQ6hQ=` | Public key to verify DMG signature |
| `SUEnableAutomaticChecks` | `true` | Check on launch |
| `SUScheduledCheckInterval` | `86400` | Re-check every 24 hours |

Sparkle compares by `sparkle:version` (the build number, e.g. `2`), not the display version string. Always increment the build number for every release.

---

## How Signing Works

Sparkle uses EdDSA (Ed25519) key pairs:

- **Private key** — stored in macOS Keychain (added automatically by `sign_update` on first run). Used to sign each DMG at release time.
- **Public key** — embedded in `Info.plist` as `SUPublicEDKey`. Shipped with every copy of the app. Used to verify downloaded updates.

The `sign_update` tool outputs two values that go into `appcast.xml`:
- `sparkle:edSignature` — the cryptographic signature
- `length` — DMG file size in bytes

If the private key is lost, existing users cannot verify new updates. See "New Machine Setup" below for key backup/restore.

---

## Files Involved

| File | Purpose |
|------|---------|
| `scripts/release.sh` | Main release script (build + sign + appcast + upload) |
| `scripts/make-app.sh` | Builds `dist/Zion.app` from release binary; contains version numbers in Info.plist |
| `scripts/make-dmg.sh` | Packages `Zion.app` into `dist/Zion.dmg` |
| `dist/Zion.app` | Built application bundle (git-ignored) |
| `dist/Zion.dmg` | Distributable disk image (git-ignored) |
| `dist/appcast.xml` | Sparkle update feed (git-ignored, uploaded to GitHub Releases) |
| `Package.swift` | Sparkle declared as a dependency here |

---

## Release Notes Style (MANDATORY)

Every GitHub Release **must** follow this format. Claude: check this section before creating any release.

### Template

```markdown
# Zion X.Y.Z

> One-line summary of this release's theme or headline feature.

## Highlights

- **Feature Name** — Short description of what it does and why it matters
- **Feature Name** — Short description
- **Improvement** — Short description

## What's Changed

* feat(scope): Description of feature
* fix(scope): Description of fix

**Full Changelog**: vPREV...vX.Y.Z
```

### Rules

1. **Title**: Always `Zion X.Y.Z` (matches the tag)
2. **Summary line**: One sentence below the title — the elevator pitch for this release
3. **Highlights section**: Hand-written, 3–6 bullets. Each bullet is `**Bold Name** — description`. Focus on user-facing value, not implementation details. Group related changes.
4. **What's Changed section**: Auto-generated by `release.sh` from `git log` between the previous tag and HEAD. Lists all commits from merged PRs. Do NOT edit or remove this section.
5. **Full Changelog link**: Auto-generated. Links to the full diff between tags.
6. **Major releases** (x.0.0): Add an `## Install` section at the bottom with download/build instructions.
7. **Breaking changes**: If any, add a `## Breaking Changes` section between Highlights and What's Changed.

### Workflow

1. Use descriptive commit messages — they become the "What's Changed" line items (e.g. `feat(terminal): Add AI image display`)
2. All changes go through PRs — master is protected by a GitHub ruleset (direct push is blocked)
3. Run `./scripts/release.sh upload` — it auto-generates the "What's Changed" section from commits
4. Immediately after upload, edit the release on GitHub (or via `gh release edit`) to prepend the title, summary, and Highlights section above the auto-generated content

### Release History (Reference)

**v1.0.0** — First public release. Hand-crafted notes with Highlights, Details, and Install sections. Set the tone for the project.

**v1.1.0** — Zion Map, Code Review, Sparkle auto-updates. First release with PR-based "What's Changed" (#1, #2).

**v1.2.0** — Editor expansion. Single PR (#3) in "What's Changed".

**v1.2.1** — Hotfix. Direct push — used `--generate-notes` which produced empty "What's Changed". Fixed in later versions by switching to commit-based changelog.

**v1.2.2** — Hotfix. Same as v1.2.1. From v1.3.0+ the release script uses `git log` so all commits appear regardless of workflow.

**v1.3.0** — Major feature release. Mobile Remote Access, Git Hosting abstraction (GitHub/GitLab/Bitbucket), ViewModel extension split, interactive rebase UI, Recovery Vault.

**v1.3.1** — Merge commit edge rendering, mobile drawer fix, background fetch improvements.

**v1.3.2** — Code formatter (16+ languages), editor symbol index, format on save, bracket pair highlight, indent guides.

**v1.3.3** — Mobile web redesign, remote access wake recovery, Cloudflare 429 handling.

**v1.4.0** — Mobile Remote Access with xterm.js rich terminal, Recovery Vault auto-snapshots, Git Hosting abstraction (GitHub/GitLab/Bitbucket), annotated/signed tags, force push options, code formatter (16+ languages), AI agent slash commands (Claude/Gemini/Codex), security & performance audit.

**v1.4.1** — Mobile tunnel error detection, wake auto-reconnect, session management improvements.

**v1.4.2** — Mobile session branch display fix, refresh screen throttling.

**v1.5.0** — Azure DevOps support, GitHub PATs, improved URL parsing and credential store, smarter PR creation with dynamic base branch and push warnings, security hardening.

**v1.6.0** — Voice-to-text dictation (Apple Speech + Whisper), Git Bisect UI with AI explanation, smooth graph curves, design token compliance, file browser keyboard nav fix.

**v1.6.6** — AI history search upgrade, pending changes card alignment, AI summary persistence, cleaner graph without pending marker.

---

## Version Bumping

Both values live in `scripts/make-app.sh` inside the Info.plist heredoc:

```xml
<key>CFBundleVersion</key>
<string>20</string>                 <!-- build number — Sparkle uses this to detect updates -->
<key>CFBundleShortVersionString</key>
<string>1.5.0</string>              <!-- display version — shown to users -->
```

Rules:
- **Always** increment `CFBundleVersion` (build number) for every release
- `CFBundleShortVersionString` follows semver for user-facing display
- The release script reads these values to determine the git tag (`v1.3.3`) and download URL

---

## New Machine Setup

### 1. Install Sparkle tools

```bash
cd /tmp
curl -LO https://github.com/sparkle-project/Sparkle/releases/download/2.8.1/Sparkle-2.8.1.tar.xz
tar xf Sparkle-2.8.1.tar.xz
# This places sign_update at /tmp/bin/sign_update
```

### 2. Restore the EdDSA private key

The private key is stored in Bitwarden under the Sparkle entry. To restore it into macOS Keychain:

```bash
# Import the key (sign_update will prompt or you can set it via environment)
/tmp/bin/sign_update --import-private-key
# Paste the base64 private key when prompted
```

If you run `sign_update` without a key in Keychain, it will generate a **new** key pair. This breaks updates for existing users — only do this if starting fresh.

### 3. Authenticate GitHub CLI

```bash
brew install gh
gh auth login
# Select: GitHub.com → HTTPS → Login with browser
# Ensure the token has `repo` scope for release uploads
```

### 4. Restore local notarization env

`notarytool` credentials stay in macOS Keychain under your chosen profile name. The local helper file only stores non-secret labels so releases stay one-command and nothing sensitive is committed.

```bash
cat > .zion-release.local <<'EOF'
export CODESIGN_IDENTITY="Developer ID Application: Your Name"
export NOTARY_KEYCHAIN_PROFILE="your-notary-profile"
EOF
```

---

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| `sign_update not found` | Sparkle tools not installed at `/tmp/bin/` | Run the install commands above |
| `gh: not found` | GitHub CLI not installed | `brew install gh` |
| `HTTP 403` on upload | Token missing `repo` scope | `gh auth refresh -s repo` |
| `Release vX.Y.Z already exists` | Re-releasing same version | Script handles this — uses `gh release upload --clobber` to replace assets |
| Users don't get update | Build number not incremented | Sparkle compares `sparkle:version` (build number), not display version |
| Signature verification fails | Wrong private key or public key mismatch | Ensure `SUPublicEDKey` in `make-app.sh` matches the private key in Keychain |
| Wrong repo in appcast URL | `GITHUB_REPO` in `release.sh` doesn't match actual repo | Update the `GITHUB_REPO` variable in `release.sh` |
