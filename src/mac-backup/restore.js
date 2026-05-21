import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawnSync } from 'node:child_process';

import { loadConfig } from './manifest.js';
import { decrypt } from './crypto.js';
import { archiveExtract, assertArchiveTools } from './archive.js';
import { promptPassword } from './prompt.js';

function rsyncBack(src, dest) {
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  const args = ['-a'];
  args.push(src.endsWith('/') ? src : src + '/', dest + '/');
  const r = spawnSync('rsync', args, { stdio: ['ignore', 'inherit', 'inherit'] });
  if (r.status !== 0) throw new Error(`rsync failed: ${src} -> ${dest}`);
}

function copyBack(src, dest) {
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(src, dest);
}

async function decryptAndExtract({ encPath, password, encryption, workDir }) {
  const archivePath = path.join(workDir, 'archive.tar.zst');
  await decrypt({ inFile: encPath, outFile: archivePath, password, encryption });
  const extract = path.join(workDir, 'extracted');
  fs.mkdirSync(extract, { recursive: true });
  await archiveExtract({ archiveFile: archivePath, dest: extract });
  fs.rmSync(archivePath, { force: true });
  return extract;
}

function loadManifest(bundleDir) {
  const cfgPath = path.join(bundleDir, 'config.json');
  if (!fs.existsSync(cfgPath)) throw new Error(`Missing config.json in ${bundleDir}`);
  return JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
}

export async function runRestore({ bundleDir } = {}) {
  if (!bundleDir) throw new Error('Usage: mac-restore <bundle-folder>');
  assertArchiveTools();
  bundleDir = path.resolve(bundleDir);
  if (!fs.existsSync(bundleDir)) throw new Error(`Bundle dir not found: ${bundleDir}`);

  const manifest = loadManifest(bundleDir);
  const cfg = loadConfig();
  const encPath = path.join(bundleDir, 'main.tar.zst.enc');
  if (!fs.existsSync(encPath)) throw new Error(`Missing main.tar.zst.enc in ${bundleDir}`);

  console.log(`\n→ mac-restore`);
  console.log(`  Bundle: ${bundleDir}`);
  console.log(`  Created: ${manifest.timestamp} on ${manifest.hostname}`);
  console.log(`  Items: ${manifest.items.length}`);

  const password = await promptPassword({ confirm: false });

  const workDir = fs.mkdtempSync(path.join(os.tmpdir(), `mac-restore-${manifest.timestamp}-`));
  console.log('\n→ Decrypting + extracting main.tar.zst.enc');
  const extract = await decryptAndExtract({
    encPath,
    password,
    encryption: manifest.encryption || cfg.encryption,
    workDir
  });

  // Walk items and restore each
  for (const item of manifest.items) {
    const src = path.join(extract, item.archivePath);
    if (!fs.existsSync(src)) {
      console.log(`  skip (not in archive): ${item.archivePath}`);
      continue;
    }

    switch (item.type) {
      case 'home':
      case 'vscode-file':
      case 'macos-defaults':
      case 'brewfile':
      case 'vscode-extensions': {
        if (item.source) {
          copyBack(src, item.source);
          console.log(`  ✓ ${item.archivePath} -> ${item.source}`);
        } else {
          // Brewfile and similar: just print, runner handles below
          console.log(`  ✓ ${item.archivePath}  (handled separately)`);
        }
        break;
      }
      case 'vscode-dir':
      case 'user-dir':
      case 'extra': {
        rsyncBack(src, item.source);
        console.log(`  ✓ ${item.archivePath} -> ${item.source}`);
        break;
      }
      default:
        console.log(`  ? unknown type ${item.type} -> skipping ${item.archivePath}`);
    }
  }

  // Brewfile install
  const brewfileSrc = path.join(extract, 'Brewfile');
  if (fs.existsSync(brewfileSrc)) {
    console.log('\n→ Running brew bundle install');
    if (!spawnSync('which', ['brew']).status === 0) {
      console.log('  ! Homebrew not installed. Install it first:');
      console.log('    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"');
    } else {
      const r = spawnSync('brew', ['bundle', 'install', '--file', brewfileSrc], {
        stdio: ['ignore', 'inherit', 'inherit']
      });
      if (r.status !== 0) console.log('  ! brew bundle had failures — review and re-run');
    }
  }

  // VS Code extensions
  const extensionsTxt = path.join(extract, 'vscode', 'extensions.txt');
  if (fs.existsSync(extensionsTxt)) {
    if (spawnSync('which', ['code']).status === 0) {
      console.log('\n→ Installing VS Code extensions');
      const list = fs.readFileSync(extensionsTxt, 'utf8').split('\n').filter(Boolean);
      for (const ext of list) {
        spawnSync('code', ['--install-extension', ext], { stdio: ['ignore', 'inherit', 'inherit'] });
      }
    } else {
      console.log('\n  ! `code` CLI not on PATH — install via VS Code, then run:');
      console.log(`    xargs -L1 code --install-extension < ${extensionsTxt}`);
    }
  }

  // macOS defaults
  const defaultsJson = path.join(extract, 'macos-defaults.json');
  if (fs.existsSync(defaultsJson)) {
    console.log('\n→ Applying macOS defaults');
    const data = JSON.parse(fs.readFileSync(defaultsJson, 'utf8'));
    for (const entry of data.defaults || []) {
      let value = entry.value;
      if (entry.type === 'string') value = expandHomeStr(String(value));
      if (entry.type === 'bool') value = value ? 'true' : 'false';
      spawnSync('defaults', ['write', entry.domain, entry.key, `-${entry.type}`, String(value)], {
        stdio: ['ignore', 'inherit', 'inherit']
      });
    }
    spawnSync('killall', ['Finder', 'Dock', 'SystemUIServer'], { stdio: 'ignore' });
    console.log('  ✓ defaults applied');
  }

  // oh-my-zsh
  const ohmyzsh = path.join(os.homedir(), '.oh-my-zsh');
  if (!fs.existsSync(ohmyzsh)) {
    console.log('\n→ Cloning oh-my-zsh');
    spawnSync('git', ['clone', '--depth=1', 'https://github.com/ohmyzsh/ohmyzsh.git', ohmyzsh], {
      stdio: ['ignore', 'inherit', 'inherit']
    });
  }

  fs.rmSync(workDir, { recursive: true, force: true });

  console.log('\n' + '='.repeat(60));
  console.log('Main restore complete.');
  console.log('='.repeat(60));
  console.log('\nNot done by main restore:');
  console.log('  • Security files (~/.ssh, AWS creds, tokens) — run:');
  console.log(`      npm run mac-restore-security ${bundleDir}`);
  console.log('  • Sign in to VS Code Settings Sync, 1Password, browsers');
  console.log('  • gh auth login, aws sso login, docker login');
}

function expandHomeStr(s) {
  if (s.startsWith('~/')) return path.join(os.homedir(), s.slice(2));
  if (s === '~') return os.homedir();
  return s;
}
