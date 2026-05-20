import { spawn } from 'node:child_process';
import path from 'node:path';

export function tarCreate({ cwd, outFile, includeRelative }) {
  return new Promise((resolve, reject) => {
    const args = ['-cf', outFile, '-C', cwd, ...includeRelative];
    const child = spawn('tar', args, { stdio: ['ignore', 'inherit', 'inherit'] });
    child.on('error', reject);
    child.on('exit', (code) => {
      if (code === 0) resolve();
      else reject(new Error(`tar create exited with code ${code}`));
    });
  });
}

export function tarExtract({ tarFile, dest }) {
  return new Promise((resolve, reject) => {
    const args = ['-xf', tarFile, '-C', dest];
    const child = spawn('tar', args, { stdio: ['ignore', 'inherit', 'inherit'] });
    child.on('error', reject);
    child.on('exit', (code) => {
      if (code === 0) resolve();
      else reject(new Error(`tar extract exited with code ${code}`));
    });
  });
}

export function tarList({ tarFile }) {
  return new Promise((resolve, reject) => {
    const child = spawn('tar', ['-tf', tarFile], { stdio: ['ignore', 'pipe', 'inherit'] });
    let out = '';
    child.stdout.on('data', (d) => (out += d));
    child.on('error', reject);
    child.on('exit', (code) => {
      if (code === 0) resolve(out.split('\n').filter(Boolean));
      else reject(new Error(`tar list exited with code ${code}`));
    });
  });
}
