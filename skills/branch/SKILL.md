---
name: branch
description: >
  Create an isolated git worktree for a new task, log it to the repo's work
  journal, and prepare a clean workspace so multiple Claude Code sessions can
  run in parallel without clobbering each other's HEAD or uncommitted edits.
  Use whenever the user starts a new coding task in a repo that may have other
  agent sessions active, or when you detect WIP from another session in the
  current working tree. Subcommands: `list`, `done <slug>`, `update`
  (heartbeat: working-on / blocked-by / asks / dont-touch), `coord <message>`
  (post a cross-session constraint), `coord clear <slug>` (drop one session's
  coord lines). Also triggers on phrases like "start in a worktree", "isolate
  this work", "parallel session", "clean workspace for X", "post a coord note",
  "heartbeat the journal", "what are the other sessions doing".
model: sonnet
---

# /branch — Isolated worktree creation for parallel agent sessions

Two Claude Code sessions in the same working directory race on:
- **HEAD** — `git checkout` switches it for everyone in that dir
- **Uncommitted edits** — they leak across branch checkouts
- **The index** — staging-area collisions

Git worktrees give each session its own working files, HEAD, and index while sharing `.git` (all branches/objects stay visible). This skill wraps `git worktree add` with project conventions and a journal entry so other sessions can see what's in flight. Cost: one extra directory, ~zero git overhead.

## Argument shapes

```
/branch <task-slug> [--from <base-branch>] [--description "<text>"] [--reuse]
/branch list
/branch done <task-slug> [--force]
/branch update [--working-on "..."] [--state <state>] [--next "..."] [--blocked-by "..."] [--asks "..."] [--dont-touch "..."] [--slug <slug>]
/branch coord <message>
/branch coord clear <slug>
```

Parse the first positional arg and dispatch: `list`→list mode, `done`→done mode, `update`→update mode (heartbeat current entry), `coord`→coord mode (manage `## Coordination`), anything else→create mode (treat the arg as a task slug).

---

## Mode: create (default)

### 1. Resolve repo info

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
REPO_NAME=$(basename "$REPO_ROOT")
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
# The journal lives OUT of the tracked tree, shared across all worktrees of this repo:
COORD_DIR=$(bash ~/.claude/coordination/resolve-coord-dir.sh)   # → ~/.claude/coordination/<repo>
JOURNAL="$COORD_DIR/journal.md"
```

If `git rev-parse` fails, tell the user they're not in a git repo and stop.

**Journal path (applies in every mode):** `$JOURNAL` = `~/.claude/coordination/<repo>/journal.md` — out of the tracked tree, shared by every worktree of the repo, never committed. Any reference below to `docs/worktree-journal.md` means `$JOURNAL`. **Never edit the in-tree `docs/worktree-journal.md`** — it's a tombstone pointer, not the real journal.

### 2. Validate the slug, pick the base branch, resolve the description

- **Validate the slug:** must match `^[a-z][a-z0-9-]*$` (reject otherwise with a one-line example of a valid slug). Refuse if `git rev-parse --verify "refs/heads/<slug>"` finds an existing branch, unless `--reuse` was passed. Refuse if `git worktree list --porcelain | grep -q "branch refs/heads/<slug>"` finds a worktree already on that branch.
- **Pick the base branch:** use `--from <base>` if given (verify with `git rev-parse --verify <base>`), otherwise `CURRENT_BRANCH`. If the working tree has uncommitted modifications (`git status --porcelain | grep -v '^??'` non-empty), warn that they won't carry over — `git worktree add` checks out the base's HEAD, not the working tree — and ask whether to proceed or commit/stash first.
- **Resolve the description:** use `--description "..."` if given, otherwise ask: "One-line description of what this worktree is for? (will go in the journal)".

### 3. Pick the worktree path

Default: sibling of the repo dir.
```
WORKTREE_PATH="$(dirname "$REPO_ROOT")/${REPO_NAME}-${SLUG}"
```

Override: if `${REPO_ROOT}/.claude/worktree-base` exists, read it as a path template; substitute `{repo}`→`$REPO_NAME`, `{slug}`→`$SLUG` (e.g. `../worktrees/{repo}/{slug}`). Absolute-path templates are fine — useful for a different filesystem.

Refuse if the resolved path already exists.

### 4. Create the worktree and run the setup hook

```bash
git worktree add "$WORKTREE_PATH" -b "$SLUG" "$BASE_BRANCH"
```

On failure, surface the exact error and stop — do not write the journal entry.

A fresh worktree shares `.git` but not gitignored working-tree files — notably local secrets (`.dev.vars`, `.env`) and build artifacts (`node_modules`). Without these a new session can't typecheck, run dev, or smoke-test.

**If `${REPO_ROOT}/.claude/worktree-setup.sh` exists**, run it inside the new worktree:

```bash
if [ -f "$REPO_ROOT/.claude/worktree-setup.sh" ]; then
  ( cd "$WORKTREE_PATH" && \
    REPO_ROOT="$REPO_ROOT" WORKTREE_PATH="$WORKTREE_PATH" SLUG="$SLUG" BASE_BRANCH="$BASE_BRANCH" \
    bash "$REPO_ROOT/.claude/worktree-setup.sh" )
