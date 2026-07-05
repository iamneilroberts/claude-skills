"""llm-write: generate boilerplate (tests, configs, docs) from a spec.

Usage:
    llm-write -r src/foo.py -s "Pytest tests for foo. Cover happy path + 2 edge cases." -o tests/test_foo.py

The cheap model writes the file; Claude reviews and edits surgically.
Output is written verbatim — no markdown fences. The system prompt enforces this.
"""

from __future__ import annotations

import sys
from pathlib import Path

import click

from ..client import chat
from ..config import load_config


SYSTEM_PROMPT = (
    "You generate complete, production-quality file contents on demand. "
    "Follow the user's spec exactly. Use the reference files only as context for style and naming. "
    "Output ONLY the raw file contents — no markdown code fences, no preamble, no commentary. "
    "If the file is Python, do not wrap in ```python. Just the file."
)


@click.command(context_settings={"help_option_names": ["-h", "--help"]})
@click.option("--reference", "-r", multiple=True, type=click.Path(exists=True, dir_okay=False, path_type=Path),
              help="Reference file(s) for style/context. Repeat -r for multiple.")
@click.option("--spec", "-s", required=True, help="Plain-English description of what to generate.")
@click.option("--output", "-o", required=True, type=click.Path(path_type=Path),
              help="Output file path. Will be created/overwritten.")
@click.option("--provider", default=None, help="Override routed provider.")
@click.option("--model", default=None, help="Override model name.")
@click.option("--max-tokens", type=int, default=16384, show_default=True,
              help="Be generous — 'thinking' models eat tokens before emitting.")
@click.option("--temperature", type=float, default=0.2, show_default=True)
@click.option("--task", default="write", show_default=True, help="Routing key in config.")
@click.option("--stdout", is_flag=True, help="Print to stdout instead of writing the file.")
@click.option("--force", is_flag=True, help="Overwrite output without confirmation if it exists.")
def main(
    reference: tuple[Path, ...],
    spec: str,
    output: Path,
    provider: str | None,
    model: str | None,
    max_tokens: int,
    temperature: float,
    task: str,
    stdout: bool,
    force: bool,
) -> None:
    if not stdout and output.exists() and not force:
        click.echo(f"{output} exists. Pass --force to overwrite or --stdout to preview.", err=True)
        sys.exit(2)

    ref_blocks: list[str] = []
    for path in reference:
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            click.echo(f"Skipping non-UTF8 reference: {path}", err=True)
            continue
        ref_blocks.append(f"=== REFERENCE: {path} ===\n{text}\n")
    ref_text = "\n".join(ref_blocks) if ref_blocks else "(no reference files supplied)"

    config = load_config()
    provider_cfg, resolved_model = config.resolve(task, provider, model)

    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {
            "role": "user",
            "content": (
                f"{ref_text}\n"
                f"=== SPEC ===\n{spec}\n\n"
                f"=== TARGET PATH ===\n{output}\n\n"
                f"Emit the complete file contents now."
            ),
        },
    ]

    content = chat(
        provider_cfg,
        resolved_model,
        messages,
        max_tokens=max_tokens,
        temperature=temperature,
    )

    content = _strip_fences(content)

    if stdout:
        click.echo(content)
        return

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(content, encoding="utf-8")
    click.echo(f"Wrote {output} ({len(content)} chars) using {provider_cfg.base_url} / {resolved_model}", err=True)


def _strip_fences(text: str) -> str:
    """Belt-and-suspenders: strip a leading/trailing ```lang fence if a model adds one despite the prompt."""
    stripped = text.strip()
    if stripped.startswith("```"):
        first_newline = stripped.find("\n")
        if first_newline != -1:
            stripped = stripped[first_newline + 1 :]
        if stripped.endswith("```"):
            stripped = stripped[: -3].rstrip()
    return stripped + ("\n" if not stripped.endswith("\n") else "")


if __name__ == "__main__":
    main()
