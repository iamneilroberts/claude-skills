---
name: codex
description: Delegate a task or question to the OpenAI Codex CLI running as an isolated subagent, then relay its answer. Use when the user invokes /codex <prompt>, says "ask codex", "have codex look at / do X", or wants a second independent model to investigate a question or make a self-contained edit. Read-only by default; /codex --write lets Codex edit the working tree. Distinct from /codex-review, which is the structured JSON review gate — /codex is a general-purpose Codex delegate.
---

# /codex — delegate to the Codex CLI via a subagent

Runs the OpenAI Codex CLI (`codex exec`) on the user's prompt inside a **dispatched
subagent**, so Codex's (possibly large) output stays out of the main context and you relay
only its answer. Codex is a genuinely independent model — good for a second opinion, an
adversarial read, or offloading a self-contained investigation or edit.

Helper: `codex.sh` (this skill's dir) runs `codex exec`, captures only Codex's final
message (`-o`), and falls back across models on failure.

## When to use
- `/codex <prompt>` — hand any question or task to Codex against this repo.
- "ask codex to …", "have codex look at …", "get codex to write / refactor …".
- NOT the structured review gate — that's `/codex-review`.

## How to run

1. **Parse the invocation.** Everything after `/codex` is the PROMPT. Flags:
   - `--write` → Codex may edit the working tree (workspace-write sandbox). Default is read-only.
   - `-m <model>` → pin a Codex model. `--dir <path>` → working root (default: repo root).

2. **Dispatch ONE subagent** (Agent tool, `subagent_type: general-purpose`). Pin the model
   explicitly: `haiku` for a plain ask/relay; `sonnet` if Codex is making edits and you want
   the result sanity-checked. Give it this task (substitute `<SKILL_DIR>` = this skill's base
   directory, and `<PROMPT>`):

   > Run the Codex CLI and return its final answer VERBATIM — trim only banner/progress
   > noise, do not summarize or editorialize. Run:
   > `printf %s '<PROMPT>' | bash <SKILL_DIR>/codex.sh [--write] [--stats] [-m MODEL] -`
   > (stdin form avoids quoting problems for long or quote-heavy prompts). If the script
   > exits non-zero, report its stderr line so the caller can retry. If `--write` was used,
   > also run `git status --short` and `git --no-pager diff` afterward and include a short
   > list of what Codex changed.

   **Only pass `--stats`** when the user asked for Codex's token usage or API cost (e.g. a
   model comparison / cost accounting). It appends a token-usage + estimated-cost block after
   the answer; relay that block verbatim. Omit `--stats` for normal delegation so output stays
   clean. Cost is an estimate — override the rates with `CODEX_PRICE_INPUT_PER_M` /
   `CODEX_PRICE_CACHED_PER_M` / `CODEX_PRICE_OUTPUT_PER_M` if the model's real pricing differs.

3. **Relay Codex's answer** to the user, attributed ("Codex says:") so it's clear this is the
   second model, not you. If `--write` was used, review the diff the subagent returned and
   summarize what Codex changed **before trusting it** — never present Codex's edits as
   verified without looking at the diff.

## Notes
- Read-only is the safe default; pass `--write` only when the user clearly wants Codex to
  edit files.
- Codex's output is not ground truth. Verify anything that matters — especially `--write`
  edits — against the actual code and the test suite.
- If `codex.sh` reports rate-limit / auth failure, tell the user and offer to retry (or try a
  different `-m` model).
