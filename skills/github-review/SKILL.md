---
name: github-review
description: |
  Review a GitHub pull request — the PR-review behavior that used to live in the built-in
  `/review`, split out now that `/review` is the review orchestrator. Fetches the PR with `gh`,
  reviews the diff at an evidence-graded bar (only a fully-traced finding is blocking), and
  optionally posts inline PR comments. For your uncommitted working diff use `/review` instead;
  this command is specifically for a PR. Triggers on `/github-review`, `/github-review <pr>`,
  "review this pull request", "review PR #N".
user_invocable: true
---

# /github-review — review a GitHub pull request

Reviews a **GitHub pull request** (the behavior the built-in `/review` used to provide, now that
`/review` is the review orchestrator). For your *uncommitted working diff*, use `/review` (it
picks the right shape) or a direct code-review — this command is specifically for a PR.

Usage: `/github-review [<pr-number-or-url>] [focus aspects…]`. With no argument, target the PR for
the current branch (`gh pr view --json number`), or ask which PR if there isn't one.

## Steps

1. **Fetch the PR.** `gh pr view <pr> --json number,title,body,headRefName,baseRefName,additions,deletions,files`
   and `gh pr diff <pr>`. If `gh` isn't authenticated, say so and stop.
2. **Review the diff at the evidence bar** (same ladder as `/review`'s light mode):
   - **CONFIRMED** — full traced path (file:line → file:line, 3+ steps) or a concrete triggering
     input. Only CONFIRMED is blocking.
   - **LIKELY** — strong reasoning, one inferred link. **POSSIBLE** — a smell, untraced,
     informational. **UNFOUNDED** — ruled out.
   - Verify assumptions first: does the change actually wire in (a new/edited unit is registered/
     imported where the system loads it, new config/env is declared where the code reads it), are
     public names/routes/stored-data keys stable, is every write path updated for a new stored field.
   - Domain checks: schema/API consistency across consumers, concurrency (unguarded
     read-modify-write on eventually-consistent stores), auth on new entrypoints, security
     (secrets/injection/output encoding), common bugs (null, swallowed errors, missing `await`),
     quality.
3. **Output** per finding: **[TAG]** `file:line` — what it is, why it bites, the fix; trace or
   triggering input for CONFIRMED. Lead with CONFIRMED/LIKELY, then POSSIBLE as a short list.
4. **Optionally post** — if asked, post as inline PR comments (`gh pr review --comment`) or a
   summary review; otherwise just report in-session. Never approve/merge.

## Notes
- This is single-model (this session). For cross-model independence on a PR, check it out locally
  and run `/review` → `/codex-review` / `/review-panel` on the diff.
