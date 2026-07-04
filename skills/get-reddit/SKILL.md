---
name: get-reddit
description: Fetch a specific public Reddit post (title, body, and top comments) as clean markdown, by driving a real browser session (Playwright) — because Reddit 403s all non-browser fetches AND closed self-serve API access in Nov 2025. Use whenever you need the actual contents of a Reddit thread from a URL or post id — e.g. "fetch this Reddit post", "what does this thread say", "summarize this r/... discussion", or `/get-reddit <url>`.
---

# get-reddit

Fetch one public Reddit post + its top comments, rendered as markdown.

## Run it directly — no plan mode, no brainstorming

This skill is a single mechanical fetch, not a project. When it triggers (a `/get-reddit`
invocation or a pasted Reddit URL to read/summarize), do **NOT** enter plan mode, brainstorm,
or write a plan first — run the script immediately, then summarize. The "process skills come
first" rule doesn't apply: this skill *is* the process, and there are no design decisions to
make. If the session is already in plan mode when this triggers, tell the user the fetch needs
to execute a script and ask them to exit plan mode (Shift+Tab).

## When to use

- The user pastes a Reddit URL and wants its contents read/summarized.
- A research/eval task needs a specific thread that plain `WebFetch`/`curl` 403s on (the
  `/evaluate` and `/deep-research` skills hit exactly this wall — call this skill for the
  Reddit leg instead of giving up on the source).

## Why a browser, not curl or the API

Two independent walls (both verified 2026-06-30):

1. **Anti-bot:** Reddit returns a 403 anti-bot HTML page to *any* non-browser client —
   `.json`, `old.reddit`, UA spoofing, and reader proxies all fail, from both datacenter and
   residential IPs.
2. **API closed:** Reddit's **Responsible Builder Policy** (effective 2025-11-11) **disabled
   self-serve API-app creation**. The `prefs/apps` "create app" button is now zombie
   functionality — it flashes "creating app", silently fails, and shows the Responsible-Builder
   policy line. New apps require a pre-approval application (~2–4 wk, high solo-dev rejection),
   so the OAuth path is effectively closed.

The only robust path left is a **real browser session**. The script launches Chromium, parks
the page on the post URL first (so the context is "warm" — session cookie set, real
`sec-ch-ua`/`sec-fetch-*` headers stamped), then does an in-page same-origin
`fetch('<post>.json')`. The browser carries cookies + headers Node's fetch can't replicate, so
Reddit returns real JSON. (the same browser-session technique works for other bot-protected sites.) No
Reddit login or API key is needed.

## Setup

None on first use beyond Node — the launcher auto-installs Playwright + the Chromium binary the
first time it runs (one-time, ~1–2 min; the browser binary is shared at `~/.cache/ms-playwright`).
Requires `node` and `npm` on PATH.

## Usage

```bash
.claude/skills/get-reddit/get-reddit.sh <reddit-url-or-post-id> [comment_limit] | tee <scratchpad>/reddit-<post-id>.md
```

Always `tee` the output to a scratchpad file as shown — the save offer below reuses it, so a
save never refetches (Reddit rate-limits; see "Be gentle").

Accepts a full post URL, an `old.reddit.com` URL, a `redd.it/<id>` short link, or a bare
base-36 post id. `comment_limit` (default 25) caps top-level comments, sorted by score. Output
is markdown: title, subreddit/author/score line, permalink, body (or external link), then the
top comments.

Env knobs:
- `GET_REDDIT_HEADLESS=0` — show the browser window. Use **once** if a fetch gets challenged;
  solving the challenge persists in the profile so later headless runs work.
- `GET_REDDIT_PROFILE=<dir>` — override the persisted browser-profile dir (default `.profile/`
  beside the script; gitignored).

## After the summary: offer to save

After emitting the summary, ask the user (one short question, e.g. via AskUserQuestion) whether
to save the fetched thread as a markdown file. Propose a concrete default path derived from the
post: `docs/research/reddit/<yyyy-mm-dd>-r-<subreddit>-<title-slug>.md` (kebab-case the title,
truncate to ~6 words). If they accept, copy the tee'd scratchpad file there (prepend your
summary as a short intro section above the fetched content); if they pick another path, use
that; if they decline, do nothing. Never refetch to save.

## Notes / limits

- **Read-only**, top-level comments only (depth 1) — enough to "read the thread".
- **Be gentle:** run sequentially, not in parallel. On HTTP 429 the script exits 8; wait ~15s
  and retry. Don't loop it over many threads without backoff.
- If a fetch returns the anti-bot HTML instead of JSON, the script exits non-zero and hints to
  re-run once with `GET_REDDIT_HEADLESS=0` to warm/solve the session.
- The persisted profile (`.profile/`) and `node_modules/` are gitignored.
