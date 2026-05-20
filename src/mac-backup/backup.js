import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawnSync } from 'node:child_process';
import inquirer from 'inquirer';

import { loadConfig, expandHome, timestamp, buildManifest, defaultsDir } from './manifest.js';
import { scanLargeDirs } from './scanner.js';
import { encrypt } from './crypto.js';
import { tarCreate } from './archive.js';
import { writeLog } from './logger.js';

function globToRegex(glob) {
  // simple **/, *, ? handling
  let re = glob
    .replace(/[.+^${}()|[\]\\]/g, '\\$&')
    .replace(/\*\*\//g, '(?:.*/)?')
    .replace(/\*\*/g, '.*')
    .replace(/\*/g, '[^/]*')
    .replace(/\?/g, '[^/]');
  return new RegExp('^' + re + '$');
}

function isSecret(filePath, patterns) {
  const regs = patterns.map(globToRegex);
  return regs.some((r) => r.test(filePath));
}

function copyFileEnsure(src, dest) {
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(src, dest);
}

function copyDirRsync(src, dest) {
  fs.mkdirSync(dest, { recursive: true });
  const r = spawnSync('rsync', ['-a', src.endsWith('/') ? src : src + '/', dest + '/'], {
    stdio: ['ignore', 'inherit', 'inherit']
  });
  if (r.status !== 0) throw new Error(`rsync failed for ${src} -> ${dest}`);
}

function walkFiles(dir) {
  const out = [];
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walkFiles(full));
    else if (entry.isFile() || entry.isSymbolicLink()) out.push(full);
  }
  return out;
}

