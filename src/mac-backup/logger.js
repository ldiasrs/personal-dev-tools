import fs from 'node:fs';

export function writeLog(logPath, sections) {
  const lines = [];
  for (const [title, body] of Object.entries(sections)) {
    lines.push(`=== ${title} ===`);
    if (Array.isArray(body)) {
      lines.push(...body.map(String));
    } else if (typeof body === 'object') {
      lines.push(JSON.stringify(body, null, 2));
    } else {
      lines.push(String(body));
    }
    lines.push('');
  }
  fs.writeFileSync(logPath, lines.join('\n'), 'utf8');
}
