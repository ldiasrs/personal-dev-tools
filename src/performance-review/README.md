# performance-review

AI-powered performance review generator. Collects your git commits across multiple repos, analyzes them against your role expectations, and produces a structured performance review. Runs weekly and improves incrementally — each run builds on the previous draft.

---

## How to Run

```bash
npm run perf-review
```

---

## Modes

### Analyze new commits

Collects unprocessed commits for a selected time window and feeds them into the review.

```
? What do you want to do? Analyze new commits
? Select time window: Last week (2026-04-14 – 2026-04-20)

Collecting commits for: Last week (2026-04-14 – 2026-04-20)
Found 8 new commit(s) across 2 repo(s).

Analyzing with AI...

Outputs written:
  Full review     → performance-review/data/full-review.md
  Simplified      → performance-review/data/simplified-review.md
  Processed log   → performance-review/data/processed-commits.md

Done. 8 commit(s) processed.
```

### Refine existing review

Re-reads `full-review.md` and asks the AI to improve it — no new commits or input needed.

```
? What do you want to do? Refine existing review

Refining existing review...

Outputs written:
  Full review     → performance-review/data/full-review.md
  Simplified      → performance-review/data/simplified-review.md

Done. Review refined.
```

---

## Example Outputs

### full-review.md

```markdown
## Topic: Payment Retry Feature

**Tickets:** PROJ-101, #42

Added retry logic to the payment flow to handle transient failures (a1b2c3d).
Reduced failed transactions by handling timeout errors gracefully.

Role alignment: Demonstrates ownership of a complete feature from design to delivery.

---

## Topic: Auth Middleware Refactor

**Tickets:** PROJ-98, #38

Extracted duplicated auth logic into a shared middleware (d4e5f6a).
Improved consistency across 3 services and simplified future changes.

Role alignment: Reduces unnecessary deviations from common patterns.

---

## Patterns & Strengths

Consistent delivery of well-scoped features with clear business impact.

## Gaps & Growth Areas

Some changes lacked upfront design discussion — earlier alignment would reduce rework.
```

### simplified-review.md

```markdown
## 1. Most Meaningful Outcomes

**Payment Retry Logic** — Delivered retry handling for transient failures (PROJ-101),
directly reducing failed transactions and improving user experience.

**Auth Middleware Refactor** — Consolidated duplicated auth logic into a shared layer
(PROJ-98), improving consistency across 3 services.

## 2. Where Impact Fell Short

Changes were delivered without upfront design docs, leading to some rework.
Earlier alignment with the team would have reduced iteration cycles.

## 3. Skills to Prioritize

**Design-first approach** — Write a short design note before starting cross-service
work and share it with one peer. Builds toward the expectation of driving technical
solutions at team scope.
```

---

## Setup

See the [project README](../../README.md) for full setup instructions.

---

## Architecture

See the [Architecture section](../../README.md#architecture) of the project README.
