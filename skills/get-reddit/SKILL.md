---
name: get-reddit
description: Fetch a specific public Reddit post (title, body, and top comments) as clean markdown, by driving a real browser session (Playwright) — because Reddit 403s all non-browser fetches AND closed self-serve API access in Nov 2025. Use whenever you need the actual contents of a Reddit thread from a URL or post id — e.g. "fetch this Reddit post", "what does this thread say", "summarize this r/... discussion", or `/get-reddit <url>`. Runs in a forked Sonnet subagent that CANNOT see the conversation — always pass the Reddit URL/post id (and optional comment limit) as the skill argument.
context: fork
agent: general-purpose
model: sonnet
---

# get-reddit (forked fetcher)

You are a subagent. Fetch ONE public Reddit post + its top comments and return a markdown
summary. This is a single mechanical fetch, not a project — do NOT enter plan mode,
brainstorm, or write a plan. Run the script, then summarize.

**Target:** $ARGUMENTS

That should be a full post URL, an `old.reddit.com` URL, a `redd.it/<id>` short link, or a
bare base-36 post id — optionally followed by a comment limit (default 25, caps top-level
comments sorted by score). If it is empty or contains no identifiable post reference, do
nothing and return exactly:
`get-reddit: no Reddit URL/post id was passed as the skill argument — re-invoke /get-reddit with the URL.`

## Run it

```bash
.claude/skills/get-reddit/get-reddit.sh <reddit-url-or-post-id> [comment_limit] | tee /tmp/get-reddit-<post-id>.md
```

The script lives in this skill's directory (project install: `.claude/skills/get-reddit/`;
user install: `~/.claude/skills/get-reddit/`). Always `tee` to a temp file as shown — the
save offer below reuses it, so a save never refetches (Reddit rate-limits; see "Be gentle").

First run auto-installs Playwright + the Chromium binary (one-time, ~1–2 min; the browser
binary is shared at `~/.cache/ms-playwright`). Requires `node` and `npm` on PATH.

Env knobs:
- `GET_REDDIT_HEADLESS=0` — show the browser window. Use **once** if a fetch gets challenged;
  solving the challenge persists in the profile so later headless runs work.
- `GET_REDDIT_PROFILE=<dir>` — override the persisted browser-profile dir (default `.profile/`
  beside the script; gitignored).

Failure handling:
- Exit 8 = HTTP 429 rate limit → wait ~15s, retry once. Don't loop over many threads.
- Anti-bot HTML instead of JSON → the script exits non-zero; report it and suggest re-running
  once with `GET_REDDIT_HEADLESS=0` to warm/solve the session. Don't thrash retries.

## Why a browser, not curl or the API (in case you must debug)

Two independent walls (both verified 2026-06-30):

1. **Anti-bot:** Reddit returns a 403 anti-bot HTML page to *any* non-browser client —
   `.json`, `old.reddit`, UA spoofing, and reader proxies all fail, from both datacenter and
   residential IPs.
2. **API closed:** Reddit's **Responsible Builder Policy** (effective 2025-11-11) **disabled
   self-serve API-app creation**, so the OAuth path is effectively closed (pre-approval takes
   ~2–4 wk with high solo-dev rejection).

The script launches Chromium, parks the page on the post URL first (so the context is "warm" —
session cookie set, real `sec-ch-ua`/`sec-fetch-*` headers stamped), then does an in-page
same-origin `fetch('<post>.json')`. (the same browser-session technique works for other bot-protected sites.) No Reddit login or API key is needed. Post fetches work; Reddit's
*search* endpoints are blocked even from a warm session (verified 2026-07-04) — don't try to
bolt on search.

## What to return (your final message)

Your final text is the deliverable relayed to the main conversation. Include, in order:

1. **Summary** — title, `r/<sub> · u/<author> · score · N comments`, permalink; the post
   body's key points; the top comments worth reading, grouped by theme (keep scores).
   Faithful and concise — don't pad, don't editorialize.
2. **Tee'd file** — the exact path of the raw fetched markdown (e.g. `/tmp/get-reddit-<id>.md`).
3. **Save offer** — final line, verbatim format, for the main assistant to relay to the user:
   `SAVE OFFER: raw thread at <tee-path>; offer to save to docs/research/reddit/<yyyy-mm-dd>-r-<subreddit>-<title-slug>.md (kebab-case title, ~6 words; prepend the summary as an intro; copy the tee'd file — never refetch).`

## Notes / limits

- **Read-only**, top-level comments only (depth 1) — enough to "read the thread".
- **Be gentle:** run sequentially, not in parallel.
- The persisted profile (`.profile/`) and `node_modules/` are gitignored.
