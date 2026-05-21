import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawnSync } from 'node:child_process';
import { promptPassword } from './prompt.js';

import { loadConfig, expandHome, timestamp, buildManifest, defaultsDir } from './manifest.js';
import { scanLargeDirs } from './scanner.js';
import { encrypt } from './crypto.js';
import { archiveCreate, assertArchiveTools } from './archive.js';
import { writeLog } from './logger.js';

function globToRegex(glob) {
  // Tokenize to avoid the trap of re-replacing chars we just emitted.
  const TOK = { DSLASH: '\x00A\x00', DSTAR: '\x00B\x00', STAR: '\x00C\x00', Q: '\x00D\x00' };
  let s = glob
    .replace(/\*\*\//g, TOK.DSLASH)
    .replace(/\*\*/g, TOK.DSTAR)
    .replace(/\*/g, TOK.STAR)
    .replace(/\?/g, TOK.Q);
  s = s.replace(/[.+^${}()|[\]\\]/g, '\\$&');
  s = s
    .replace(new RegExp(TOK.DSLASH, 'g'), '(?:.*/)?')
    .replace(new RegExp(TOK.DSTAR, 'g'), '.*')
    .replace(new RegExp(TOK.STAR, 'g'), '[^/]*')
    .replace(new RegExp(TOK.Q, 'g'), '[^/]');
  return new RegExp('^' + s + '$');
}

function matchesAny(p, regs) {
  return regs.some((r) => r.test(p));
}

function copyFileEnsure(src, dest) {
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(src, dest);
}

function copyDirRsync(src, dest, excludes = []) {
  fs.mkdirSync(dest, { recursive: true });
  const args = ['-a'];
  for (const ex of excludes) args.push('--exclude', ex);
  args.push(src.endsWith('/') ? src : src + '/', dest + '/');
  const r = spawnSync('rsync', args, {
    stdio: ['ignore', 'inherit', 'inherit']
  });
  if (r.status !== 0) throw new Error(`rsync failed for ${src} -> ${dest}`);
}

// Node-native recursive copy that skips sockets/FIFOs/devices and preserves
// symlinks + file modes. Used for security paths (e.g. ~/.ssh) where macOS's
// openrsync trips over Unix domain sockets like the SSH agent socket.
function copyDirSafe(src, dest) {
  const srcStat = fs.lstatSync(src);
  fs.mkdirSync(dest, { recursive: true });
  fs.chmodSync(dest, srcStat.mode & 0o7777);
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const s = path.join(src, entry.name);
    const d = path.join(dest, entry.name);
    if (entry.isSocket() || entry.isFIFO() || entry.isCharacterDevice() || entry.isBlockDevice()) {
      continue;
    }
    if (entry.isSymbolicLink()) {
      fs.symlinkSync(fs.readlinkSync(s), d);
    } else if (entry.isDirectory()) {
      copyDirSafe(s, d);
    } else if (entry.isFile()) {
      fs.copyFileSync(s, d);
      fs.chmodSync(d, fs.lstatSync(s).mode & 0o7777);
    }
  }
}

