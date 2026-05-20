import { spawn } from 'node:child_process';

export function encrypt({ inFile, outFile, password, encryption }) {
  const { algo, kdf, iter } = encryption;
  return run('openssl', [
    'enc',
    `-${algo}`,
    `-${kdf}`,
    '-iter', String(iter),
    '-salt',
    '-in', inFile,
    '-out', outFile,
    '-pass', 'env:MACBACKUP_PASS'
  ], password);
}

export function decrypt({ inFile, outFile, password, encryption }) {
  const { algo, kdf, iter } = encryption;
  return run('openssl', [
    'enc',
    '-d',
    `-${algo}`,
    `-${kdf}`,
    '-iter', String(iter),
    '-in', inFile,
    '-out', outFile,
    '-pass', 'env:MACBACKUP_PASS'
  ], password);
}

function run(cmd, args, password) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, {
      stdio: ['ignore', 'inherit', 'inherit'],
      env: { ...process.env, MACBACKUP_PASS: password }
    });
    child.on('error', reject);
    child.on('exit', (code) => {
      if (code === 0) resolve();
      else reject(new Error(`${cmd} exited with code ${code}`));
    });
  });
}