fi
```

The hook is a repo-authored, version-controlled, trusted script. It receives `REPO_ROOT` (main clone, source for symlinking secrets), `WORKTREE_PATH`, `SLUG`, `BASE_BRANCH` in its environment, with the worktree as CWD. Typical contents: symlink gitignored secrets from the main clone, install deps, run codegen. Example:

```bash
#!/usr/bin/env bash
set -euo pipefail
# Symlink local secrets from the main clone (gitignored, not carried by the worktree)
for f in .dev.vars .env; do
  [ -e "$REPO_ROOT/$f" ] && [ ! -e "$f" ] && ln -s "$REPO_ROOT/$f" "$f"
done
# Install deps (share-nothing; worktrees each need their own node_modules)
[ -f package.json ] && npm install --no-audit --no-fund
```

Surface the hook's stdout/stderr to the user. **If the hook fails, do not delete the worktree** — it's already created and the journal entry should still be written; report the failure and let the user fix and re-run the hook by hand.

**If no hook file exists**, don't invent one silently — mention it in step 6's output and offer to scaffold one (for this repo: symlink `.dev.vars`/`.env`, run `npm install`). Skip the offer if the repo has no `package.json` and no gitignored env files.

### 5. Update the journal

If `$JOURNAL` is missing, create it with this header:

```markdown
# Worktree Journal

Active and recent isolated worktrees for this repo. Agents starting new
sessions should review this. Mark entries `done` with `/branch done <slug>`
when the work ships or is abandoned.

## Active

## Done
```

Insert the new entry under `## Active` (newest first):

```markdown
### <slug>
- **Started:** <YYYY-MM-DD HH:MM> (use `date '+%Y-%m-%d %H:%M'`)
- **Branch:** `<slug>`
- **Worktree:** `<absolute path>`
- **Base:** `<base-branch>`
- **Description:** <description — long-term goal, set at create, doesn't change>
- **Working on:** <one-line current focus, set to "(starting)" at create>
- **State:** building
- **Next action:** (starting)
- **Last update:** <same as Started>
- **Status:** active
```

Field semantics are defined once, in the Journal schema section at the end of this file. Omit `Blocked by`/`Don't touch`/`Asks` at create time — `/branch update` adds them when populated.

If the journal is missing `## Coordination` (legacy journal), insert it between `## Active` and `## Done`:

```markdown
## Coordination

Cross-cutting constraints active across sessions. Format:
`<YYYY-MM-DD HH:MM> — <slug>: <constraint>. <expires when or unblock condition>.`

- (none active)
```

Save the file — it lives out of the tracked tree, so there's nothing to commit; the entry is live for all sessions the moment it's written.

