import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import inquirer from 'inquirer';

function duDir(p, maxDepth) {
  const out = spawnSync('du', ['-sk', '-d', String(maxDepth), p], {
    encoding: 'utf8'
  });
  if (out.status !== 0) return [];
  return out.stdout
    .split('\n')
    .filter(Boolean)
    .map((line) => {
      const [sizeKb, ...rest] = line.split(/\s+/);
      return { path: rest.join(' '), sizeKb: parseInt(sizeKb, 10) };
    })
    .filter((e) => fs.existsSync(e.path));
}

function fmtSize(kb) {
  if (kb >= 1024 * 1024) return (kb / 1024 / 1024).toFixed(1) + ' GB';
  if (kb >= 1024) return (kb / 1024).toFixed(0) + ' MB';
  return kb + ' KB';
}

export async function scanLargeDirs(cfg) {
  if (!cfg.scanForLarge?.enabled) return [];
  const { roots, minSizeMB, maxDepth, autoSkip } = cfg.scanForLarge;
  const minKb = (minSizeMB || 100) * 1024;
  const skipSet = new Set(autoSkip || []);

  const all = [];
  for (const root of roots) {
    if (!fs.existsSync(root)) continue;
    const entries = duDir(root, maxDepth || 2);
    for (const e of entries) {
      if (e.path === root) continue;
      if (e.sizeKb < minKb) continue;
      all.push(e);
    }
  }

  all.sort((a, b) => b.sizeKb - a.sizeKb);

  if (all.length === 0) {
    console.log('  (no directories above threshold)');
    return [];
  }

  console.log(`\nFound ${all.length} directories above ${cfg.scanForLarge.minSizeMB} MB:`);
  for (const e of all) {
    const tag = skipSet.has(e.path) ? ' (auto-skip)' : '';
    console.log(`  ${fmtSize(e.sizeKb).padStart(8)}  ${e.path}${tag}`);
  }

  const choices = all.map((e) => ({
    name: `${fmtSize(e.sizeKb).padStart(8)}  ${e.path}${skipSet.has(e.path) ? '  (auto-skip)' : ''}`,
    value: e.path,
    checked: !skipSet.has(e.path)
  }));

  const { picked } = await inquirer.prompt([
    {
      type: 'checkbox',
      name: 'picked',
      message: 'Select large directories to INCLUDE in backup (space to toggle, enter to confirm):',
      choices,
      pageSize: Math.min(20, choices.length)
    }
  ]);

  // Allow free-form additions
  const extras = [];
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const { extra } = await inquirer.prompt([
      {
        type: 'input',
        name: 'extra',
        message: 'Add another path? (absolute path, or empty to finish)'
      }
    ]);
    if (!extra) break;
    const resolved = path.resolve(extra.replace(/^~/, process.env.HOME || ''));
    if (!fs.existsSync(resolved)) {
      console.log(`  Skipping: ${resolved} does not exist`);
      continue;
    }
    extras.push(resolved);
  }

  return [...picked, ...extras];
}
