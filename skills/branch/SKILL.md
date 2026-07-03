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

Git worktrees give each session its own working files, HEAD, and index while sharing the `.git` directory (so all branches and objects are visible). This skill wraps `git worktree add` with project conventions and a journal entry so other sessions can see what's in flight.

## Argument shapes

```
/branch <task-slug> [--from <base-branch>] [--description "<text>"] [--reuse]
/branch list
/branch done <task-slug> [--force]
/branch update [--working-on "..."] [--state <state>] [--next "..."] [--blocked-by "..."] [--asks "..."] [--dont-touch "..."] [--slug <slug>]
/branch coord <message>
/branch coord clear <slug>
```

Parse the first positional arg. Dispatch:
- `list` → list mode
- `done` → done mode
- `update` → update mode (heartbeat current entry)
- `coord` → coord mode (manage `## Coordination` section)
- anything else → create mode, treat the arg as a task slug.

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

If `git rev-parse` fails, the user isn't in a git repo — tell them and stop.

**JOURNAL PATH (all modes):** the worktree journal is `$JOURNAL` =
`~/.claude/coordination/<repo>/journal.md` (resolve via the snippet above). It is NOT in
the tracked tree and is shared by every worktree of the repo. Wherever this skill says
"`docs/worktree-journal.md`" below, it means `$JOURNAL`. Never edit the in-tree
`docs/worktree-journal.md` (it's a tombstone pointer). The journal is not committed.

### 2. Validate the slug

- Must match `^[a-z][a-z0-9-]*$`. Reject otherwise with a one-line example of a valid slug.
- `git rev-parse --verify "refs/heads/<slug>"` — if the branch exists, refuse unless `--reuse` was passed.
- `git worktree list --porcelain | grep -q "branch refs/heads/<slug>"` — if a worktree already uses this branch, refuse.

### 3. Pick the base branch

- If `--from <base>` given, use that. Verify it exists (`git rev-parse --verify <base>`).
- Else: use `CURRENT_BRANCH`.
- If the current working tree has uncommitted modifications (`git status --porcelain | grep -v '^??'` non-empty), warn the user: those changes won't carry to the new worktree (`git worktree add` checks out from the base's HEAD, not the working tree). Ask whether to proceed or commit/stash first.

### 4. Resolve the description

- If `--description "..."` given, use it.
- Otherwise ask: "One-line description of what this worktree is for? (will go in the journal)". Use AskUserQuestion or a direct prompt.

### 5. Pick the worktree path

Default convention: sibling of the repo dir.
```
WORKTREE_PATH="$(dirname "$REPO_ROOT")/${REPO_NAME}-${SLUG}"
```

Override: if `${REPO_ROOT}/.claude/worktree-base` exists, read its contents as a path template. Substitute `{repo}` → `$REPO_NAME` and `{slug}` → `$SLUG`. Example template: `../worktrees/{repo}/{slug}`.

If the resolved path already exists, refuse and tell the user.

### 6. Create the worktree

```bash
git worktree add "$WORKTREE_PATH" -b "$SLUG" "$BASE_BRANCH"
```

If this fails, surface the exact error and stop. Do not write the journal entry on failure.

### 6b. Run the setup hook

A fresh worktree shares `.git` but **not** the working-tree files that are gitignored — most importantly local secrets (`.dev.vars`, `.env`) and build artifacts (`node_modules`). Without these a new session can't typecheck, run dev, or smoke-test. This step bootstraps them, borrowed from cmux's per-project setup hook.

**If `${REPO_ROOT}/.claude/worktree-setup.sh` exists**, run it inside the new worktree:

```bash
if [ -f "$REPO_ROOT/.claude/worktree-setup.sh" ]; then
  ( cd "$WORKTREE_PATH" && \
    REPO_ROOT="$REPO_ROOT" WORKTREE_PATH="$WORKTREE_PATH" SLUG="$SLUG" BASE_BRANCH="$BASE_BRANCH" \
    bash "$REPO_ROOT/.claude/worktree-setup.sh" )
fi
```