### 6. Output to user

Tell the user:
- The new worktree's absolute path and branch name
- Setup hook result: ran (one-line summary of what it did), or "no `.claude/worktree-setup.sh` found" plus the scaffold offer (step 4)
- Suggested next move: open a new Claude Code session at that path (`cd <path> && claude`), or `cd` for shell work
- The **current session stays in the original directory** — switching an agent's working dir mid-session is fragile. Pause this session if the new work supersedes it.

---

## Mode: list

Trigger: first arg is exactly `list`.
1. Run `git worktree list --porcelain` and parse the `worktree <path>` / `HEAD <sha>` / `branch <ref>` triples (blank-line separated).
2. Read `$JOURNAL`. For each active entry, capture description + start date.
3. For each worktree, also fetch last commit relative time (`git -C <path> log -1 --format='%cr'`) and uncommitted-changes count (`git -C <path> status --porcelain | wc -l`).
4. Print a table:

```
SLUG                          BRANCH                    LAST COMMIT   WIP   DESCRIPTION
feature-alpha                 feature-alpha             2 hours ago   0     Add the alpha feature
bugfix-beta                   bugfix-beta               12 min ago    1     Fix the beta bug
(main)                        docs-index                30 min ago    0     —
```

Mark the current session's worktree with a `*` prefix. Journal entries with no matching worktree are orphans — list them under "Stale journal entries" and suggest `/branch done <slug>` to close out.

---

## Mode: done

Trigger: `/branch done <slug>`.
1. Find the worktree for `<slug>`:
   ```bash
   git worktree list --porcelain | awk -v s="<slug>" '/^worktree/{p=$2} /^branch/ && $2=="refs/heads/"s {print p; exit}'
   ```
   No match → ask whether the user wants to just close the journal entry (orphan cleanup) and skip `git worktree remove`.
2. Check the worktree's state: uncommitted changes (`git -C <path> status --porcelain` non-empty)? Refuse without `--force` and report what's dirty. Branch unmerged to its base (`git -C <path> log <base>..HEAD --oneline` non-empty)? Warn "Branch has N unmerged commits. Has the work been pushed and merged via PR?" and let the user proceed if they confirm.
3. Ask the user for an outcome line: "What was the outcome? (shipped / abandoned / merged-as-PR-#NNN / etc.)"
4. Update the journal: move the entry from `## Active` to `## Done`; append `- **Closed:** <YYYY-MM-DD HH:MM>` and `- **Outcome:** <outcome>`; change status to `done`.
5. Run `git worktree remove <path>` (add `--force` if uncommitted changes were present and the user passed `--force`).
6. Suggest a branch-cleanup command but do **not** run it — branch deletion is destructive, the user runs it themselves: merged → `git branch -d <slug>`; abandoned → `git branch -D <slug>`; pushed → also `git push origin --delete <slug>` after the local delete.

---

## Mode: update

Trigger: `/branch update`. Heartbeats the current worktree's Active entry — each invocation bumps `Last update` to now and sets/clears any provided fields.

**Resolve the slug:** use `--slug <slug>` if given, otherwise infer from the current working dir:
```bash
CWD_REPO=$(git rev-parse --show-toplevel)
# The slug is the branch name of the current worktree
SLUG=$(git rev-parse --abbrev-ref HEAD)
```
If the slug isn't a `## Active` entry in `$JOURNAL` (e.g. user is on `main`), refuse: "Not on a worktree branch — use `--slug` explicitly or `cd` into the worktree first."

**Field semantics:**
- `--working-on "..."` — replaces `Working on:`. Empty string `""` resets to `(idle)`.
- `--state <state>` — sets `State:`, one of `building` / `in-review` / `blocked` / `almost-done` / `stale`. Reject other values with a one-line list of valid states. (`blocked` should usually pair with `--blocked-by`.)
- `--next "..."` — sets `Next action:` (the paste-to-resume line a cold reader follows). Empty string `""` resets to `(idle)`.
- `--blocked-by "..."` — sets `Blocked by:`. Empty string removes the line.
- `--asks "..."` — sets `Asks:`. Empty string removes the line; for multiple asks join with `; ` or call multiple times (each call replaces).
- `--dont-touch "..."` — sets `Don't touch:`. Empty string removes the line.

