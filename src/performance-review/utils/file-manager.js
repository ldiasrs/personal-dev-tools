import { readFileSync, writeFileSync, existsSync, mkdirSync } from "fs";
import { resolve, dirname } from "path";

const DATA_DIR = resolve("performance-review/data");

const paths = {
  processedCommits: resolve(DATA_DIR, "processed-commits.md"),
  fullReview: resolve(DATA_DIR, "full-review.md"),
  simplifiedReview: resolve(DATA_DIR, "simplified-review.md"),
};

function ensureDir(filePath) {
  const dir = dirname(filePath);
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
}

function readOrEmpty(filePath) {
  return existsSync(filePath) ? readFileSync(filePath, "utf8").trim() : "";
}

function write(filePath, content) {
  ensureDir(filePath);
  writeFileSync(filePath, content, "utf8");
}

export function readExistingReview() {
  return readOrEmpty(paths.fullReview);
}

export function writeReviews(fullReview, simplifiedReview) {
  write(paths.fullReview, fullReview);
  write(paths.simplifiedReview, simplifiedReview);
}

export function readProcessedHashes() {
  const content = readOrEmpty(paths.processedCommits);
  if (!content) return new Set();
  const matches = content.match(/`([a-f0-9]{7,40})`/g) || [];
  return new Set(matches.map((m) => m.replace(/`/g, "")));
}

export function appendProcessedCommits(commits, windowLabel) {
  const date = new Date().toISOString().split("T")[0];
  const header = `\n## Run: ${date} | Window: ${windowLabel}\n`;

  const byRepo = commits.reduce((acc, c) => {
    if (!acc[c.repo]) acc[c.repo] = [];
    acc[c.repo].push(c);
    return acc;
  }, {});

  const sections = Object.entries(byRepo)
    .map(([repo, repoCommits]) => {
      const lines = repoCommits.map(
        (c) => `- \`${c.hash}\` ${c.date} — ${c.message}`
      );
      return `\n### ${repo}\n${lines.join("\n")}`;
    })
    .join("\n");

  const existing = readOrEmpty(paths.processedCommits);
  const prefix = existing ? existing : "# Processed Commits";
  write(paths.processedCommits, `${prefix}${header}${sections}\n\n---`);
}
