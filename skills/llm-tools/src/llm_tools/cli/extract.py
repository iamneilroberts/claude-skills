"""llm-extract: compress a Claude Code session transcript into structured notes.

Reads a transcript JSONL file (or stdin) and asks the cheap model to emit
sections suitable for documentation updates: decisions, files-touched, and
TODOs. Claude can then take that small summary and decide what doc edits to make,
instead of re-reading the whole transcript.

Usage:
    llm-extract path/to/session.jsonl
    cat session.jsonl | llm-extract -
    llm-extract session.jsonl --sections decisions,todos --provider deepseek
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import click

from ..client import chat
from ..config import load_config


SYSTEM_PROMPT = (
    "You compress AI-coding session transcripts into terse, factual notes. "
    "Output exactly the requested sections as Markdown, no extras. "
    "Quote file paths in backticks. No preamble, no closing remark."
)


SECTION_SPECS = {
    "decisions": "## Decisions\nBullet list of architectural or design decisions made. Each bullet: WHAT was decided, WHY, alternatives rejected. Skip routine implementation choices.",
    "files": "## Files touched\nBullet list. Each bullet: `path` — created/modified/deleted — one-sentence purpose.",
    "todos": "## TODOs / open questions\nBullet list of things explicitly left undone or marked as needing follow-up. Quote the user verbatim where useful.",
    "summary": "## Summary\nThree to five sentences describing what this session accomplished.",
}


def _flatten_transcript(raw: str) -> str:
    """Pull human-readable text out of Claude Code JSONL transcript lines.

    Each line is a JSON object; the shape is unstable across versions, so we
    walk anything that looks like a `text` field. Errors are skipped; we'd
    rather miss a line than choke on the whole transcript.
    """
    chunks: list[str] = []
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            chunks.append(line)
            continue
        chunks.extend(_walk_for_text(obj))
    return "\n".join(c for c in chunks if c.strip())


def _walk_for_text(node: object) -> list[str]:
    out: list[str] = []
    if isinstance(node, dict):
        role = node.get("role") if isinstance(node.get("role"), str) else None
        if "text" in node and isinstance(node["text"], str):
            prefix = f"[{role}] " if role else ""
            out.append(f"{prefix}{node['text']}")
        for value in node.values():
            out.extend(_walk_for_text(value))
    elif isinstance(node, list):
        for item in node:
            out.extend(_walk_for_text(item))
    return out


@click.command(context_settings={"help_option_names": ["-h", "--help"]})
@click.argument("transcript", type=click.Path(allow_dash=True, dir_okay=False, path_type=Path))
@click.option("--sections", default="summary,decisions,files,todos", show_default=True,
              help=f"Comma-separated subset of: {sorted(SECTION_SPECS)}")
@click.option("--provider", default=None)
@click.option("--model", default=None)
@click.option("--max-tokens", type=int, default=4096, show_default=True)
@click.option("--temperature", type=float, default=0.1, show_default=True)
@click.option("--task", default="extract", show_default=True)
def main(
    transcript: Path,
    sections: str,
    provider: str | None,
    model: str | None,
    max_tokens: int,
    temperature: float,
    task: str,
) -> None:
    if str(transcript) == "-":
        raw = sys.stdin.read()
    else:
        raw = transcript.read_text(encoding="utf-8", errors="replace")

    body = _flatten_transcript(raw)
    if not body.strip():
        click.echo("Transcript yielded no readable text.", err=True)
        sys.exit(2)

    requested = [s.strip() for s in sections.split(",") if s.strip()]
    unknown = [s for s in requested if s not in SECTION_SPECS]
    if unknown:
        click.echo(f"Unknown sections: {unknown}. Valid: {sorted(SECTION_SPECS)}", err=True)
        sys.exit(2)
    section_block = "\n\n".join(SECTION_SPECS[s] for s in requested)

    config = load_config()
    provider_cfg, resolved_model = config.resolve(task, provider, model)

    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {
            "role": "user",
            "content": (
                f"=== TRANSCRIPT ===\n{body}\n\n"
                f"=== EMIT THESE SECTIONS (in this order) ===\n{section_block}"
            ),
        },
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
