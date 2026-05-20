import { spawn } from 'node:child_process';

// Create a zip from a directory. Uses -r (recursive), -y (store symlinks),
// -X (no extra file attrs), -q (quiet).
export function zipCreate({ cwd, outFile, includeRelative }) {
  return new Promise((resolve, reject) => {
    const args = ['-r', '-y', '-X', '-q', outFile, ...includeRelative];
    const child = spawn('zip', args, {
      cwd,
      stdio: ['ignore', 'inherit', 'inherit']
    });
    child.on('error', reject);
    child.on('exit', (code) => {
      if (code === 0) resolve();
      else reject(new Error(`zip exited with code ${code}`));
    });
  });
}

export function unzip({ zipFile, dest }) {
  return new Promise((resolve, reject) => {
    const args = ['-q', '-o', zipFile, '-d', dest];
    const child = spawn('unzip', args, { stdio: ['ignore', 'inherit', 'inherit'] });
    child.on('error', reject);
    child.on('exit', (code) => {
      if (code === 0) resolve();
      else reject(new Error(`unzip exited with code ${code}`));
    });
  });
}

export function zipList({ zipFile }) {
  return new Promise((resolve, reject) => {
    const child = spawn('unzip', ['-l', zipFile], { stdio: ['ignore', 'pipe', 'inherit'] });
    let out = '';
    child.stdout.on('data', (d) => (out += d));
    child.on('error', reject);
    child.on('exit', (code) => {
      if (code === 0) resolve(out);
      else reject(new Error(`unzip -l exited with code ${code}`));
    });
  });
}
