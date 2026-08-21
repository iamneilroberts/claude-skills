---
name: comment-refactor
description: Refactor the comments in AI-generated (or long-lived) code — strip the accumulation of fix-history narration, obsolete explanations, and code-restating noise while preserving load-bearing WHY/TODO/warning comments. Works over a path, glob, or the whole repo; skips dead/abandoned/unused and vendored/generated files; and stamps each cleaned file with a content-hash marker so re-runs skip files that haven't changed. Incorporates the /remove-comments and /deslop (humanizer) heuristics plus a used-code filter and incremental idempotency. Triggers on `/comment-refactor [path|glob]`, "refactor the comments", "clean up comment cruft", "strip obsolete comments".
user_invocable: true
args: "<path | glob | (empty for whole repo)> — what to refactor"
license: MIT
---

# /comment-refactor — clean comment cruft, incrementally, across a codebase

Comments in AI-assisted code accumulate: fix-history narration (`// changed to X because the old
way broke`), stale explanations that no longer match the code, and line-by-line restating of what
the code plainly does. This skill removes that layer while keeping the comments that carry real
information, across many files, and **only re-touches files that changed since their last pass**.

It composes three things:
1. the `/remove-comments` keep/remove judgment (the engine),
2. the `/deslop` → **humanizer** pass applied to comment *prose* (AI-tell removal inside the
   comments that survive), and
3. two mods you asked for: a **used-code filter** (skip dead/abandoned/unused + vendored/generated
   files) and an **incremental content-hash marker** (skip files already up to date).

## Bundled helpers

- `marker.py` — the idempotency control marker. `check <file>` (exit 0 = up-to-date/skip, 10 =
  process), `stamp <file>` (write/refresh the marker), `hash <file>`. The marker is
  `@comment-refactor:v1:<sha256(body-without-marker)[:16]>` in the file's own comment syntax,
  placed at the top (after a shebang). Excluding the marker line from the hash makes re-stamping
  stable; any real edit changes the hash and forces a reprocess.
- `scan.sh [path|glob …]` — prints the mechanical worklist (`PROCESS <file>` / `SKIP-UPTODATE
  <file>`), applying the extension allowlist, the vendored/generated exclusions, and the marker
  check. Default scope is the git-tracked tree.

## Procedure

### 1. Resolve scope
From the argument: a file → that file; a directory/glob → its matching files; **empty → the whole
repo**. Run the scan to get the worklist:

```bash
bash "$SKILL_DIR/scan.sh" <path-or-glob>     # omit arg for the whole repo
```

`SKILL_DIR` is this skill's directory. Everything marked `SKIP-UPTODATE` is already clean since its
last pass — ignore it. Work only the `PROCESS` list.

### 2. Filter to code that's actually used (the used-code mod)
The scan already drops `node_modules`/`dist`/`build`/`vendor`/`.min.`/`*.d.ts`/generated dirs. Now
drop **dead/abandoned/unused** source too, so effort goes to live code:

- If the `repowise` MCP server is available, call `get_dead_code` and remove any `PROCESS` file it
  flags as dead/unreachable. If `codebase-memory` is available instead, use `search_graph` /
  reachability to the same end.
- If neither is available, fall back to obvious signals only — files with no inbound imports, files
  under `legacy/`/`deprecated/`/`archive/`, and anything the repo's own docs mark obsolete — and
  **say in the summary that the dead-code filter was heuristic, not tool-verified.**

Never delete or edit a file you're skipping; just leave it out of the worklist.

### 3. Refactor each PROCESS file
Read the file. Apply the keep/remove judgment (comment syntax is language-specific — `//`, `#`,
`--`, `/* */`, `<!-- -->`, docstrings).

**REMOVE:**
- Comments that restate the code (`// increment i`, `# return the result`, `// constructor`).
- **Fix-history / changelog narration** in comments: `// changed to…`, `// was previously…`,
  `// fixed bug where…`, `// updated 2024-… to handle…`, stacked layers of `// also handle…` added
  over time. The comment should describe the code as it is now, not its edit history — that's what
  git is for.
- Obsolete explanations that no longer match the current code (verify against the actual code, not
  the comment's claim).
- AI narration of control flow (`// Now we loop over the items and…`, `// First, we check if…`).
- Commented-out code (`// const old = …`) unless a nearby comment explains why it's intentionally
  parked.

**PRESERVE (do not touch):**
- WHY a non-obvious choice was made; business-logic rationale; the repo's own "load-bearing"
  comments.
- `TODO` / `FIXME` / `HACK` / `XXX`, `MARK:`/section markers, and warnings about non-obvious or
  dangerous behavior.
- License/copyright headers, `@ts-*` / `eslint-*` / `noqa` / type-directive pragmas, and generator
  markers — including **this skill's own `@comment-refactor:v1:` marker**.

**CONSOLIDATE:** where several stacked comments describe one thing (typically fix-history), collapse
to a single present-tense line, or delete if the code is now self-evident.

Then de-slop the surviving comment **prose**. If the `humanizer` skill is available, invoke it
(Skill tool, `skill=humanizer`) on the comment text — it's the source of truth (`/deslop` is its
alias). If it isn't installed, apply its core rules inline: no em-dash overuse, no rule-of-three, no
AI vocabulary ("leverage", "seamless", "robust"), no filler/hedging. Either way, keep the technical
content and stay neutral — never rewrite comments in anyone's "voice".

Keep changes surgical — comments only. Do not touch code, formatting, or imports.

### 4. Stamp the marker
After editing a file, refresh its marker so future runs skip it until it changes again:

```bash
python3 "$SKILL_DIR/marker.py" stamp <file>
```

Stamp **only** files you actually refactored (or confirmed already clean this pass) — the marker
asserts "these comments were reviewed at this content hash."

### 5. Confirm + report
- **Default to a dry-run first** on a multi-file scope: show the worklist and a sample of the
  removals per file, and get a go-ahead before applying — a bulk comment sweep is easy to over-cut.
  A single-file / small scope can apply directly with the diff shown.
- Report: files processed, files skipped up-to-date, files skipped as dead/vendored, and a one-line
  note if the dead-code filter was heuristic.

## Notes
- The marker makes the skill cheap to re-run: a second pass over an unchanged repo does almost no
  work (all `SKIP-UPTODATE`). Run it after a big AI-assisted coding burst.
- Bump the marker version (`v1`→`v2`) only if the keep/remove rules change enough that every file
  deserves a fresh pass — that invalidates all existing markers by design.
- Language coverage is the marker helper's extension map; an unsupported extension is reported and
  left unstamped rather than guessed.
