#!/usr/bin/env python3
"""comment-refactor idempotency marker.

Each file that has been comment-refactored carries a top-of-file control marker:

    @comment-refactor:v1:<16-hex>

where <16-hex> is sha256(file body WITH the marker line removed)[:16]. On a later
scan the hash is recomputed the same way; if it matches, the file is unchanged
since its last refactor and is SKIPPED. Any real edit (code or comments) changes
the body hash, so the file is reprocessed. The marker line itself is excluded from
the hash so re-stamping is stable.

Subcommands:
  hash  <file>   print the current body hash (marker line excluded)
  check <file>   exit 0 = up-to-date (SKIP); exit 10 = needs processing
  stamp <file>   (re)write the marker at the top with the current body hash

The marker is written in the file's own comment syntax so it stays valid code.
"""
import hashlib
import re
import sys
import os

MARKER_RE = re.compile(r"@comment-refactor:v1:([0-9a-f]{16})")

# extension -> (line_prefix) OR (block_open, block_close)
LINE = {
    ".js": "//", ".jsx": "//", ".ts": "//", ".tsx": "//", ".mjs": "//", ".cjs": "//",
    ".c": "//", ".h": "//", ".cc": "//", ".cpp": "//", ".hpp": "//", ".java": "//",
    ".go": "//", ".rs": "//", ".swift": "//", ".kt": "//", ".kts": "//", ".scala": "//",
    ".php": "//", ".cs": "//", ".dart": "//", ".proto": "//", ".zig": "//",
    ".py": "#", ".rb": "#", ".sh": "#", ".bash": "#", ".zsh": "#", ".yaml": "#",
    ".yml": "#", ".toml": "#", ".r": "#", ".pl": "#", ".pm": "#", ".tf": "#",
    ".sql": "--", ".lua": "--", ".hs": "--", ".elm": "--", ".ex": "#", ".exs": "#",
}
BLOCK = {
    ".css": ("/*", "*/"), ".scss": ("/*", "*/"), ".less": ("/*", "*/"),
    ".html": ("<!--", "-->"), ".htm": ("<!--", "-->"), ".xml": ("<!--", "-->"),
    ".vue": ("<!--", "-->"), ".svelte": ("<!--", "-->"), ".md": ("<!--", "-->"),
}


def comment_for(path, hexhash):
    ext = os.path.splitext(path)[1].lower()
    body = f"@comment-refactor:v1:{hexhash}"
    if ext in LINE:
        return f"{LINE[ext]} {body}"
    if ext in BLOCK:
        o, c = BLOCK[ext]
        return f"{o} {body} {c}"
    return None  # unsupported language → caller should not stamp


def read(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def strip_marker(text):
    """Remove the single marker line, returning (body_without_marker, existing_hash|None)."""
    m = MARKER_RE.search(text)
    if not m:
        return text, None
    existing = m.group(1)
    # drop the whole physical line the marker sits on
    lines = text.split("\n")
    kept = [ln for ln in lines if not MARKER_RE.search(ln)]
    return "\n".join(kept), existing


def body_hash(text):
    body, _ = strip_marker(text)
    return hashlib.sha256(body.encode("utf-8")).hexdigest()[:16]


def cmd_hash(path):
    print(body_hash(read(path)))
    return 0


def cmd_check(path):
    text = read(path)
    _, existing = strip_marker(text)
    if existing is not None and existing == body_hash(text):
        return 0  # up-to-date → skip
    return 10  # needs processing


def cmd_stamp(path):
    text = read(path)
    body, _ = strip_marker(text)              # body without any old marker
    h = hashlib.sha256(body.encode("utf-8")).hexdigest()[:16]
    marker = comment_for(path, h)
    if marker is None:
        print(f"unsupported extension, not stamped: {path}", file=sys.stderr)
        return 2
    lines = body.split("\n")
    # keep a shebang (and an optional encoding line) at the very top
    insert = 0
    if lines and lines[0].startswith("#!"):
        insert = 1
    lines.insert(insert, marker)
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(h)
    return 0


def main(argv):
    if len(argv) != 3 or argv[1] not in ("hash", "check", "stamp"):
        print(__doc__)
        return 2
    cmd, path = argv[1], argv[2]
    return {"hash": cmd_hash, "check": cmd_check, "stamp": cmd_stamp}[cmd](path)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
