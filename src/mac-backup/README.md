# mac-backup

Encrypted, portable Mac backup bundle. Run on your current Mac, restore on a fresh one by cloning this repo and running two npm scripts.

## What gets backed up

The backup produces **two encrypted archives** per bundle:

**`main.zip.enc`** — everything you need to be productive again:
- `$HOME` dotfiles (`.zshrc`, `.gitconfig`, `.asdfrc`, `.tool-versions`, etc.)
- Whole directories: `~/Documents`, `~/Downloads` (configurable via `include.dirs`)
- VS Code settings + snippets + extension list
- Homebrew packages (auto-dumped Brewfile)
- macOS system defaults (from `defaults/macos-defaults.json`)
- Large directories you opt in to via interactive prompt

**`security.zip.enc`** — sensitive files that you may want to restore separately (or skip entirely):
- `~/.ssh/` (private keys, known_hosts, config)
- `~/.aws/credentials` (if present)
- `~/.config/gh/hosts.yml` (GitHub auth token)
- Anything inside the main backup that matched a security pattern (`*.pem`, `*.key`, `id_rsa*`, `credentials`, `*token*`, `*secret*`, `.npmrc`, `.pypirc`, etc.) — these are **moved** from main into security, never duplicated.

The `alsoInclude` list in `defaults/config.json` controls which paths are always added to security. The `patterns` list controls which files get pulled out of main and routed to security.

### Skipping security entirely

Pass `--skip-security` to backup, or set `"skipSecurity": true` in config.json. With that on, security files are still **stripped from main** (so they're not encrypted into the shared bundle) but no security archive is produced. They simply aren't in the backup at all.

## Bundle layout

Each backup creates a folder:

```
~/Documents/mac-backups/
└── 2026-05-20-184500-bkp/
    ├── main.zip.enc           # encrypted main archive
    ├── security.zip.enc       # encrypted security archive (if any)
    ├── config.json            # manifest (viewable without decrypting)
    ├── files.log              # human-readable contents + sizes
    └── README.txt             # quick restore instructions
```

## Usage

### Bootstrap dev apps on this machine first (optional, one-time)

```sh
cd src/mac-backup/defaults
brew bundle install --file=Brewfile.starter
```

### Make a backup

```sh
cd ~/Documents/personal-projects/personal-dev-tools
npm run mac-backup
# or, no security archive:
npm run mac-backup -- --skip-security
```

You'll be prompted to pick large dirs, add extras, and enter an encryption password. The same password is used for both archives so a single decryption gets you everything.

### Restore on a fresh Mac

The restore assumes you've cloned this repo on the new Mac. On a totally clean Mac, do the prerequisites first:

```sh
# Install Homebrew + the bare minimum
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)"
brew install git node

# Clone the tools repo
git clone https://github.com/ldiasrs/personal-dev-tools.git
cd personal-dev-tools && npm install
```

Then run:

```sh
# Step 1: main bundle (Brewfile installs apps, dotfiles, VS Code, ~/Documents, ...)
npm run mac-restore ~/path/to/2026-05-20-184500-bkp

# Step 2: security archive (only if you want SSH keys / AWS creds / tokens back)
npm run mac-restore-security ~/path/to/2026-05-20-184500-bkp
```

You can also inspect what's in the bundle **without decrypting** — `config.json` is plaintext:

```sh
cat ~/path/to/2026-05-20-184500-bkp/config.json | jq .
less ~/path/to/2026-05-20-184500-bkp/files.log
```

## Configuration

Edit `defaults/config.json`:

- `outputDir` — parent folder for bundles (default `~/Documents/mac-backups`)
- `skipSecurity` — set `true` to never produce a security archive
- `include.home` — individual `$HOME` files to track
- `include.dirs` — whole directories (default: `~/Documents`, `~/Downloads`)
- `include.dirExcludePatterns` — patterns skipped inside `include.dirs` (default: `node_modules`, `dist`, build artifacts, prior backup folders)
- `include.vscode.*` — what to grab from `~/Library/Application Support/Code/User`
- `include.security.alsoInclude` — paths always sent to security archive (default: `~/.ssh`, AWS creds, gh token)
- `include.security.patterns` — files moved from main to security if they match any pattern
- `scanForLarge.*` — interactive large-dir prompts during backup

## Files

```
src/mac-backup/
├── index.js              # CLI entry
├── backup.js             # Backup orchestrator
├── restore.js            # Main restore (no security)
├── restore-security.js   # Security restore (~/.ssh, tokens, etc.)
├── scanner.js            # du-based large-dir scan
├── crypto.js             # openssl AES-256-CBC + PBKDF2
├── archive.js            # zip / unzip
├── manifest.js           # config loader + manifest builder
├── prompt.js             # TTY/piped-stdin password reader
├── logger.js             # files.log writer
└── defaults/
    ├── config.json
    ├── macos-defaults.json
    └── Brewfile.starter
```

## Notes

- Encryption: AES-256-CBC with PBKDF2 (200k iterations) via macOS's built-in LibreSSL. Same password works for both archives.
- Archives use `.zip` (built-in `zip`/`unzip` on macOS). File modes are preserved; SSH key permissions are also forced to 600 on restore as belt-and-suspenders.
- Restore is pure Node — no generated shell scripts. The plaintext `config.json` and `files.log` make every backup self-documenting.
- Password is passed via env var to openssl, never visible in `ps`.
