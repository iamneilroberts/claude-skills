# llm-tools

CLI helpers that route bulk file-reading and boilerplate-writing from Claude Code
to a cheaper OpenAI-compatible model — Kimi, DeepSeek, OpenRouter, or Ollama on
your LAN. The pattern is from
[this Medium post](https://medium.com/@kunalbhardwaj598/i-was-burning-through-claude-codes-weekly-limit-in-3-days-here-s-how-i-fixed-it-0344c555abda),
generalized so the worker model is your choice.

The premise: Claude is great at reasoning and lousy at being economical with
context. When you'd otherwise have it read three large files just to answer one
question, hand the read to a cheap long-context model and let Claude consume the
short answer. Same trick for generating predictable boilerplate (tests, configs,
doc scaffolds) — Claude reviews and edits, but doesn't draft.

## What's in the box

Three CLIs:

- **`llm-ask <files...> -q "..."`** — bulk read. Files are placed before the
  question so prefix caching kicks in when you query the same corpus twice.
- **`llm-write -r ref.py -s "spec" -o out.py`** — generate a file from a spec
  plus optional reference files. Output is written verbatim; Claude reviews.
- **`llm-extract transcript.jsonl`** — compress a Claude Code session
  transcript into Decisions / Files / TODOs sections suitable for doc updates.

All three speak the OpenAI Chat Completions protocol, so the same code works
against Kimi, DeepSeek, OpenRouter, and Ollama (and any other provider that
implements `/v1/chat/completions`).

## Install

```bash
bash scripts/setup.sh
```

That installs the CLIs via `uv tool install -e .`, seeds
`~/.config/llm-tools/config.toml` from the example (without clobbering an
existing one), and prints the `export` lines you'll want in your shell rc.
Re-run any time to upgrade after a `git pull`.

## Configure

`scripts/setup.sh` already wrote `~/.config/llm-tools/config.toml`. Edit it:

```bash
$EDITOR ~/.config/llm-tools/config.toml
```

Set the API keys you want to use:

```bash
# in ~/.bashrc or ~/.zshrc
export KIMI_API_KEY=sk-...
export DEEPSEEK_API_KEY=sk-...
export OPENROUTER_API_KEY=sk-or-...
```

Ollama needs no key — just point `base_url` at the host running `ollama serve`.
For a LAN box, make sure Ollama is started with
`OLLAMA_HOST=0.0.0.0:11434 ollama serve` so it accepts non-loopback connections.

The config has two halves:

```toml
[providers.kimi]
base_url = "https://api.moonshot.ai/v1"
api_key_env = "KIMI_API_KEY"
default_model = "kimi-k2-turbo-preview"

[providers.ollama]
base_url = "http://192.168.1.100:11434/v1"
default_model = "qwen2.5:32b"

[routing.ask]      # `llm-ask` defaults to this
provider = "kimi"

[routing.write]    # `llm-write` defaults to this
provider = "deepseek"

[routing.extract]  # `llm-extract` defaults to this
provider = "ollama"
```

Override either side per call:

```bash
llm-ask --provider ollama --model qwen2.5:14b src/foo.py -q "summarize"
```

Config search order: `./.llm-tools.toml`, then `$LLM_TOOLS_CONFIG`, then
`~/.config/llm-tools/config.toml`. The first one wins. Drop a `.llm-tools.toml`
in a project root to override globally for that project (e.g. force Ollama in a
repo with sensitive code).

## Usage

```bash
# Read and summarize without burning Claude's context
llm-ask src/auth.py src/session.py -q "How does session expiry work?"

# Generate boilerplate Claude will review
llm-write -r src/foo.py \
          -s "Pytest tests covering happy path + 2 edge cases for foo.parse()" \
          -o tests/test_foo.py

# Compress a session transcript before feeding it back into Claude
llm-extract ~/.claude/projects/some-project/<session>.jsonl \
            --sections summary,decisions,todos
```

## Wire it into Claude Code

Drop a block like this into your project's `CLAUDE.md` so Claude knows when
to delegate (the routing rules are what actually save tokens — the CLI is just
the execution layer):

```markdown
## Cheap-worker delegation

Three CLIs are on PATH that route to a cheaper OpenAI-compatible model. Use
them when the task is bulk I/O or predictable generation, not when reasoning
or correctness is on the line.

- `llm-ask <files...> -q "..."` — use when you'd otherwise read 3+ files OR
  any single file >400 lines. Returns a short answer; you read that, not the
  files.
- `llm-write -r <ref> -s "<spec>" -o <path>` — use for tests, fixtures,
  config scaffolds, doc templates. Review and edit the result; do not blindly
  trust it.
- `llm-extract <transcript.jsonl>` — use before updating docs from a long
  session.

Keep on Claude (do NOT delegate):
- Architectural decisions
- Debugging — the cheap model misses subtle bugs
- Anything touching auth, payments, PII, deletion, or production data
- Final commits and PR descriptions

If a delegated answer looks wrong or thin, re-read the source files yourself
rather than trusting the worker.
```

## Why OpenAI-compatible only

Every provider here exposes `/v1/chat/completions`, so we don't ship adapters
for native Anthropic / Gemini / Bedrock formats. If you want to add one, swap
the `openai.OpenAI` call in `client.py` for the relevant SDK and add a
`provider_kind` discriminator in config. It's roughly a one-day change.

## Hard rules

- Worker output is **untrusted by default**. Claude reads the result, not the
  files; but Claude makes the edits.
- Workers don't see secrets. If a file you'd hand to `llm-ask` contains real
  credentials, redact first.
- This pipeline does not authenticate to the worker on Claude's behalf — your
  shell has the env vars, so anything that runs on your shell can spend your
  worker budget.
