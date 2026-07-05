"""llm-ask: read files and answer a question with a cheap model.

Usage:
    llm-ask path/a.py path/b.py -q "Summarize what these modules do."
    llm-ask src/**/*.py -q "Where is auth handled?" --provider deepseek

Files are placed before the question to maximize prefix-cache hits when the
same corpus is queried multiple times.
"""

from __future__ import annotations

import sys
from pathlib import Path

import click

from ..client import chat
from ..config import load_config


SYSTEM_PROMPT = (
    "You read code and prose carefully. Answer the user's question using only "
    "the supplied files. Be concise and concrete: name files, functions, and "
    "line ranges where relevant. If the answer isn't in the files, say so."
)


@click.command(context_settings={"help_option_names": ["-h", "--help"]})
@click.argument("files", nargs=-1, type=click.Path(exists=True, dir_okay=False, path_type=Path))
@click.option("--question", "-q", required=True, help="The question to ask about the files.")
@click.option("--provider", default=None, help="Override routed provider (kimi, deepseek, openrouter, ollama, ...).")
@click.option("--model", default=None, help="Override model name for the chosen provider.")
@click.option("--max-tokens", type=int, default=8192, show_default=True)
@click.option("--temperature", type=float, default=0.2, show_default=True)
@click.option("--task", default="ask", show_default=True, help="Routing key in config.")
def main(
    files: tuple[Path, ...],
    question: str,
    provider: str | None,
    model: str | None,
    max_tokens: int,
    temperature: float,
    task: str,
) -> None:
    if not files:
        click.echo("No files given. Pass one or more file paths as arguments.", err=True)
        sys.exit(2)

    parts: list[str] = []
    for path in files:
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            click.echo(f"Skipping non-UTF8 file: {path}", err=True)
            continue
        parts.append(f"=== FILE: {path} ===\n{text}\n")

    if not parts:
        click.echo("No readable text files.", err=True)
        sys.exit(2)

    corpus = "\n".join(parts)

    config = load_config()
    provider_cfg, resolved_model = config.resolve(task, provider, model)

    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": f"{corpus}\nQuestion: {question}"},
    ]

    answer = chat(
        provider_cfg,
        resolved_model,
        messages,
        max_tokens=max_tokens,
        temperature=temperature,
    )
    click.echo(answer)


if __name__ == "__main__":
    main()
