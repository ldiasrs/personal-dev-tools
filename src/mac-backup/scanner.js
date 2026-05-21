import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import inquirer from 'inquirer';

import { expandHome } from './manifest.js';

function duDir(p, maxDepth) {
  // BSD (macOS) du rejects `-s` together with `-d` — they're mutually
  // exclusive. Use `-d` alone; `-k` reports sizes in KB.
  // Don't bail on non-zero exit: du exits 1 when it hits TCC-protected
  // directories but still emits valid sizes for everything else on stdout.
  const out = spawnSync('du', ['-k', '-d', String(maxDepth), p], {
    encoding: 'utf8'
  });
  if (!out.stdout) return [];
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

// Compile a dirExcludePatterns entry (e.g. "node_modules", ".next", "*.log")
// into a basename-matching regex. Mirrors rsync --exclude's basename match.
function patternToRegex(p) {
  return new RegExp(
    '^' +
      p
        .replace(/[.+^${}()|[\]\\]/g, '\\$&')
        .replace(/\*/g, '.*')
        .replace(/\?/g, '.') +
      '$'
  );
}

function basenameMatchesAny(name, regs) {
  return regs.some((r) => r.test(name));
}

// Walks every path in cfg.include.dirs, surfaces subdirectories >= minSizeMB
// (after honoring dirExcludePatterns), and asks the user which ones to keep.
// Returns the absolute paths the user UNCHECKED — these become per-source
// rsync --exclude patterns when include.dirs is copied.
export async function scanLargeDirs(cfg) {
  if (!cfg.scanForLarge?.enabled) return [];

  const sources = (cfg.include?.dirs || [])
    .map(expandHome)
    .filter((p) => fs.existsSync(p));
  if (sources.length === 0) {
    console.log('  (no include.dirs configured to scan)');
    return [];
  }

  const { minSizeMB, maxDepth, autoSkip } = cfg.scanForLarge;
  const minKb = (minSizeMB || 100) * 1024;
  const autoSkipSet = new Set((autoSkip || []).map(expandHome));
  const excludeRegs = (cfg.include?.dirExcludePatterns || []).map(patternToRegex);

  // Walk each include source, dedupe by absolute path (sources can overlap).
  const seen = new Set();
  const all = [];
  for (const src of sources) {
    for (const e of duDir(src, maxDepth || 2)) {
      if (e.path === src) continue;
      if (e.sizeKb < minKb) continue;
      if (seen.has(e.path)) continue;
      // Skip anything dirExcludePatterns already kills — showing it would
      // be misleading since rsync won't copy it anyway.
      if (basenameMatchesAny(path.basename(e.path), excludeRegs)) continue;
      // Also skip if any ancestor along the way matches an exclude pattern.
      const rel = path.relative(src, e.path);
      if (rel.split(path.sep).some((seg) => basenameMatchesAny(seg, excludeRegs))) continue;
      seen.add(e.path);
      all.push(e);
    }
  }

  all.sort((a, b) => b.sizeKb - a.sizeKb);

  if (all.length === 0) {
    console.log('  (no subdirectories above threshold inside include.dirs)');
    return [];
  }

  console.log(
    `\nFound ${all.length} director${all.length === 1 ? 'y' : 'ies'} >= ${cfg.scanForLarge.minSizeMB} MB inside include.dirs:`
  );
  for (const e of all) {
    const tag = autoSkipSet.has(e.path) ? '  (auto-excluded)' : '';
    console.log(`  ${fmtSize(e.sizeKb).padStart(8)}  ${e.path}${tag}`);
  }

  const choices = all.map((e) => ({
    name: `${fmtSize(e.sizeKb).padStart(8)}  ${e.path}${autoSkipSet.has(e.path) ? '  (auto-excluded)' : ''}`,
    value: e.path,
    checked: !autoSkipSet.has(e.path)
  }));

  const { kept } = await inquirer.prompt([
    {
      type: 'checkbox',
      name: 'kept',
      message:
        'Directories to INCLUDE in backup (uncheck to exclude). Space toggles, enter confirms:',
      choices,
      pageSize: Math.min(20, choices.length)
    }
  ]);

  const keptSet = new Set(kept);
  // Return what the user removed — these become rsync --exclude args.
  return all.map((e) => e.path).filter((p) => !keptSet.has(p));
}
