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
  const args = ['-a', src.endsWith('/') ? src : src + '/', dest + '/'];
  const r = spawnSync('rsync', args, { stdio: ['ignore', 'inherit', 'inherit'] });
  if (r.status !== 0) throw new Error(`rsync failed: ${src} -> ${dest}`);
}

function copyBack(src, dest) {
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(src, dest);
}

function chmodSshKeys() {
  const ssh = path.join(os.homedir(), '.ssh');
  if (!fs.existsSync(ssh)) return;
  spawnSync('chmod', ['700', ssh]);
  for (const name of fs.readdirSync(ssh)) {
    const p = path.join(ssh, name);
    if (!fs.statSync(p).isFile()) continue;
    if (name.endsWith('.pub')) spawnSync('chmod', ['644', p]);
    else spawnSync('chmod', ['600', p]);
  }
}

export async function runRestoreSecurity({ bundleDir } = {}) {
  if (!bundleDir) throw new Error('Usage: mac-restore-security <bundle-folder>');
  assertArchiveTools();
  bundleDir = path.resolve(bundleDir);
  const encPath = path.join(bundleDir, 'security.tar.zst.enc');
  const cfgPath = path.join(bundleDir, 'config.json');
  if (!fs.existsSync(encPath)) {
    console.log('No security.tar.zst.enc in this bundle (or skipSecurity was true at backup time).');
    return;
  }
  const manifest = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
  const cfg = loadConfig();

  console.log(`\n→ mac-restore-security`);
  console.log(`  Bundle: ${bundleDir}`);
  console.log(`  Created: ${manifest.timestamp} on ${manifest.hostname}`);

  const password = await promptPassword({ confirm: false });

  const workDir = fs.mkdtempSync(path.join(os.tmpdir(), `mac-restore-sec-`));
  console.log('\n→ Decrypting + extracting security.tar.zst.enc');
  const archivePath = path.join(workDir, 'security.tar.zst');
  await decrypt({
    inFile: encPath,
    outFile: archivePath,
    password,
    encryption: manifest.encryption || cfg.encryption
  });
  const extract = path.join(workDir, 'extracted');
  fs.mkdirSync(extract, { recursive: true });
  await archiveExtract({ archiveFile: archivePath, dest: extract });
  fs.rmSync(archivePath, { force: true });

  // Read security-paths.json from inside the archive
  const mapPath = path.join(extract, 'security-paths.json');
  if (!fs.existsSync(mapPath)) {
    throw new Error('security-paths.json missing inside security archive');
  }
  const map = JSON.parse(fs.readFileSync(mapPath, 'utf8'));
  console.log(`  ${map.paths.length} path(s) to restore`);

  for (const { archivePath, target } of map.paths) {
    const src = path.join(extract, archivePath);
    if (!fs.existsSync(src)) {
      console.log(`  skip (not in archive): ${archivePath}`);
      continue;
    }
    try {
      if (fs.statSync(src).isDirectory()) rsyncBack(src, target);
      else copyBack(src, target);
      console.log(`  ✓ ${archivePath} -> ${target}`);
    } catch (e) {
      console.log(`  ! failed ${archivePath} -> ${target}: ${e.message}`);
    }
  }

  // Fix SSH key permissions
  chmodSshKeys();

  fs.rmSync(workDir, { recursive: true, force: true });

  console.log('\n' + '='.repeat(60));
  console.log('Security restore complete.');
  console.log('='.repeat(60));
  console.log('\nReminder:');
  console.log('  • Test SSH: ssh -T git@github.com');
  console.log('  • Re-auth where credentials expired: aws sso login, gh auth login, docker login');
}
