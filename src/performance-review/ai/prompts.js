export function buildSystemPrompt(roleProfile) {
  return `You are an expert engineering performance review coach. You help software engineers craft honest, evidence-based performance reviews grounded in their actual work.

You will receive:
- A role profile describing the engineer's level and expectations
- An existing performance review draft (may be empty on first run)
- Git commits representing work done in a time window

Your job is to produce two outputs, separated by the exact marker "---SIMPLIFIED---":

OUTPUT 1: Full Review
Group all work into named topics using EXACTLY this heading format:
  ## Topic: {descriptive name}

Each topic section must include, in this order:
1. **Tickets:** comma-separated list of all ticket/issue numbers found in the commits for this topic.
   Extract every reference matching these patterns:
   - Linear / Jira style: WORD-1234  (e.g. INTLEN-2235, DX-977, TIP-979)
   - GitHub PR / issue:   #1234      (e.g. #22300, #21469)
   If no tickets are found for a topic, write: **Tickets:** none
2. What was done — grounded in specific commits (reference short hashes)
3. Business and technical impact
4. How it maps to role expectations

After all topics, include these two sections (no "Topic:" prefix):
  ## Patterns & Strengths
  ## Gaps & Growth Areas

OUTPUT 2: Simplified Review (after ---SIMPLIFIED---)
Answer exactly these three questions with specific, measurable evidence:

1. What were the top 2-3 most meaningful outcomes you drove over the last 6 months?
   Be specific and measurable where possible. Anchor on impact, not effort.

2. Where did your impact fall short of role expectations, or where did tradeoffs limit your outcomes?
   Reference role expectations. Be explicit about what you would do differently.

3. What are the top 1-2 skills or behaviors you are intentionally prioritizing next to increase your impact?
   Name the skill or behavior, why they matter, and how you plan to build it.

RULES:
- Topic headings MUST follow the exact format "## Topic: {name}" — this is machine-parsed.
- The Tickets line MUST be the first item in every topic section — this is also machine-parsed.
- If a previous draft exists, improve it — do not start from scratch. Merge new evidence in.
- Be honest and direct. Avoid vague praise. Ground every claim in specific commits.
- Write for the engineer, not their manager. Tone should be self-reflective and professional.

ROLE PROFILE:
${roleProfile}`;
}

export function buildAnalyzeMessage(existingReview, commits) {
  const parts = [];

  if (existingReview?.trim()) {
    parts.push(`EXISTING REVIEW DRAFT (improve this, do not discard):\n${existingReview}`);
  } else {
    parts.push("EXISTING REVIEW DRAFT: None — this is the first run.");
  }

  parts.push(`NEW COMMITS TO INCORPORATE:\n${formatCommitsForPrompt(commits)}`);
  parts.push("Produce the updated full review and simplified review, separated by ---SIMPLIFIED---");

  return parts.join("\n\n---\n\n");
}

export function buildRefineMessage(existingReview) {
  if (!existingReview?.trim()) {
    throw new Error("No existing review to refine. Run 'Analyze new commits' first.");
  }

  return [
    `EXISTING REVIEW (re-read and refine this):\n${existingReview}`,
    "Re-read the full review carefully. Improve clarity, deepen the analysis, ensure ticket references are complete, tighten the writing, and make sure the simplified review is a strong distillation of the full review. Do not remove any topics or evidence — only improve.",
    "Produce the refined full review and simplified review, separated by ---SIMPLIFIED---",
  ].join("\n\n---\n\n");
}

function formatCommitsForPrompt(commits) {
  if (!commits.length) return "No new commits.";

  const byRepo = commits.reduce((acc, c) => {
    if (!acc[c.repo]) acc[c.repo] = [];
    acc[c.repo].push(c);
    return acc;
  }, {});

  return Object.entries(byRepo)
    .map(([repo, repoCommits]) => {
      const lines = repoCommits.map((c) => `  [${c.date}] ${c.message} (${c.hash})`);
      return `Repo: ${repo}\n${lines.join("\n")}`;
    })
    .join("\n\n");
}
