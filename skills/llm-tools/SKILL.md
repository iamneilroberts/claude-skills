---
name: llm-tools
description: Use when a session is about to bulk-read 3+ files or any single file over ~400 lines, generate predictable boilerplate (tests, fixtures, config scaffolds, doc templates), or compress a long session transcript — and a cheap OpenAI-compatible worker model (Kimi, DeepSeek, OpenRouter, local Ollama) is available via the llm-ask/llm-write/llm-extract CLIs.
---

# llm-tools — cheap-worker delegation

## Overview

Premium-model context is the scarcest resource in a session. These three CLIs route
bulk I/O and predictable generation to a cheap long-context worker; the premium model
consumes the short answer instead of the raw files. Install + provider config:
[README.md](README.md) in this directory (~1-minute setup, any
`/v1/chat/completions` provider).

## Routing rules (the rules save the tokens; the CLIs just execute)

| Situation | Do this |
|---|---|
| Would read 3+ files, or one file >~400 lines, to answer a question | `llm-ask <files...> -q "..."` — read the answer, not the files |
| Need tests / fixtures / config scaffold / doc template from a spec | `llm-write -r <ref> -s "<spec>" -o <path>` — then review and edit; never trust blind |
| Long transcript needs to become doc updates | `llm-extract <transcript.jsonl> --sections summary,decisions,todos` |

## Never delegate

- Architectural or design decisions
- Debugging — cheap models miss subtle bugs
- Anything touching auth, payments, PII, deletion, or production data
- Final commits and PR descriptions

If a delegated answer looks wrong or thin, re-read the sources yourself rather than
trusting the worker. Worker output is untrusted by default: the worker drafts, the
premium model reviews and makes the edits.

## Cost reference

Asking a cheap worker to summarize a ~12k-token doc runs ~125× cheaper than the same
read on a frontier model, at quality that's fine for "summarize / find facts" — which
is why the >400-line / 3-file thresholds pay for themselves almost immediately.

## Common mistakes

- Delegating a *judgment* question because it happens to involve big files — split it:
  `llm-ask` extracts the facts, the premium model judges.
- Passing files containing real credentials — redact first; workers don't get secrets.
- Treating `llm-write` output as done — it ships boilerplate, you ship correctness.