function safeName(p) {
  return p
    .replace(/^\/Users\/[^/]+\//, '')
    .replace(/^\//, '')
    .replace(/\//g, '__');
}

let _stdinBuffer = '';
let _stdinAttached = false;

function readSecret(prompt) {
  return new Promise((resolve, reject) => {
    const stdin = process.stdin;
    const stdout = process.stdout;
    const isTTY = stdin.isTTY;

    stdout.write(prompt);

    if (isTTY) {
      stdin.setRawMode(true);
      stdin.resume();
      stdin.setEncoding('utf8');
      let buf = '';
      const onData = (key) => {
        if (key === '\r' || key === '\n' || key === '') {
          stdin.setRawMode(false);
          stdin.pause();
          stdin.removeListener('data', onData);
          stdout.write('\n');
          resolve(buf);
        } else if (key === '') {
          stdin.setRawMode(false);
          stdout.write('\n');
          reject(new Error('Aborted'));
        } else if (key === '' || key === '\b') {
          if (buf.length > 0) {
            buf = buf.slice(0, -1);
            stdout.write('\b \b');
          }
        } else {
          buf += key;
          stdout.write('*');
        }
      };
      stdin.on('data', onData);
    } else {
      // Non-TTY: read one line from stdin (with shared buffer across calls)
      const tryResolve = () => {
        const nl = _stdinBuffer.indexOf('\n');
        if (nl !== -1) {
          const line = _stdinBuffer.slice(0, nl);
          _stdinBuffer = _stdinBuffer.slice(nl + 1);
          resolve(line);
          return true;
        }
        return false;
      };
      if (tryResolve()) {
        stdout.write('\n');
        return;
      }
      stdin.setEncoding('utf8');
      const onData = (chunk) => {
        _stdinBuffer += chunk;
        if (tryResolve()) {
          stdin.removeListener('data', onData);
          stdout.write('\n');
        }
      };
      stdin.on('data', onData);
      if (!_stdinAttached) {
        stdin.resume();
        _stdinAttached = true;
      }
    }
  });
}

async function promptPassword() {
  const p1 = await readSecret('Encryption password: ');
  const p2 = await readSecret('Confirm password:    ');
  if (p1 !== p2) throw new Error('Passwords did not match');
  if (p1.length < 8) throw new Error('Password must be at least 8 characters');
  return p1;
}

export async function runBackup({ configPath, allowSecrets } = {}) {
  const cfg = loadConfig(configPath);
  const ts = timestamp();
  const hostname = os.hostname();

  console.log(`\n→ mac-backup ${ts}`);
  console.log(`  Config: ${configPath || 'defaults/config.json'}`);
  console.log(`  Output: ${cfg.outputDir}`);

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
      const dest = path.join(staging, 'vscode', f);
      copyFileEnsure(src, dest);
      items.push({ type: 'vscode-file', source: src, archivePath: path.join('vscode', f) });
      console.log(`  ✓ ${f}`);
    }
    for (const d of cfg.include.vscode.dirs || []) {
      const src = path.join(vsc, d);
      if (!fs.existsSync(src)) {
        console.log(`  skip (not found): ${d}/`);
        continue;
      }
      const dest = path.join(staging, 'vscode', d);
      copyDirRsync(src, dest);
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
        console.log(`  ! could not run 'code --list-extensions' (CLI not on PATH)`);
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

  // 4. macOS defaults JSON (copy into archive so restore can apply it)
  if (cfg.include.macosDefaults) {
    const src = path.join(defaultsDir(), '..', cfg.include.macosDefaults);
    const resolved = fs.existsSync(src) ? src : path.join(defaultsDir(), 'macos-defaults.json');
    if (fs.existsSync(resolved)) {
      const dest = path.join(staging, 'macos-defaults.json');
      fs.copyFileSync(resolved, dest);
      items.push({ type: 'macos-defaults', archivePath: 'macos-defaults.json' });
      console.log('\n→ macOS defaults file: ✓');
    }
  }

  // 5. Large dirs (interactive)
  console.log('\n→ Scanning for large directories');
  const extras = await scanLargeDirs(cfg);
  if (extras.length) {
    console.log(`\n→ Copying ${extras.length} extra path(s)`);
    for (const p of extras) {
      const name = safeName(p);
      const dest = path.join(staging, 'extras', name);
      try {
        if (fs.statSync(p).isDirectory()) copyDirRsync(p, dest);
        else copyFileEnsure(p, dest);
        items.push({ type: 'extra', source: p, archivePath: path.join('extras', name) });
        console.log(`  ✓ ${p}`);
      } catch (e) {
        console.log(`  ! failed: ${p} (${e.message})`);
      }
    }
  }

  // 6. Secrets gate
  console.log('\n→ Running secrets gate');
  const allFiles = walkFiles(staging);
  const offenders = [];
  for (const f of allFiles) {
    const rel = path.relative(staging, f);
    if (isSecret(rel, cfg.exclude || [])) offenders.push(rel);
  }
  if (offenders.length) {
    const mode = cfg.secretsGate?.mode || 'hardFail';
    if (mode === 'hardFail' && !allowSecrets) {
      console.error('\n  ✗ Secrets gate matched the following paths:');
      for (const o of offenders) console.error('    - ' + o);
      console.error(`\n  Aborting. To override, re-run with --allow-secrets-warning`);
      fs.rmSync(staging, { recursive: true, force: true });
      process.exit(2);
    }
    // Soft mode or override: remove offenders and warn
    console.log(`  ! ${offenders.length} secret-like file(s) removed from staging:`);
    for (const o of offenders) {
      console.log('    - ' + o);
      fs.rmSync(path.join(staging, o), { force: true });
    }
  } else {
    console.log('  ✓ no secrets detected');
  }

  // 7. Manifest
  const manifest = buildManifest({ ts, hostname, items });
  fs.writeFileSync(path.join(staging, 'config.json'), JSON.stringify(manifest, null, 2));

  // 8. Tar
  console.log('\n→ Building tar archive');
  const stagingEntries = fs.readdirSync(staging);
  const tarPath = path.join(os.tmpdir(), `${ts}.tar`);
  await tarCreate({ cwd: staging, outFile: tarPath, includeRelative: stagingEntries });
  const tarSize = fs.statSync(tarPath).size;
  console.log(`  ✓ ${(tarSize / 1024 / 1024).toFixed(1)} MB`);

  // 9. Encrypt
  console.log('\n→ Encrypting');
  const password = await promptPassword();
  fs.mkdirSync(cfg.outputDir, { recursive: true });
  const encPath = path.join(cfg.outputDir, `${ts}.tar.enc`);
  await encrypt({
    inFile: tarPath,
    outFile: encPath,
    password,
    encryption: cfg.encryption
  });
  fs.rmSync(tarPath, { force: true });
  const encSize = fs.statSync(encPath).size;
  console.log(`  ✓ ${(encSize / 1024 / 1024).toFixed(1)} MB`);

  // 10. Sibling config.json (manifest copy outside archive)
  const cfgOutPath = path.join(cfg.outputDir, `${ts}.config.json`);
  fs.writeFileSync(cfgOutPath, JSON.stringify(manifest, null, 2));

  // 11. .log
  const logPath = path.join(cfg.outputDir, `${ts}.log`);
  writeLog(logPath, {
    'Backup': {
      timestamp: ts,
      hostname,
      macos: os.release(),
      node: process.version,
      output: cfg.outputDir,
      tarSizeMB: +(tarSize / 1024 / 1024).toFixed(2),
      encSizeMB: +(encSize / 1024 / 1024).toFixed(2)
    },
    'Items included': items.map((i) => `${i.type.padEnd(18)} ${i.archivePath}${i.source ? '  <- ' + i.source : ''}`),
    'Secrets gate offenders (skipped or aborted)': offenders.length ? offenders : ['(none)']
  });

  // 12. Generate uncrypt-and-restore-<ts>.sh from template
  const tplPath = path.join(defaultsDir(), 'restore-template.sh');
  let tpl = fs.readFileSync(tplPath, 'utf8');
  tpl = tpl
    .replace(/\{\{TS\}\}/g, ts)
    .replace(/\{\{ENC_ALGO\}\}/g, cfg.encryption.algo)
    .replace(/\{\{ENC_KDF\}\}/g, cfg.encryption.kdf)
    .replace(/\{\{ENC_ITER\}\}/g, String(cfg.encryption.iter));
  const restorePath = path.join(cfg.outputDir, `uncrypt-and-restore-${ts}.sh`);
  fs.writeFileSync(restorePath, tpl);
  fs.chmodSync(restorePath, 0o755);

  // 13. Cleanup staging
  fs.rmSync(staging, { recursive: true, force: true });

  // Summary
  console.log('\n' + '='.repeat(60));
  console.log('Backup complete. 4 files in ' + cfg.outputDir + ':');
  console.log('  ' + path.basename(encPath));
  console.log('  ' + path.basename(restorePath));
  console.log('  ' + path.basename(cfgOutPath));
  console.log('  ' + path.basename(logPath));
  console.log('='.repeat(60));
  console.log('\nTo restore on a new Mac:');
  console.log('  1. Copy all 4 files to the new Mac');
  console.log(`  2. cd to that folder and run:  bash ${path.basename(restorePath)}`);
}
