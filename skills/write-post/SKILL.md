---
name: write-post
description: |
  Turn a rough brief into a blog deep-dive draft. Takes a topic or brief, gathers the
  relevant sources, runs one short focused interview to pin down the angle and the
  claims, then writes a draft to docs/posts/<date>-<slug>.md. The default output is a
  rich outline — a dense, factual skeleton meant to be rewritten in your own voice —
  not finished prose. Pass `--draft` for full prose, `--outline` to force the outline.
  This is the no-BS technical counterpart to `/brag` (which builds a sales/hype
  showcase page); reach for write-post when the goal is an accurate deep dive.
  Triggers on `/write-post <topic>`, "write a blog post about", "draft a deep dive on",
  "help me write a post on".
user_invocable: true
---

# write-post — brief → interview → rich-outline draft

You rewrite everything into your own voice, so the job is NOT to produce polished prose.
It is to produce a **dense, well-structured, factually-grounded skeleton** you can rewrite
fast: the right sections, the real claims with evidence under each, the links and code
refs, and explicit markers where facts still need checking.

## Workflow

### 1. Read the brief
Parse what you were given as args. If it's one line ("deep dive on the latest MCP Apps
features"), that's the seed — the interview fills the rest. Don't assume; ask.

### 2. Gather sources BEFORE interviewing (so questions are specific, not generic)
Spend a little effort grounding yourself so the interview is informed:
- Relevant code/docs in this repo (grep, read the specific files).
- Any local documentation mirrors you keep (e.g. a docs mirror under `~/.claude/`), plus
  the project's own docs, for the topic at hand.
- Any notes/memory you keep about prior decisions and what has already shipped.
- Use a subagent for heavy reading; keep only the facts in this thread.
Bring 2–4 concrete things you learned into the interview ("the release notes list X, Y, Z
as new — which of these is the post about?"). Cross-check claims against the actual
code/spec; don't relay lore.

### 3. Interview (short, focused, conversational)
Ask in prose, not a wall of separate question widgets — one tight round, grouped, with a
recommended default on each so the answer can be fast ("your call" is a valid answer).
Cover:
- **Audience** — who reads this?
- **Thesis / angle** — the one sentence the post argues. If it's fuzzy, propose 2–3.
- **The hook** — what's new / why now / why anyone should care.
- **Must-include claims + evidence** — the specific things to say, and what backs each (a
  shipped feature, a number, a code ref, a screenshot).
- **Structure** — narrative, how-to, announcement, or teardown.
- **Length** — short (~600w), medium (~1200w), or long deep-dive (~2500w+).
- **Voice references** — anything to imitate/avoid; default applies the anti-AI-speak
  rules below.
- **CTA + destination** — where it gets published, what the reader should do next.
Skip any question the brief already answers. Stop interviewing once you can write a
skeleton that won't have to be re-scoped.

### 4. Write the draft
Default = **rich outline**. Write to `docs/posts/<YYYY-MM-DD>-<slug>.md`. Shape:
- Title + 2–3 alternative titles/subtitles.
- One-line thesis, stated plainly.
- Intended audience + length target (one line each, so the rewrite stays on-target).
- Section by section: `## heading` then dense bullets carrying the **actual substance** —
  the claims, numbers, examples, links, code refs (`file:line`), and a noted transition to
  the next section. Not paragraphs.
- `[PULLQUOTE: …]` where a quotable line should go.
- `[VERIFY: …]` for any claim not yet checked against code/spec; `[NEEDS: screenshot /
  number / link]` for missing assets. Never silently assert an unverified fact.
- A closing section with the CTA.
- A short "Sources" list at the bottom (files/URLs the claims came from).

`--draft` → expand the outline into full prose (still applying the rules below).
`--outline` → force outline even if `--draft` is a habit.

### 5. Hand off
Print the path, a one-paragraph summary of the angle, and the list of `[VERIFY]` /
`[NEEDS]` markers so it's clear exactly what's load-bearing-but-unconfirmed. Don't commit
unless asked.

## Writing rules (apply to every word, outline or draft)

- No "it's not X, it's Y" / "not just X but Y" em-dash antithesis constructions.
- No cute throat-clearing ("Let's dive in", "Here's the thing", "In a world where…").
- No inflated transitions ("Moreover", "Furthermore", "Ultimately", "the ever-evolving
  landscape"). Plain connectors or none.
- Sparing em-dashes. Active voice. Concrete over abstract. Short declarative sentences.
- Don't hype. State what's true and let it stand — you add the personality on the rewrite.
- Outline mode especially: terse and factual. Bullets, not paragraphs.

## Notes
- `docs/posts/` is the draft home; create it if missing. Slug = kebab of the title.
- This skill produces a draft to rewrite — it is not a publish step.
