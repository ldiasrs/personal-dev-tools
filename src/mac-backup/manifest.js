import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export function expandHome(p) {
  if (!p) return p;
  if (p === '~') return os.homedir();
  if (p.startsWith('~/')) return path.join(os.homedir(), p.slice(2));
  return p;
}

export function loadConfig(configPath) {
  const resolved = configPath
    ? path.resolve(configPath)
    : path.join(__dirname, 'defaults', 'config.json');
  const raw = fs.readFileSync(resolved, 'utf8');
  const cfg = JSON.parse(raw);
  cfg.outputDir = expandHome(cfg.outputDir);
  if (cfg.scanForLarge?.roots) {
    cfg.scanForLarge.roots = cfg.scanForLarge.roots.map(expandHome);
  }
  if (cfg.scanForLarge?.autoSkip) {
    cfg.scanForLarge.autoSkip = cfg.scanForLarge.autoSkip.map(expandHome);
  }
  if (cfg.include?.vscode?.userDir) {
    cfg.include.vscode.userDir = expandHome(cfg.include.vscode.userDir);
  }
  return cfg;
}

export function defaultsDir() {
  return path.join(__dirname, 'defaults');
}

export function timestamp() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return (
    d.getFullYear().toString() +
    '-' +
    pad(d.getMonth() + 1) +
    '-' +
    pad(d.getDate()) +
    '-' +
    pad(d.getHours()) +
    pad(d.getMinutes()) +
    pad(d.getSeconds())
  );
}

export function buildManifest({ ts, hostname, items, encryption }) {
  return {
    version: 1,
    createdAt: new Date().toISOString(),
    timestamp: ts,
    hostname,
    macos: os.release(),
    node: process.version,
    encryption,
    items
  };
}