No field flags given → only `Last update` is bumped (a "still alive" ping).

**Apply and output:** edit the entry in place under `## Active`, fields in canonical order (see Journal schema below). Use `date '+%Y-%m-%d %H:%M'` for the timestamp. Do **not** auto-commit — the journal change goes in the next batch. Then print the updated entry's relevant lines to confirm. One-liner: `Updated <slug>: <field>=<value>. Last update: <timestamp>.`

---

## Mode: coord

Trigger: `/branch coord <message>` or `/branch coord clear <slug>`.

### Sub-mode: post

`/branch coord <message>` (where `<message>` is everything after the `coord` keyword).
1. Resolve current slug (same logic as update mode). If on `main` / not in a worktree, the slug is `(main)`.
2. Open `$JOURNAL`. If `## Coordination` is missing, create it between `## Active` and `## Done` using the template from create-mode step 5.
3. If the section's only content is `- (none active)`, replace it with the new entry; otherwise append. Entry format: `- <YYYY-MM-DD HH:MM> — <slug>: <message>`
4. Echo: `Posted to ## Coordination as <slug>: <message>. Other sessions will see this on their next prompt.`

### Sub-mode: clear

`/branch coord clear <slug>`.
1. Open the journal. Remove every line in `## Coordination` whose source is `<slug>` (matches `— <slug>:`).
2. If the section becomes empty, restore `- (none active)`.
3. Echo: `Cleared <N> coord lines from <slug>.`

Do **not** auto-commit.

---

## Edge cases

- **Worktree directory was deleted manually** but `git worktree list` still shows it: run `git worktree prune`, then update the journal.
- **Journal file exists but a worktree referenced in it is gone:** flag as a stale entry under `list`. Offer cleanup via `done`.
- **User invokes /branch from inside a non-main worktree:** still works — `git worktree add` operates on the shared `.git` from any worktree. Resolve `REPO_ROOT` from the current worktree's main clone:
  ```bash
  MAIN_CLONE=$(git worktree list --porcelain | head -1 | awk '/^worktree/{print $2}')
  ```
- **The coordination dir doesn't exist yet:** `resolve-coord-dir.sh` creates `~/.claude/coordination/<repo>/` on first run; if you're not using that script, create the journal's parent dir before writing it.
- **Worktree base override file (`.claude/worktree-base`) contains an absolute path:** allow it.

## Journal schema (v2 — 2026-04-30)

Branch names are the slug itself (no `wt/` prefix). Cross-repo journal merging is out of scope — each repo's journal stands alone.

Active entries carry these fields, in canonical order:

| Field | Required | Mutable | Set by |
|---|---|---|---|
| Started | yes | no | create |
| Branch | yes | no | create |
| Worktree | yes | no | create |
| Base | yes | no | create |
| Description | yes | no | create — the immutable charter |
| Working on | yes | yes | create (`(starting)`), update — the heartbeat: "what are you doing right now" |
| State | no | yes | create (`building`), update |
| Next action | no | yes | create (`(starting)`), update — the paste-to-resume line |
| Last update | yes | yes | create, update, coord |
| Blocked by | no | yes | update |
| Don't touch | no | yes | update |
| Asks | no | yes | update |
| Status | yes | yes | create (`active`), done |

`## Coordination`, between `## Active` and `## Done`, holds cross-cutting constraints (see Mode: coord).

**Migrating a v1 entry to v2:** add `Working on: (idle)` and `Last update: <last commit time on the branch>`. Don't backfill `Blocked by`/`Don't touch`/`Asks` unless you have current info.
