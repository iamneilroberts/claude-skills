---
name: idea
description: |
  Capture a fix / feature / research idea fast and turn it into a tracked GitHub
  Issue plus a lightweight planning doc, so nothing gets lost and it shows up next
  time you list your issues. Runs a short confirm-or-edit interview (infers
  title/slug/type from your one-liner, you accept or correct), writes
  docs/ideas/<date>-<slug>.md, files a labelled GitHub Issue via gh, and backlinks
  the issue URL into the doc. Triggers on `/idea <one-liner>`, `/idea`, "capture
  this idea", "file an idea", "log a thing to fix/build/research", "remember to
  look into X".
user_invocable: true
args: "<one-liner describing the fix / feature / research idea> (optional — will prompt if omitted)"
---

# /idea — capture a fix/feature/research idea into a tracked issue + planning doc

The front door for "I just thought of something I want to fix / build / look into."
One fast capture produces: a **GitHub Issue** (the backlog substrate) and a **planning
doc** at `docs/ideas/<date>-<slug>.md` linked to it. Both are visible to any tool that
reads `gh issue list` (including the optional `/pm` board).

**Scope:** files into the current repo's GitHub Issues (whatever `gh` resolves for the
working dir) and, optionally, tags a milestone if the repo uses them.

## Operating principle: lean fast

Most ideas should be a 2-tap capture, not a Q&A. **Infer aggressively from the
one-liner, then show one proposal block and let the user accept all with "y" or
correct any field.** Only ask a real question for a field you genuinely cannot
infer. Never block capture on perfection — a thin idea filed beats a rich idea lost.

## Steps

1. **Get the one-liner.** If invoked as `/idea <text>`, use it. If bare `/idea`,
   ask once: "What's the idea? (one line — fix / feature / research)".

2. **Infer & propose.** From the one-liner, derive:
   - **title** — a clean imperative issue title (e.g. "Cache geocode lookups across requests").
   - **slug** — kebab-case, ≤ 5 words, no date (e.g. `cache-geocode-lookups`).
   - **type** — `fix` (bug/defect), `feature` (new capability), or `research`
     (investigation/spike). Infer from verbs: "fix/broken/regression" → fix;
     "add/build/support" → feature; "look into/investigate/compare/spike" → research.
   - **priority** — `now` / `next` / `someday`. Default `next` unless the one-liner
     signals urgency ("urgent", "broken in prod" → now) or deferral ("someday",
     "nice to have" → someday).
   - **milestone** — a milestone if the idea obviously maps to one and the repo uses
     them (e.g. from `docs/roadmap/MILESTONES.md`); otherwise none.

   Present it as a single compact block:
   ```
   title:     Cache geocode lookups across requests
   slug:      cache-geocode-lookups
   type:      feature
   priority:  next
   milestone: none
   ```
   Then: "Accept all (y), or tell me what to change."

3. **Confirm-or-edit.** Apply any corrections. If the user gave no problem detail
   in the one-liner, ask the *single* open question: "One line on the problem /
   motivation?" (skippable). Capture optional **rough approach** only if the user
   volunteers it — do not prompt for it.

4. **Write the planning doc** to `docs/ideas/<date>-<slug>.md` (date = today,
   `YYYY-MM-DD`) using the template below. Leave `issue:` blank for now.

5. **File the GitHub Issue.** Write the issue body to a temp file, then run the
   backend helper (it ensures labels exist and creates the issue):
   ```bash
   .claude/skills/idea/file-idea.sh \
     --title "<title>" --type <type> --priority <priority> \
     [--milestone M3] --body-file /tmp/idea-body.md
   ```
   It prints `ISSUE_NUMBER=<n>` and `ISSUE_URL=<url>`. Use `--dry-run` to preview
   without creating anything.

   **Issue body** (the doc is the source of truth; the issue is the board entry):
   ```markdown
   <2-3 line summary in your words>

   **Planning doc:** docs/ideas/<date>-<slug>.md
   **Milestone:** M3 (or "none")

   _Captured via /idea._
   ```

6. **Backlink & commit.** Fill the doc's `issue:` frontmatter with the URL, then
   commit *by name* (stage the one file, not `git add -A`):
   ```bash
   git add docs/ideas/<date>-<slug>.md && git commit -m "idea: <title> (#<n>)"
   ```

7. **Report.** One line: issue number + URL + doc path.

## Planning doc template (`docs/ideas/<date>-<slug>.md`)

```markdown
---
title: <title>
slug: <slug>
type: fix | feature | research
priority: now | next | someday
milestone: M3 | none
issue: <url — filled after the issue is created>
status: open
created: <YYYY-MM-DD>
---

## Problem / motivation
<the itch, in the user's words>

## Rough approach
<optional — or "TBD">

## Open questions
-

## Notes
<append as the idea evolves; this doc is the durable home, the issue is the pointer>
```

## Notes

- **Backend is the helper script.** `file-idea.sh` owns label creation
  (`idea` + type + `p:<priority>` + optional `area:M<n>`) and `gh issue create`.
  It is idempotent (`gh label create --force`) and supports `--dry-run`.
- **Milestone handling:** if a real GitHub milestone named `M<n>` exists, the
  helper sets it; otherwise it applies an `area:M<n>` label (no GitHub milestones
  exist today, so it's labels for now).
- **Not in scope (by design):** no worktree creation (capture ≠ start-work — use
  `/branch` or `/pickup` when you're ready to build it); no triage automation.
- **Resuming an idea later:** list open issues (`gh issue list`, or `/pm` if you have
  it); pick one, read its `docs/ideas/` doc, then `/branch <slug>` to start the work.
