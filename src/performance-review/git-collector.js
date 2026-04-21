import simpleGit from "simple-git";
import { addDays, subDays, parseISO, format } from "date-fns";
import { readProcessedHashes } from "./utils/file-manager.js";

// git --after/--before are exclusive at midnight, so expand by 1 day each side
// to make the window fully inclusive of the start and end dates.
function toGitRange(start, end) {
  const after = format(subDays(parseISO(start), 1), "yyyy-MM-dd");
  const before = format(addDays(parseISO(end), 1), "yyyy-MM-dd");
  return { after, before };
}

export async function collectNewCommits(repos, identities, start, end) {
  const processedHashes = readProcessedHashes();
  const allCommits = [];
  const seenHashes = new Set();
  const { after, before } = toGitRange(start, end);

  for (const repo of repos) {
    const git = simpleGit(repo.path);

    try {
      await git.status();
    } catch {
      console.warn(`Warning: repo not accessible at ${repo.path}, skipping.`);
      continue;
    }

    for (const identity of identities) {
      const flags = [
        `--author=${identity}`,
        `--after=${after}`,
        `--before=${before}`,
        "--no-merges",
      ];

      if (repo.subfolder) {
        flags.push("--", repo.subfolder);
      }

      const log = await git.log(flags);

      for (const entry of log.all) {
        const hash = entry.hash.slice(0, 7);
        const fullHash = entry.hash;
        const date = entry.date.split(" ")[0];
        const message = entry.message.trim();

        const isNew =
          !processedHashes.has(hash) &&
          !processedHashes.has(fullHash) &&
          !seenHashes.has(fullHash);

        if (isNew) {
          seenHashes.add(fullHash);
          allCommits.push({ hash, date, message, repo: repo.name });
        }
      }
    }
  }

  return allCommits;
}