The hook is a repo-authored, version-controllable script (trusted — it's the user's own repo). It receives `REPO_ROOT` (the main clone, source for symlinking secrets), `WORKTREE_PATH`, `SLUG`, `BASE_BRANCH` in its environment and runs with the worktree as CWD. Typical contents: symlink gitignored secrets from the main clone, install deps, run codegen. Example:

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

**If no hook file exists**, don't invent one silently. Mention in the final output (step 8) that no `worktree-setup.sh` was found, and offer to scaffold one — for this repo the obvious contents are symlinking `.dev.vars`/`.env` and running `npm install`. Skip the offer if the repo has no `package.json` and no gitignored env files (nothing to bootstrap).

### 7. Update the journal

Path: `$JOURNAL` (the out-of-tree `~/.claude/coordination/<repo>/journal.md`, resolved in
step 1). Never write the in-tree `docs/worktree-journal.md` tombstone.

If the file is missing, create it with this header:

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

`Description` is the immutable charter. `Working on` is the heartbeat — the verb-phrase you'd answer "what are you doing right now?" with. `State` and `Next action` feed the optional `/pm` board (a companion skill in this collection): `State` is one of `building` / `in-review` / `blocked` / `almost-done` / `stale`, and `Next action` is the paste-to-resume line (e.g. `/pickup <slug>`, or a specific command like "review PR #218, merge, deploy") so a cold reader knows the single next move without re-deriving it. The `Blocked by:`, `Don't touch:`, and `Asks:` fields are added by `/branch update` only when populated; omit them at create time.

If the file is missing the `## Coordination` section (legacy journal), insert it between `## Active` and `## Done`:

```markdown
## Coordination

Cross-cutting constraints active across sessions. Format:
`<YYYY-MM-DD HH:MM> — <slug>: <constraint>. <expires when or unblock condition>.`

- (none active)
```

Just save the journal file. It lives out of the tracked tree (`$JOURNAL`), so there is nothing to commit — the entry is live for all sessions the moment it's written.

### 8. Output to user

Tell the user:
- Path of the new worktree (absolute)
- Branch name created
- Setup hook result: ran (one-line summary of what it did), or "no `.claude/worktree-setup.sh` found" plus the offer to scaffold one (per step 6b)
- Suggested next move: open a new Claude Code session at that path (`cd <path> && claude`), or `cd` for shell work
- Note: the **current session stays in the original directory**. Switching the agent's working dir mid-session is fragile. Pause this session if the new work supersedes it.

---

## Mode: list

Trigger: first arg is exactly `list`.

1. Run `git worktree list --porcelain` and parse the output. Each worktree has a `worktree <path>`, `HEAD <sha>`, `branch <ref>` triple separated by blank lines.
2. Read `$JOURNAL`. For each active entry, capture description + start date.
3. For each worktree, also fetch:
   - Last commit relative time: `git -C <path> log -1 --format='%cr'`
   - Uncommitted changes count: `git -C <path> status --porcelain | wc -l`
4. Print a table:

```
SLUG                          BRANCH                    LAST COMMIT   WIP   DESCRIPTION
feature-alpha                 feature-alpha             2 hours ago   0     Add the alpha feature
bugfix-beta                   bugfix-beta               12 min ago    1     Fix the beta bug
(main)                        docs-index                30 min ago    0     —
```

Mark the current session's worktree with a `*` prefix.

If the journal has entries with no matching worktree (orphans), list them under "Stale journal entries" and suggest running `/branch done <slug>` to close out.

---

## Mode: done

Trigger: `/branch done <slug>`.

