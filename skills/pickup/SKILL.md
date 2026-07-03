---
name: pickup
description: >
  Use when the user wants to pick up / resume the most recent handoff in an isolated worktree —
  finds the newest handoff doc, RESUMES the worktree/branch it documents if one exists (re-adding
  it if parked), otherwise creates a fresh branch + worktree, then loads the handoff's context so
  work continues where it left off. Triggers on `/pickup`, "pick up the handoff", "resume the
  latest handoff in a worktree", "branch and continue". Distinct from `session-resume` (loads a
  handoff in-place, never branches) and `branch` (makes a worktree, loads no handoff) — `/pickup`
  does both, reusing an existing worktree when one is documented.
user_invocable: true
args: "[branch-slug | date/topic filter | handoff path]"
---

# Pickup

Resume the newest handoff in an isolated worktree, then load its context. Reuse the documented worktree/branch if it still exists; create a new one only when none is documented or it's gone. Orchestrates `branch` and `session-resume` — do not reimplement their internals.

> **Requires `branch` and `session-resume`** from this collection (optionally `/pm`, see step 1 tip). Install alongside this skill.

## Steps

1. **Find the handoff.** Use `session-resume`'s discovery (shared `handoffs/` dir, then legacy in-tree dirs). Prefer newest *intentional* `pause-*.md`; fall back to a *mechanical* `auto-*.md` only if none exists. Path arg → use it. Date/topic/slug arg → filter by it. No arg → newest intentional handoff. Multiple matches → list the 5 most recent and ask. None → say so, stop. Read the file. Tip: run `/pm` first for a picture of all in-flight lanes.

2. **WIP/worktree safety first.** Run `git worktree list` and read the shared journal (`$(bash ~/.claude/coordination/resolve-coord-dir.sh)/journal.md`; the in-tree `docs/worktree-journal.md` is only a tombstone pointer). If another session has uncommitted WIP or an overlapping active worktree, surface it and pause. Never branch on top of another session's WIP.

3. **Resume-or-create.** Check the handoff + journal for a documented branch/worktree (`Branch:`/`Worktree:` line, `## Parked` entry, or an "Active" journal entry):
   - **Worktree present** → `cd` in, verify `git status`/`git branch`, resume. No new branch.
   - **Branch exists, worktree gone** (parked on `origin/<branch>` or local-only) → re-add: `git worktree add ../<repo>-<slug> <branch>` (or `/branch <slug> --reuse`). Resume on the existing branch.
   - **Nothing documented, or both gone** (shipped & pruned, or the handoff describes new work) → go to step 4.

   Unsure which applies → state findings and ask.

4. **(New work only) Create the worktree.** Derive a slug — prefer an arg, else propose one from the handoff's "next" work (kebab-case, `^[a-z][a-z0-9-]*$`; confirm if ambiguous). Invoke `branch` with it — it owns the path convention, journal entry, and base (default `main`). Don't hand-roll `git worktree add`.

5. **Project setup, if the repo needs it** (fresh/re-added worktree only). Fresh worktrees have no deps/secrets — check CLAUDE.md/the handoff for the convention (e.g. symlink `node_modules`, copy `.env`/`.dev.vars`). Skip if not needed.

6. **Load the context.** Summarize done / what's-next / first action. Rebuild TodoWrite from any unchecked `## Checklist`/`## Instructions` items, mirror to `docs/summaries/CHECKLIST.md` in the worktree. Heartbeat: `/branch update --working-on "<next task>"`.

7. **Confirm before working.** Present the first concrete next step and ask before proceeding — honor any design gate or `/branch`-before-code rule the handoff carries.

## Quick reference

| Invocation | Behavior |
|---|---|
| `/pickup` | Newest handoff → resume its worktree if documented, else new |
| `/pickup <slug>` | Same; slug used only when creating a NEW worktree |
| `/pickup 2026-06-14` / `/pickup budget` | Filter handoffs by date/topic |
| `/pickup docs/summaries/handoff-….md` | Use that exact handoff |

## Resume-or-create at a glance

| Handoff documents… | On disk | Action |
|---|---|---|
| active worktree | present | `cd` in, resume — no new branch |
| branch (parked/origin/local) | worktree gone | re-add worktree for it |
| nothing, or shipped+pruned | gone | create a fresh `branch` |

## Common mistakes

- **New branch when one exists** — a *pause* handoff usually names in-flight work to resume; fork only for shipped-and-pruned handoffs with genuinely new work.
- **Skipping the WIP check (step 2)** — cross-session WIP causes Frankenstein commits.
- **Reimplementing `branch`/`session-resume`** — call them; this skill only sequences them.
- **Auto-starting the work** — honor any design-gate/sign-off the handoff requires.
- **Hardcoding deps setup** — node_modules/.env is project-specific; only do step 5 when needed.