function safeName(p) {
  return p
    .replace(/^\/Users\/[^/]+\//, '')
    .replace(/^\//, '')
    .replace(/\//g, '__');
}

function walkFiles(dir, base = dir) {
  const out = [];
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walkFiles(full, base));
    else if (entry.isFile() || entry.isSymbolicLink()) {
      out.push({ full, rel: path.relative(base, full) });
    }
  }
  return out;
}

function moveFile(src, dest) {
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.renameSync(src, dest);
}

function removeEmptyDirs(root) {
  if (!fs.existsSync(root)) return;
  for (const name of fs.readdirSync(root)) {
    const p = path.join(root, name);
    const st = fs.lstatSync(p);
    if (st.isDirectory()) {
      removeEmptyDirs(p);
      try {
        if (fs.readdirSync(p).length === 0) fs.rmdirSync(p);
      } catch {}
    }
  }
}

export async function runBackup({ configPath, skipSecurity: skipFlag } = {}) {
  assertArchiveTools();
  const cfg = loadConfig(configPath);
  const ts = timestamp();
  const hostname = os.hostname();
  const skipSecurity = skipFlag || cfg.skipSecurity === true;

  const bundleDir = path.join(cfg.outputDir, `${ts}-bkp`);
  console.log(`\n→ mac-backup ${ts}`);
  console.log(`  Config: ${configPath || 'defaults/config.json'}`);
  console.log(`  Bundle: ${bundleDir}`);
  console.log(`  Security archive: ${skipSecurity ? 'SKIPPED' : 'enabled'}`);

  const staging = fs.mkdtempSync(path.join(os.tmpdir(), `mac-backup-${ts}-`));
  const items = [];

  // 1. HOME dotfiles
  console.log('\n→ Collecting $HOME files');
  for (const rel of cfg.include.home || []) {
    const src = path.join(os.homedir(), rel);
    if (!fs.existsSync(src)) {
      console.log(`  skip (not found): ${rel}`);
      continue;
    }
    const dest = path.join(staging, 'home', rel);
    copyFileEnsure(src, dest);
    items.push({ type: 'home', source: src, archivePath: path.join('home', rel) });
    console.log(`  ✓ ${rel}`);
  }

  // 2. VS Code
  if (cfg.include.vscode) {
    console.log('\n→ Collecting VS Code config');
    const vsc = cfg.include.vscode.userDir;
    for (const f of cfg.include.vscode.files || []) {
      const src = path.join(vsc, f);
      if (!fs.existsSync(src)) {
        console.log(`  skip (not found): ${f}`);
        continue;
      }
      copyFileEnsure(src, path.join(staging, 'vscode', f));
      items.push({ type: 'vscode-file', source: src, archivePath: path.join('vscode', f) });
      console.log(`  ✓ ${f}`);
    }
    for (const d of cfg.include.vscode.dirs || []) {
      const src = path.join(vsc, d);
      if (!fs.existsSync(src)) {
        console.log(`  skip (not found): ${d}/`);
        continue;
      }
      copyDirRsync(src, path.join(staging, 'vscode', d));
      items.push({ type: 'vscode-dir', source: src, archivePath: path.join('vscode', d) });
      console.log(`  ✓ ${d}/`);
    }
    if (cfg.include.vscode.exportExtensions) {
      const out = spawnSync('code', ['--list-extensions'], { encoding: 'utf8' });
      const extPath = path.join(staging, 'vscode', 'extensions.txt');
      if (out.status === 0) {
        fs.mkdirSync(path.dirname(extPath), { recursive: true });
        fs.writeFileSync(extPath, out.stdout, 'utf8');
        items.push({ type: 'vscode-extensions', archivePath: 'vscode/extensions.txt' });
        const count = out.stdout.trim().split('\n').filter(Boolean).length;
        console.log(`  ✓ extensions.txt (${count})`);
      } else {
        console.log(`  ! 'code' CLI not on PATH — skipping extensions list`);
      }
    }
  }

  // 3. Brewfile
  if (cfg.include.brew?.dumpBrewfile) {
    console.log('\n→ Dumping Brewfile');
    const brewfilePath = path.join(staging, 'Brewfile');
    const r = spawnSync('brew', ['bundle', 'dump', '--force', '--file', brewfilePath], {
      stdio: ['ignore', 'inherit', 'inherit']
    });
    if (r.status === 0) {
      items.push({ type: 'brewfile', archivePath: 'Brewfile' });
      const lines = fs.readFileSync(brewfilePath, 'utf8').split('\n').filter(Boolean);
      console.log(`  ✓ Brewfile (${lines.length} entries)`);
    } else {
      console.log('  ! brew bundle dump failed');
    }
  }

  // 4. macOS defaults
  if (cfg.include.macosDefaults) {
    const src = path.join(defaultsDir(), '..', cfg.include.macosDefaults);
    const resolved = fs.existsSync(src) ? src : path.join(defaultsDir(), 'macos-defaults.json');
    if (fs.existsSync(resolved)) {
      fs.copyFileSync(resolved, path.join(staging, 'macos-defaults.json'));
      items.push({ type: 'macos-defaults', archivePath: 'macos-defaults.json' });
      console.log('\n→ macOS defaults file: ✓');
    }
  }

  // 5a. Interactive review of large subdirs inside include.dirs.
  //     Returns absolute paths the user UNCHECKED — fed in as rsync excludes.
  console.log('\n→ Scanning for large directories inside include.dirs');
  const userExcludePaths = await scanLargeDirs(cfg);

  // 5b. include.dirs (wholesale copy with pattern excludes + user-picked excludes)
  if (Array.isArray(cfg.include?.dirs) && cfg.include.dirs.length) {
    console.log('\n→ Copying whole directories from include.dirs');
    const baseExcludes = [...(cfg.include.dirExcludePatterns || [])];
    const outputBase = path.basename(cfg.outputDir);
    if (!baseExcludes.includes(outputBase)) baseExcludes.push(outputBase);

    for (const rawPath of cfg.include.dirs) {
      const src = expandHome(rawPath);
      if (!fs.existsSync(src)) {
        console.log(`  skip (not found): ${rawPath}`);
        continue;
      }
      const name = safeName(src);
      const dest = path.join(staging, 'userdirs', name);

      // Per-source excludes: config patterns + any user-deselected paths
      // under this src, converted to /-anchored rsync patterns relative to src.
      const excludes = [...baseExcludes];
      for (const abs of userExcludePaths) {
        if (abs === src) continue;
        const rel = path.relative(src, abs);
        if (!rel || rel.startsWith('..')) continue;
        excludes.push('/' + rel);
      }

      try {
        const stat = fs.statSync(src);
        if (stat.isDirectory()) copyDirRsync(src, dest, excludes);
        else copyFileEnsure(src, dest);
        items.push({
          type: 'user-dir',
          source: src,
          archivePath: path.join('userdirs', name)
        });
        console.log(`  ✓ ${rawPath}`);
      } catch (e) {
        console.log(`  ! failed: ${rawPath} (${e.message})`);
      }
    }
  }

  // 7. Manifest in staging (also goes into the archives)
  const manifest = buildManifest({ ts, hostname, items, encryption: cfg.encryption });
  manifest.skipSecurity = skipSecurity;
  fs.writeFileSync(path.join(staging, 'config.json'), JSON.stringify(manifest, null, 2));

  // 8. Split into security vs main
  console.log('\n→ Splitting security files');
  const securityStaging = fs.mkdtempSync(path.join(os.tmpdir(), `mac-backup-sec-${ts}-`));
  const securityPathMap = []; // { archivePath, target }
  const securityPatterns = (cfg.include.security?.patterns || []).map(globToRegex);

  // 8a. Patterns: scan staging tree, move matches into securityStaging at same relative path
  const all = walkFiles(staging);
  let movedByPattern = 0;
  for (const { full, rel } of all) {
    if (rel === 'config.json') continue;
    if (!matchesAny(rel, securityPatterns)) continue;

    // Compute target = original source by mapping prefix via items
    let target = null;
    for (const it of items) {
      if (!it.source) continue;
      if (rel === it.archivePath) {
        target = it.source;
        break;
      }
      const pfx = it.archivePath + '/';
      if (rel.startsWith(pfx)) {
        target = path.join(it.source, rel.slice(pfx.length));
        break;
      }
    }
    if (!target) {
      // Top-level non-mapped (Brewfile, macos-defaults.json) — leave in main
      continue;
    }

    const secDest = path.join(securityStaging, rel);
    moveFile(full, secDest);
    securityPathMap.push({ archivePath: rel, target });
    movedByPattern++;
  }
  removeEmptyDirs(staging);

  // 8b. alsoInclude paths: copy directly into securityStaging/security-home/...
  for (const raw of cfg.include.security?.alsoInclude || []) {
    const src = expandHome(raw);
    if (!fs.existsSync(src)) {
      console.log(`  skip (not found): ${raw}`);
      continue;
    }
    const rel = path.relative(os.homedir(), src);
    const archivePath = path.join('security-home', rel);
    const dest = path.join(securityStaging, archivePath);
    try {
      if (fs.statSync(src).isDirectory()) copyDirSafe(src, dest);
      else copyFileEnsure(src, dest);
      securityPathMap.push({ archivePath, target: src });
      console.log(`  ✓ ${raw}`);
    } catch (e) {
      console.log(`  ! failed: ${raw} (${e.message})`);
    }
  }

  // 8c. Write security manifest
  if (securityPathMap.length) {
    fs.writeFileSync(
      path.join(securityStaging, 'security-paths.json'),
      JSON.stringify({ version: 1, timestamp: ts, paths: securityPathMap }, null, 2)
    );
  }
  console.log(`  ${movedByPattern} file(s) moved by pattern, ${securityPathMap.length - movedByPattern} alsoInclude path(s)`);

  // 9. Password
  console.log('\n→ Encryption password');
  const password = await promptPassword();

  // 10. Make bundle folder
  fs.mkdirSync(bundleDir, { recursive: true });

  // 11. Archive + encrypt MAIN
  console.log('\n→ Archiving main (tar.zst)');
  const mainArchive = path.join(os.tmpdir(), `main-${ts}.tar.zst`);
  const stagingEntries = fs.readdirSync(staging);
  if (stagingEntries.length === 0) throw new Error('Main staging is empty — nothing to back up');
  await archiveCreate({ cwd: staging, outFile: mainArchive, includeRelative: stagingEntries });
  const mainArchiveSize = fs.statSync(mainArchive).size;
  console.log(`  ✓ ${(mainArchiveSize / 1024 / 1024).toFixed(1)} MB`);

  console.log('→ Encrypting main');
  const mainEnc = path.join(bundleDir, 'main.tar.zst.enc');
  await encrypt({ inFile: mainArchive, outFile: mainEnc, password, encryption: cfg.encryption });
  fs.rmSync(mainArchive, { force: true });
  const mainEncSize = fs.statSync(mainEnc).size;
  console.log(`  ✓ ${(mainEncSize / 1024 / 1024).toFixed(1)} MB`);

  // 12. Archive + encrypt SECURITY (unless skipped or empty)
  let securityEncSize = 0;
  if (!skipSecurity && securityPathMap.length) {
    console.log('\n→ Archiving security (tar.zst)');
    const secArchive = path.join(os.tmpdir(), `security-${ts}.tar.zst`);
    const secEntries = fs.readdirSync(securityStaging);
    await archiveCreate({ cwd: securityStaging, outFile: secArchive, includeRelative: secEntries });
    const secArchiveSize = fs.statSync(secArchive).size;
    console.log(`  ✓ ${(secArchiveSize / 1024 / 1024).toFixed(2)} MB`);

    console.log('→ Encrypting security');
    const secEnc = path.join(bundleDir, 'security.tar.zst.enc');
    await encrypt({ inFile: secArchive, outFile: secEnc, password, encryption: cfg.encryption });
    fs.rmSync(secArchive, { force: true });
    securityEncSize = fs.statSync(secEnc).size;
    console.log(`  ✓ ${(securityEncSize / 1024 / 1024).toFixed(2)} MB`);
  } else if (skipSecurity) {
    console.log('\n→ Security archive: SKIPPED (skipSecurity=true)');
  } else {
    console.log('\n→ Security archive: skipped (nothing matched)');
  }

  // 13. Write sibling config.json + log + README
  fs.writeFileSync(path.join(bundleDir, 'config.json'), JSON.stringify(manifest, null, 2));

  writeLog(path.join(bundleDir, 'files.log'), {
    Backup: {
      timestamp: ts,
      hostname,
      macos: os.release(),
      node: process.version,
      bundleDir,
      mainEncSizeMB: +(mainEncSize / 1024 / 1024).toFixed(2),
      securityEncSizeMB: +(securityEncSize / 1024 / 1024).toFixed(2),
      skipSecurity
    },
    'Items (main archive)': items.map(
      (i) => `${i.type.padEnd(18)} ${i.archivePath}${i.source ? '  <- ' + i.source : ''}`
    ),
    'Security paths': securityPathMap.length
      ? securityPathMap.map((p) => `${p.archivePath}  ->  ${p.target}`)
      : ['(none)']
  });

  writeRestoreReadme(bundleDir, { ts, hostname, hasSecurity: !!securityPathMap.length && !skipSecurity });

  // 14. Cleanup
  fs.rmSync(staging, { recursive: true, force: true });
  fs.rmSync(securityStaging, { recursive: true, force: true });

  // 15. Summary
  console.log('\n' + '='.repeat(60));
  console.log('Backup complete. Files in ' + bundleDir + ':');
  for (const f of fs.readdirSync(bundleDir)) console.log('  ' + f);
  console.log('='.repeat(60));
  console.log('\nTo restore on a new Mac (assumes this repo is cloned):');
  console.log(`  npm run mac-restore ${bundleDir}`);
  if (securityPathMap.length && !skipSecurity) {
    console.log(`  npm run mac-restore-security ${bundleDir}`);
  }
}

function writeRestoreReadme(bundleDir, { ts, hostname, hasSecurity }) {
  const body = `mac-backup bundle
==================

Created: ${ts}
Source : ${hostname}

Files in this folder
--------------------
  main.tar.zst.enc      Main archive (dotfiles, VS Code, Brewfile, ~/Documents, ...)
${hasSecurity ? '  security.tar.zst.enc  Security archive (~/.ssh, AWS creds, tokens, *.pem, *.key)\n' : ''}  config.json           Manifest (what's in the archive, where it maps back)
  files.log             Human-readable list of contents
  README.txt            This file

How to restore
--------------

Prerequisites on the new Mac:

  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
  brew install git node zstd

Clone the tools repo and install deps:

  git clone https://github.com/ldiasrs/personal-dev-tools.git
  cd personal-dev-tools && npm install

Restore main bundle (Brewfile, dotfiles, VS Code, ~/Documents, ...):

  npm run mac-restore /path/to/this/${ts}-bkp

${hasSecurity ? `Restore security files (separate password if you used one):

  npm run mac-restore-security /path/to/this/${ts}-bkp

` : ''}Inspect what's inside before restoring (no decryption needed):

  cat config.json | jq .
  less files.log
`;
  fs.writeFileSync(path.join(bundleDir, 'README.txt'), body);
}