1. Find the worktree for `<slug>`:
   ```bash
   git worktree list --porcelain | awk -v s="<slug>" '/^worktree/{p=$2} /^branch/ && $2=="refs/heads/"s {print p; exit}'
   ```
   If no match, ask whether the user wants to just close the journal entry (orphan cleanup) and skip `git worktree remove`.

2. Check the worktree's state:
   - Uncommitted changes (`git -C <path> status --porcelain` non-empty)? Refuse without `--force` and report what's dirty.
   - Branch unmerged to its base? Detect via `git -C <path> log <base>..HEAD --oneline`. If non-empty, warn: "Branch has N unmerged commits. Has the work been pushed and merged via PR?" — let the user proceed if they confirm.

3. Ask the user for an outcome line: "What was the outcome? (shipped / abandoned / merged-as-PR-#NNN / etc.)"

4. Update journal:
   - Move entry from `## Active` to `## Done`
   - Append: `- **Closed:** <YYYY-MM-DD HH:MM>`, `- **Outcome:** <outcome>`
   - Change status to `done`

5. Run `git worktree remove <path>` (add `--force` if uncommitted changes were present and user passed `--force`).

6. Suggest a branch-cleanup command but do **not** run it:
   - If merged: `git branch -d <slug>`
   - If abandoned: `git branch -D <slug>`
   - If pushed: `git push origin --delete <slug>` after the local delete

   Branch deletion is destructive. The user runs it themselves.

---

## Mode: update

Trigger: `/branch update`. Heartbeat the current worktree's Active entry. Each invocation bumps `Last update` to now and sets/clears any provided fields.

### 1. Resolve the slug

- If `--slug <slug>` given, use it.
- Otherwise infer from the current working dir:
  ```bash
  CWD_REPO=$(git rev-parse --show-toplevel)
  # The slug is the branch name of the current worktree
  SLUG=$(git rev-parse --abbrev-ref HEAD)
  ```
  If the slug isn't a `## Active` entry in `$JOURNAL` (e.g. user is on `main`), refuse: "Not on a worktree branch — use `--slug` explicitly or `cd` into the worktree first."

### 2. Field semantics

- `--working-on "..."` — replaces `Working on:` value. Empty string `""` resets to `(idle)`.
- `--state <state>` — sets `State:`. One of `building` / `in-review` / `blocked` / `almost-done` / `stale`. Reject any other value with a one-line list of the valid states. (`blocked` should usually accompany `--blocked-by`.)
- `--next "..."` — sets `Next action:` (the paste-to-resume line a cold reader follows). Empty string `""` resets to `(idle)`.
- `--blocked-by "..."` — sets `Blocked by:` line. Empty string removes the line.
- `--asks "..."` — sets `Asks:` line. Empty string removes the line. For multiple asks, join with `; ` or call multiple times (each call replaces).
- `--dont-touch "..."` — sets `Don't touch:` line. Empty string removes the line.

If no field flags given, only `Last update` is bumped (a "still alive" ping).

### 3. Apply the update

Edit the entry in-place under `## Active`. Add fields in canonical order: Started, Branch, Worktree, Base, Description, **Working on**, **State** (if set), **Next action** (if set), **Last update**, **Blocked by** (if set), **Don't touch** (if set), **Asks** (if set), Status. Use `date '+%Y-%m-%d %H:%M'` for the timestamp.

Do **not** auto-commit. The journal change goes in the next batch.

### 4. Output

Print the updated entry's relevant lines to confirm. One-liner: `Updated <slug>: <field>=<value>. Last update: <timestamp>.`

---

## Mode: coord

Trigger: `/branch coord <message>` or `/branch coord clear <slug>`.

### Sub-mode: post

`/branch coord <message>` (where `<message>` is everything after the `coord` keyword)

1. Resolve current slug (same logic as update mode). If on `main` / not in a worktree, the slug is `(main)`.
2. Open `$JOURNAL`. If `## Coordination` section is missing, create it between `## Active` and `## Done` using the template from create mode step 7.
3. If the section's only content is `- (none active)`, replace with the new entry. Otherwise append.
4. Entry format:
   ```
   - <YYYY-MM-DD HH:MM> — <slug>: <message>
   ```
