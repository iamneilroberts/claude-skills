#!/usr/bin/env bash
# Idempotent setup for llm-tools.
#   1. install/upgrade the CLIs via `uv tool install -e .`
#   2. seed ~/.config/llm-tools/config.toml from config.example.toml (no clobber)
#   3. print the export lines for the API keys you need to set in your shell rc
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/llm-tools"
CONFIG_FILE="$CONFIG_DIR/config.toml"
EXAMPLE_FILE="$REPO_DIR/config.example.toml"

if ! command -v uv >/dev/null 2>&1; then
  echo "error: uv is not on PATH. Install it from https://github.com/astral-sh/uv first." >&2
  exit 1
fi

echo "==> Installing llm-tools from $REPO_DIR"
( cd "$REPO_DIR" && uv tool install -e . --reinstall )

mkdir -p "$CONFIG_DIR"
if [[ -e "$CONFIG_FILE" ]]; then
  echo "==> Config already present at $CONFIG_FILE — leaving it alone."
else
  cp "$EXAMPLE_FILE" "$CONFIG_FILE"
  echo "==> Wrote $CONFIG_FILE (copied from config.example.toml)."
fi

echo
echo "==> Verifying CLIs are on PATH"
for bin in llm-ask llm-write llm-extract; do
  if command -v "$bin" >/dev/null 2>&1; then
    printf '    %-12s %s\n' "$bin" "$(command -v "$bin")"
  else
    printf '    %-12s NOT FOUND — make sure ~/.local/bin (or `uv tool dir`/bin) is on PATH\n' "$bin"
  fi
done

cat <<'EOF'

==> Next: edit your config and set the API keys you want to use.

    $EDITOR ~/.config/llm-tools/config.toml

Add to ~/.bashrc or ~/.zshrc (only the providers you actually plan to use):

    export KIMI_API_KEY=sk-...
    export DEEPSEEK_API_KEY=sk-...
    export OPENROUTER_API_KEY=sk-or-...

Ollama needs no key. If your Ollama box isn't on localhost, edit the
[providers.ollama] base_url in the config above.

Smoke test once a key is set:

    echo "hello world" > /tmp/smoke.txt
    llm-ask /tmp/smoke.txt -q "what does this say?"
EOF
