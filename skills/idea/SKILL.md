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

Turns "I just thought of something" into a **GitHub Issue** (backlog substrate) plus a linked **planning doc** at `docs/ideas/<date>-<slug>.md`. Files into the current repo (whatever `gh` resolves); tags a milestone only if the repo uses them.

**Lean fast:** 2-tap capture, not a Q&A. Infer aggressively, show one proposal block, accept with "y" or correct a field. Only ask what you truly can't infer — a thin idea filed beats a rich idea lost.

## Steps

1. **One-liner** — use it if given (`/idea <text>`); if bare, ask once: "What's the idea? (one line — fix / feature / research)".
2. **Infer & propose**, one compact block, then "Accept all (y), or tell me what to change.":
   - **title** — clean imperative (e.g. "Cache geocode lookups across requests")
   - **slug** — kebab-case, ≤5 words, no date (e.g. `cache-geocode-lookups`)
   - **type** — `fix`/`feature`/`research`, from verbs (fix/broken/regression → fix; add/build/support → feature; investigate/compare/spike → research)
   - **priority** — `now`/`next`/`someday`, default `next` (urgency → now, "someday"/"nice to have" → someday)
   - **milestone** — only if it obviously maps to one the repo uses (e.g. `docs/roadmap/MILESTONES.md`); else `none`
   ```
   title:     Cache geocode lookups across requests
   slug:      cache-geocode-lookups
   type:      feature
   priority:  next
   milestone: none
   ```
3. **Confirm-or-edit** — apply corrections; if no problem detail was given, ask one skippable question: "One line on the problem / motivation?" Capture **rough approach** only if volunteered.
4. **Write the planning doc** to `docs/ideas/<date>-<slug>.md` (template below), `issue:` left blank.
5. **File the issue** — write the body to a temp file, then:
   ```bash
   .claude/skills/idea/file-idea.sh \
     --title "<title>" --type <type> --priority <priority> \
     [--milestone M3] --body-file /tmp/idea-body.md
   ```
   Prints `ISSUE_NUMBER=<n>` / `ISSUE_URL=<url>`; `--dry-run` previews only. Body (doc is source of truth, issue is the board entry):
   ```markdown
   <2-3 line summary in your words>

   **Planning doc:** docs/ideas/<date>-<slug>.md
   **Milestone:** M3 (or "none")

   _Captured via /idea._
   ```
6. **Backlink & commit** — fill `issue:` with the URL, stage by name (not `git add -A`):
   ```bash
   git add docs/ideas/<date>-<slug>.md && git commit -m "idea: <title> (#<n>)"
   ```
7. **Report** one line: issue number + URL + doc path.

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
<append as the idea evolves; doc is the durable home, issue is the pointer>
```

## Notes

- `file-idea.sh` creates labels (`idea` + type + `p:<priority>` + optional `area:M<n>`) and the issue; idempotent, supports `--dry-run`.
- Sets a real GitHub milestone `M<n>` if one exists, else an `area:M<n>` label.
- Out of scope: worktree creation (`/branch`/`/pickup` to start work), triage automation.
- Resume later: `gh issue list` (or `/pm`) → read the doc → `/branch <slug>`.
