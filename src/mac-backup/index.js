#!/usr/bin/env node
import { runBackup } from './backup.js';

const argv = process.argv.slice(2);
const cmd = argv[0] || 'backup';

function getFlag(name) {
  const i = argv.indexOf(name);
  if (i === -1) return undefined;
  return argv[i + 1] ?? true;
}

async function main() {
  if (cmd === 'backup') {
    await runBackup({
      configPath: getFlag('--config'),
      allowSecrets: getFlag('--allow-secrets-warning') === true
    });
  } else if (cmd === 'restore') {
    console.log('Restore is performed by the generated uncrypt-and-restore-<ts>.sh');
    console.log('Run that script directly:  bash uncrypt-and-restore-<ts>.sh');
  } else if (cmd === '--help' || cmd === '-h') {
    console.log(`mac-backup [backup|restore] [options]

  backup                       Create an encrypted backup bundle
    --config <path>            Use a custom config.json
    --allow-secrets-warning    Downgrade secrets gate from hard-fail to warn+skip

  restore                      Tells you to run the generated .sh

  --help                       Show this
`);
  } else {
    console.error(`Unknown command: ${cmd}`);
    process.exit(1);
  }
}

main().catch((err) => {
  console.error('\nError: ' + err.message);
  process.exit(1);
});
