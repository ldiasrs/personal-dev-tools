// TTY + piped-stdin friendly password reader.
// Inquirer's password prompt breaks when stdin is piped (used in tests/scripts);
// this implements rawmode masking for TTY and a buffered line reader otherwise.

let _stdinBuffer = '';
let _stdinAttached = false;

export function readSecret(prompt) {
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
        const code = key.charCodeAt(0);
        if (key === '\r' || key === '\n' || code === 4) {
          stdin.setRawMode(false);
          stdin.pause();
          stdin.removeListener('data', onData);
          stdout.write('\n');
          resolve(buf);
        } else if (code === 3) {
          stdin.setRawMode(false);
          stdout.write('\n');
          reject(new Error('Aborted'));
        } else if (code === 127 || code === 8) {
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

export async function promptPassword({ confirm = true } = {}) {
  const p1 = await readSecret('Encryption password: ');
  if (!confirm) {
    if (p1.length < 8) throw new Error('Password must be at least 8 characters');
    return p1;
  }
  const p2 = await readSecret('Confirm password:    ');
  if (p1 !== p2) throw new Error('Passwords did not match');
  if (p1.length < 8) throw new Error('Password must be at least 8 characters');
  return p1;
}
