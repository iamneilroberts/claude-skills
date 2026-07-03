---
name: pickup
description: >
  Use when the user wants to pick up / resume the most recent handoff in an
  isolated worktree — finds the newest handoff doc, RESUMES the worktree/branch
  it documents if one exists (re-adding it if parked), otherwise creates a fresh
  branch + worktree, then loads the handoff's context so work continues where it
  left off. Triggers on `/pickup`, "pick up the handoff", "resume the latest
  handoff in a worktree", "branch and continue". Distinct from `session-resume`
  (loads a handoff in-place, never branches) and `branch` (makes a worktree,
  loads no handoff) — `/pickup` does both, reusing an existing worktree when one
  is documented.
user_invocable: true
args: "[branch-slug | date/topic filter | handoff path]"
---

# Pickup

Resume the newest handoff in an isolated worktree, then load its context.
**Reuse the worktree/branch the handoff documents if it still exists; only create
a new one when none is documented or it's gone.** Orchestrates two existing
skills — do NOT reimplement their internals.

> **Requires the `branch` and `session-resume` skills from this same collection** (and, optionally,
> `/pm` for the in-flight-lanes tip below). It calls them rather than reimplementing worktree
> creation or handoff discovery, so install those alongside it.

## Steps

1. **Find the handoff.** Use the **`session-resume`** discovery logic (searches the
   shared coord `handoffs/` dir first, then legacy in-tree dirs). Honor its **handoff
   precedence**: prefer the newest *intentional* `pause-*.md`, falling back to a
   *mechanical* `auto-*.md` only when no intentional handoff exists. If an arg looks
   like a path, use it directly; if it looks like a date/topic/slug, filter by it
   (this is how you target a specific lane when several are in flight — e.g. the
   session name); otherwise take the newest intentional one. If several match, list
   the 5 most recent and ask which. If none, say so and stop. Read the chosen file.
   **Tip:** for a fast picture of all in-flight lanes before choosing, run `/pm`.

2. **WIP / worktree safety FIRST.** Run `git worktree list` + read the shared journal
   at `$(bash ~/.claude/coordination/resolve-coord-dir.sh)/journal.md` (the out-of-tree
   source of truth; the in-tree `docs/worktree-journal.md` is a tombstone pointer). If another session has uncommitted WIP or an
   active worktree that overlaps, surface it and pause before touching anything
   (per the worktree-awareness rule). Never branch on top of another session's WIP.

3. **Resume-or-create decision (the core of this skill).** Parse the handoff +
   journal for a documented branch/worktree (a `Branch:`/`Worktree:` line, a
   `## Parked` entry, or an "Active" journal entry for this topic). Then:
   - **Active worktree still on disk** (in `git worktree list`) → that's the
     target. `cd` into it, verify `git status`/`git branch`, resume there. **Do
     not create a new branch.**
   - **Branch exists but no worktree** — parked (on `origin/<branch>`) or local
     only (`git rev-parse --verify <branch>`) → re-add the worktree for it:
     `git worktree add ../<repo>-<slug> <branch>` (or `/branch <slug> --reuse`).
     Resume on the existing branch — don't fork a duplicate.
   - **Nothing documented, or the branch/worktree is gone** (e.g. work shipped &
     pruned, handoff describes NEW next-work) → create a fresh one: go to step 4.
   When unsure which case applies, state what you found and confirm with the user.

4. **(New-work path only) Create the worktree.** Derive a slug — prefer an arg,
   else propose one from the handoff's "next" work (kebab-case, e.g.
   `folio-budget-depth`; must match `^[a-z][a-z0-9-]*$`); confirm if ambiguous.
   Then invoke the **`branch`** skill with that slug (it owns the path convention
   `../<repo>-<slug>`, the journal entry, and base selection — default `main`).
   Don't hand-roll `git worktree add` for a brand-new branch.

5. **Project worktree setup (only if the repo needs it, and only for a freshly
   created/re-added worktree).** Fresh worktrees have
   no deps/secrets. If the project requires them (e.g. a `node_modules` symlink
   and `.env`/`.dev.vars` copy — check the project CLAUDE.md / handoff for the
   exact convention), set them up:
   `ln -s <main-clone>/node_modules <wt>/node_modules` and copy the gitignored
   env files. Skip for repos that don't need it.

6. **Load the context.** Summarize the handoff (done / what's-next / the first
   action). If it has a checklist or `## Checklist`/`## Instructions`, rebuild
   the TodoWrite list from the unchecked items and mirror to
   `docs/summaries/CHECKLIST.md` in the target worktree. Heartbeat the journal:
   `/branch update --working-on "<the next task from the handoff>"`.

7. **Confirm before working.** Present the first concrete next step from the
   handoff and ask whether to proceed (don't auto-start a big build; a design
   gate or `/branch`-before-code rule in the handoff still applies).

## Quick reference

| Invocation | Behavior |
|---|---|
| `/pickup` | Newest handoff → resume its worktree if documented, else new |
| `/pickup <slug>` | Same; use `<slug>` only when creating a NEW worktree |
| `/pickup 2026-06-14` / `/pickup budget` | Filter handoffs by date/topic first |
| `/pickup docs/summaries/handoff-….md` | Use that exact handoff |

## Resume-or-create at a glance

| Handoff documents… | …and on disk | Action |
|---|---|---|
| an active worktree | worktree present | `cd` in, resume — no new branch |
| a branch (parked/origin/local) | worktree gone | re-add worktree for that branch |
| nothing, or shipped+pruned | gone | create a fresh `branch` |

## Common mistakes

- **Creating a new branch when one already exists** — a *pause* handoff usually
  names an in-flight worktree/branch to RESUME; only a *shipped & pruned* handoff
  whose "next" is genuinely new work warrants a fresh branch. Forking a duplicate
  orphans the in-flight work.
- **Branching before the WIP check** — always run step 2 first; cross-session
  WIP has caused Frankenstein commits here.
- **Reimplementing `branch`/`session-resume`** — call them; this skill only
  sequences them.
- **Auto-starting the work** — `/pickup` sets the stage; honor any design-gate /
  sign-off the handoff requires before coding.
- **Hardcoding project deps setup** — node_modules/.env is project-specific;
  only do step 5 when the repo actually needs it.
