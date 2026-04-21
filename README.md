# personal-dev-tools

A collection of personal developer productivity tools.

---

## Tools

| Tool | Script | Description |
|---|---|---|
| `performance-review` | `npm run perf-review` | AI-powered performance review generator from git commits |
| `xml-los-format` | `npm run xml-los-format` | LOS XML formatter |
| `login-ssn` | `npm run login-ssn` | Auto-login with SSH |

---

## performance-review

Collects your git commits across multiple repos, analyzes them against your role profile, and generates a structured performance review. Designed to run weekly — each run improves the existing draft incrementally.

### Setup

**1. Install dependencies**

```bash
npm install
```

**2. Copy the sample config**

```bash
cp performance-review/config-sample/config.yaml performance-review/config/config.yaml
```

**3. Edit `performance-review/config/config.yaml`**

```yaml
user:
  name: Your Full Name
  git_identities:
    - "your.email@company.com"   # use emails for reliable author matching
    - "personal@gmail.com"

repos:
  - path: /absolute/path/to/repo
    name: "Repo Display Name"
  - path: /absolute/path/to/monorepo
    name: "Service Name"
    subfolder: services/my-service  # optional: scope commits to a subfolder

ai:
  provider: openai          # openai | anthropic
  model: gpt-4o
  max_tokens: 4000
  api_key: YOUR_KEY_HERE    # safe here — config/ is gitignored

profile:
  role: "Senior Software Engineer"
  expectations: |
    Paste your full role profile here.
    The AI uses this to evaluate and contextualize your work.
```

> The `performance-review/config/` and `performance-review/data/` folders are gitignored. Your API key and generated reviews never leave your machine.

**4. Run it**

```bash
npm run perf-review
```

### Folder structure

```
performance-review/
├── config-sample/            # Committed — safe reference template
│   └── config.yaml
├── config/                   # Gitignored — your real config
│   └── config.yaml
└── data/                     # Gitignored — all generated files
    ├── full-review.md        # Output: deep analysis grouped by topic
    ├── simplified-review.md  # Output: 3-question format
    └── processed-commits.md  # Auto-managed: commit dedup log
```

### Weekly workflow

```
1. Run: npm run perf-review → Analyze new commits → Last week
2. Review the outputs in performance-review/data/
3. Run: npm run perf-review → Refine existing review  (optional, to improve the draft)
4. Repeat weekly — the review accumulates across the quarter
```

---

## Architecture

### `src/performance-review/`

```
index.js                  Entry point — mode prompt, orchestration, no business logic
time-window.js            Date math: resolves quarter / last week / yesterday / custom range
git-collector.js          Git log per repo, deduplicates against processed-commits.md
output-formatter.js       Writes full-review.md, simplified-review.md, processed-commits.md

ai/
  ai-factory.js           createProvider(config) → returns a provider instance
  prompts.js              All prompt text: system prompt, analyze message, refine message
  providers/
    base.js               Interface: analyze({ systemPrompt, userMessage }) + parseOutputs()
    anthropic.js          Claude implementation with prompt caching
    openai.js             OpenAI chat completion implementation

utils/
  config-loader.js        Loads and validates performance-review/config/config.yaml
  file-manager.js         All file I/O — single source of truth for paths
```

### Key design decisions

**AI provider factory**
The factory (`ai-factory.js`) is the only place that knows which provider to instantiate. All other modules program to the `BaseAIProvider` interface. Adding a new provider means creating a file in `providers/` and registering it in the factory — nothing else changes.

**Incremental deduplication via `processed-commits.md`**
Commit hashes are stored in a human-readable markdown file after each run. On the next run, the file is parsed and any already-seen hashes are excluded. This means you can safely overlap time windows (e.g. run "Last week" then "Quarter") without double-counting commits.

**Refine mode**
Decoupled from git entirely. Re-reads the existing `full-review.md` and asks the AI to improve it — deeper analysis, clearer writing, complete ticket references, tighter simplified review. No user input or new commits needed.

**`subfolder` support**
When a repo is a monorepo, the `subfolder` key in config scopes `git log` to that path via `git log -- <subfolder>`. The git root is still the repo root (required for git commands to work), but only commits touching the subfolder are collected.
