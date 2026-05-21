import { spawn, spawnSync } from 'node:child_process';

// Verify the tools we rely on are on PATH. zstd is the only one that may be
// missing on a fresh Mac (tar is always present). Throws with an actionable
// install hint so we fail fast before doing any work.
export function assertArchiveTools() {
  const r = spawnSync('zstd', ['--version'], { stdio: 'ignore' });
  if (r.status !== 0) {
    throw new Error(
      "'zstd' not found on PATH. Install it with:  brew install zstd"
    );
  }
}

// Create a tar.zst archive by streaming `tar` -> `zstd` over a pipe.
// `-T0` = use all cores, `-3` = default-ish level (good ratio, very fast).
// tar stores symlinks as symlinks and silently skips socket/FIFO entries.
export function archiveCreate({ cwd, outFile, includeRelative }) {
  return new Promise((resolve, reject) => {
    const tar = spawn('tar', ['-cf', '-', ...includeRelative], {
      cwd,
      stdio: ['ignore', 'pipe', 'inherit']
    });
    const zstd = spawn('zstd', ['-T0', '-3', '-q', '-f', '-o', outFile], {
      stdio: ['pipe', 'inherit', 'inherit']
    });
    tar.stdout.pipe(zstd.stdin);

    let settled = false;
    const fail = (err) => {
      if (settled) return;
      settled = true;
      try { tar.kill(); } catch {}
      try { zstd.kill(); } catch {}
      reject(err);
    };

    tar.on('error', fail);
    zstd.on('error', fail);
    tar.on('exit', (code) => {
      if (code !== 0) fail(new Error(`tar exited with code ${code}`));
    });
    zstd.on('exit', (code) => {
      if (settled) return;
      if (code === 0) { settled = true; resolve(); }
      else fail(new Error(`zstd exited with code ${code}`));
    });
  });
}

// Extract a tar.zst into `dest` by streaming `zstd -d` -> `tar -x`.
export function archiveExtract({ archiveFile, dest }) {
  return new Promise((resolve, reject) => {
    const zstd = spawn('zstd', ['-d', '-c', archiveFile], {
      stdio: ['ignore', 'pipe', 'inherit']
    });
    const tar = spawn('tar', ['-xf', '-', '-C', dest], {
      stdio: ['pipe', 'inherit', 'inherit']
    });
    zstd.stdout.pipe(tar.stdin);

    let settled = false;
    const fail = (err) => {
      if (settled) return;
      settled = true;
      try { zstd.kill(); } catch {}
      try { tar.kill(); } catch {}
      reject(err);
    };

    zstd.on('error', fail);
    tar.on('error', fail);
    zstd.on('exit', (code) => {
      if (code !== 0) fail(new Error(`zstd exited with code ${code}`));
    });
    tar.on('exit', (code) => {
      if (settled) return;
      if (code === 0) { settled = true; resolve(); }
      else fail(new Error(`tar exited with code ${code}`));
    });
  });
}

// List entries inside a tar.zst (used for inspection / debugging).
export function archiveList({ archiveFile }) {
  return new Promise((resolve, reject) => {
    const zstd = spawn('zstd', ['-d', '-c', archiveFile], {
      stdio: ['ignore', 'pipe', 'inherit']
    });
    const tar = spawn('tar', ['-tf', '-'], {
      stdio: ['pipe', 'pipe', 'inherit']
    });
    zstd.stdout.pipe(tar.stdin);

    let out = '';
    tar.stdout.on('data', (d) => (out += d));

    let settled = false;
    const fail = (err) => {
      if (settled) return;
      settled = true;
      try { zstd.kill(); } catch {}
      try { tar.kill(); } catch {}
      reject(err);
    };

    zstd.on('error', fail);
    tar.on('error', fail);
    zstd.on('exit', (code) => {
      if (code !== 0) fail(new Error(`zstd exited with code ${code}`));
    });
    tar.on('exit', (code) => {
      if (settled) return;
      if (code === 0) { settled = true; resolve(out); }
      else fail(new Error(`tar exited with code ${code}`));
    });
  });
}
