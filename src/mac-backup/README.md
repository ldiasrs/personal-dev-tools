# mac-backup

Encrypted, portable Mac backup bundle. Run on your current Mac, restore on a fresh one with a single shell script.

## What gets backed up

- `$HOME` dotfiles (`.zshrc`, `.gitconfig`, `.asdfrc`, `.tool-versions`, etc.)
- VS Code settings + snippets + extension list
- Homebrew packages (auto-dumped Brewfile)
- macOS system defaults (from `defaults/macos-defaults.json`)
- Large directories you opt in to via interactive prompt

## What's intentionally NOT backed up

- `~/.ssh/` and other SSH keys
- `~/.config/gh/hosts.yml` (GitHub auth token)
- `.aws/credentials*`, `.env*`, `*.pem`, `*.key`, tokens, secrets

A **secrets gate** scans every file before encryption and **hard-fails** the backup if anything secret-looking sneaks in. Override with `--allow-secrets-warning`.

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
```

You'll be prompted to:
1. Pick large directories to include
2. Add extra paths (free-form)
3. Enter an encryption password (twice)

Output: 4 files in `~/Documents/mac-backups/`:
- `<ts>.tar.enc` — encrypted tarball
- `uncrypt-and-restore-<ts>.sh` — self-contained restore script
- `<ts>.config.json` — manifest (what's in it, where each path goes back to)
- `<ts>.log` — human-readable list of contents + warnings

### Restore on a fresh Mac

Copy the 4 files to any folder on the new Mac, then:

```sh
bash uncrypt-and-restore-<ts>.sh
```

It will:
1. Decrypt the tarball (you'll be prompted for the password)
2. Install Homebrew + run `brew bundle install`
3. rsync `$HOME` dotfiles into place
4. Restore VS Code settings + install extensions
5. rsync extras (large dirs you opted in to) back to their original locations
6. Apply `macos-defaults.json` via `defaults write`
7. Clone oh-my-zsh
8. Print a manual checklist for things it can't automate (SSH keys, gh auth login, etc.)

## Configuration

Edit `defaults/config.json` to change:
- `outputDir` — where backups land
- `include.home` — which `$HOME` files to track
- `exclude` — secrets-gate glob patterns
- `scanForLarge.minSizeMB` — threshold for large-dir prompts
- `scanForLarge.autoSkip` — paths pre-unchecked in the prompt
- `secretsGate.mode` — `hardFail` (default) or `softWarn`

Use a different config: `node src/mac-backup/index.js backup --config /path/to/config.json`

## Files

```
src/mac-backup/
├── index.js                # CLI entry
├── backup.js               # Backup orchestrator
├── scanner.js              # du-based size scan + inquirer prompts
├── crypto.js               # openssl spawn wrapper (AES-256-CBC + PBKDF2)
├── archive.js              # tar spawn wrapper
├── manifest.js             # config loader + manifest builder
├── logger.js               # .log writer
└── defaults/
    ├── config.json         # Backup configuration
    ├── macos-defaults.json # System tweaks to apply on restore
    ├── Brewfile.starter    # Bootstrap dev app list
    └── restore-template.sh # Template for the generated restore script
```

## Notes

- Encryption: AES-256-CBC with PBKDF2 (200k iterations). Uses macOS's built-in LibreSSL.
- The restore script is **pure bash + python3** — no Node required on the new Mac.
- Password is passed via env var (not CLI args), never visible in `ps`.
- The `config.json` sibling lets you audit what's in the backup *without* decrypting.
