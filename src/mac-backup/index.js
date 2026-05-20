#!/usr/bin/env node
import { runBackup } from './backup.js';
import { runRestore } from './restore.js';
import { runRestoreSecurity } from './restore-security.js';

const argv = process.argv.slice(2);
const cmd = argv[0];

function getFlag(name) {
  const i = argv.indexOf(name);
  if (i === -1) return undefined;
  const next = argv[i + 1];
  return next && !next.startsWith('--') ? next : true;
}

function positional(skip = 1) {
  return argv.slice(skip).find((a) => !a.startsWith('--'));
}

async function main() {
  switch (cmd) {
    case 'backup':
      await runBackup({
        configPath: getFlag('--config'),
        skipSecurity: getFlag('--skip-security') === true
      });
      break;
    case 'restore':
      await runRestore({ bundleDir: positional() });
      break;
    case 'restore-security':
      await runRestoreSecurity({ bundleDir: positional() });
      break;
    case '--help':
    case '-h':
    case undefined:
      console.log(`mac-backup <command> [options]

  backup                                  Create an encrypted backup bundle
    --config <path>                       Use a custom config.json
    --skip-security                       Don't produce a security.zip.enc

  restore <bundle-folder>                 Restore the main bundle (no secrets)

  restore-security <bundle-folder>        Restore the security archive
                                          (~/.ssh, AWS creds, tokens, *.pem)
`);
      break;
    default:
      console.error(`Unknown command: ${cmd}`);
      process.exit(1);
  }
}

main().catch((err) => {
  console.error('\nError: ' + err.message);
  process.exit(1);
});