5. Echo: `Posted to ## Coordination as <slug>: <message>. Other sessions will see this on their next prompt.`

### Sub-mode: clear

`/branch coord clear <slug>`

1. Open the journal. Remove every line in `## Coordination` whose source is `<slug>` (matches `— <slug>:`).
2. If the section becomes empty, restore `- (none active)`.
3. Echo: `Cleared <N> coord lines from <slug>.`

Do **not** auto-commit.

---

## Edge cases

- **Worktree directory was deleted manually** but `git worktree list` still shows it: run `git worktree prune`, then update the journal.
- **Journal file exists but a worktree referenced in it is gone:** flag as a stale entry under `list`. Offer cleanup via `done`.
- **User invokes /branch from inside a non-main worktree:** still works — `git worktree add` from any worktree operates on the shared `.git`. The new worktree is still created relative to the *main* clone's parent dir (use `git rev-parse --git-common-dir` to find it if needed). For simplicity: resolve `REPO_ROOT` from the current worktree's main clone:
  ```bash
  MAIN_CLONE=$(git worktree list --porcelain | head -1 | awk '/^worktree/{print $2}')
  ```
- **The coordination dir doesn't exist yet:** `resolve-coord-dir.sh` creates `~/.claude/coordination/<repo>/` on first run; if you're not using that script, create the journal's parent dir before writing it.
- **Worktree base override file (`.claude/worktree-base`) contains an absolute path:** allow it. Useful if user wants worktrees on a different filesystem.

## Why bother (for new readers)

Without isolation, two agent sessions in the same dir corrupt each other:
- Session A is mid-deploy on branch X with uncommitted WIP. Session B runs `git checkout Y`. Session A's uncommitted edits silently follow to branch Y, get bundled into Session B's next commit, and ship a Frankenstein change.
- Or: Session A reads tools-list while Session B has half-installed `node_modules` from a partial `npm install` — typecheck fails non-deterministically.

A worktree per task fixes both. Cost is one extra directory and ~zero git overhead (`.git` is shared).

## Conventions used here (from the plan that birthed this skill)

- Journal: `~/.claude/coordination/<repo>/journal.md` (out-of-tree, shared across worktrees, NOT committed; resolve via `~/.claude/coordination/resolve-coord-dir.sh`)
- Worktree path: `../<repo-name>-<slug>` (flat siblings of the repo dir)
- Branch name: `<slug>` (no `wt/` prefix — keep names natural)
- Setup hook: optional repo-authored `.claude/worktree-setup.sh`, run inside the fresh worktree to symlink gitignored secrets + install deps (cmux-style). Never auto-created — offered when absent.
- Skill never auto-commits or auto-deletes branches
- Cross-repo journal merging is out of scope (each repo's journal stands alone)

## Journal schema (v2 — 2026-04-30)

Active entries carry these fields (canonical order):

| Field | Required | Mutable | Set by |
|---|---|---|---|
| Started | yes | no | create |
| Branch | yes | no | create |
| Worktree | yes | no | create |
| Base | yes | no | create |
| Description | yes | no | create |
| Working on | yes | yes | create (`(starting)`), update |
| State | no | yes | create (`building`), update |
| Next action | no | yes | create (`(starting)`), update |
| Last update | yes | yes | create, update, coord |
| Blocked by | no | yes | update |
| Don't touch | no | yes | update |
| Asks | no | yes | update |
| Status | yes | yes | create (`active`), done |

Top-level `## Coordination` section between `## Active` and `## Done` holds cross-cutting constraints.

**Migrating a v1 entry to v2:** add `Working on: (idle)` and `Last update: <last commit time on the branch>` fields. Don't backfill `Blocked by/Don't touch/Asks` unless you have current info.
