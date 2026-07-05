---
name: my-voice
description: Use when writing or rewriting text that must sound like a specific real person wrote it (their Reddit post, email, blog, bio, social copy) — the user offers a writing sample, asks to "put this in my voice", "make it sound like me", "de-slop this", or complains that a draft reads like AI. Distills a reusable voice profile from the sample and rewrites against it.
---

# My Voice

## Overview

Rewriting "in someone's voice" fails two ways at once: the agent applies generic
anti-AI de-slopping that makes text clean but anonymous, and it leaves its OWN tells in
(em-dashes, "not just X, it's Y", rule-of-three). The fix is to stop working from vibes:
**distill a concrete, checkable profile from a real sample, then verify the output
against it mechanically.** A voice is a set of observable habits, not a mood.

## Method

### 1. Get a real sample
Ask for one if none given. Rank by fidelity:
1. **Unedited chat/DM/message history** (best — natural, unperformed)
2. Emails, comments, forum/Reddit posts
3. Published blog/marketing (worst — already edited, may not be their own hand)

Aim for **~400+ words across 2–3 pieces**. Prefer the genre being written (a Reddit
voice ≠ a bio voice). If the only sample is one polished paragraph, say so — the profile
will be thin.

### 2. Distill the profile (write it down, don't hold it in your head)
Fill every dimension from the sample with a specific observation + a quoted example.
Guessing = leave it "unknown", never invent:

- **Sentence length & rhythm** — short/medium/long; uniform or varied? run-ons?
- **Punctuation habits** — em-dashes? semicolons? parentheticals? ellipses? Note what
  they use to join clauses instead (comma splices? periods? "So"/"Then"?).
- **POV & address** — first person? second-person "you"? name the reader?
- **Openers & connectives** — how sentences start ("So", "The problem was", "Look,").
- **Register** — dry / wry / warm / blunt / profane / formal. Hedged or flat-assertive?
- **Concreteness** — numbers-first? named examples? or abstract?
- **Honesty tics** — do they admit dead ends, uncertainty, self-deprecation?
- **Signature quirks** — lowercase, specific words, a recurring move.
- **Never-does** — the strongest signal. What's *absent* from the sample that AI defaults
  to? (usually: em-dashes, antithesis, exclamation points, marketing words.)

### 3. Interview for stated preferences (the sample can't tell you these)
A sample shows what the person *did*, not what they *want* or consciously avoid. Ask a
short round (one question at a time, skip any the sample already answers clearly):

- **Aspirations vs habits** — "Anything in these samples you'd change? Words or moves
  you fall into but don't like?" (Habits you'd otherwise faithfully reproduce as tells.)
- **Hard bans** — "Words, phrases, or punctuation you refuse to use?" (People often have
  a personal blocklist beyond the universal AI tells — e.g. never "utilize", never
  emoji, never exclamation points.)
- **Register range** — "Same voice everywhere, or more formal for X and looser for Y?"
  Capture per-context variants if so.
- **Contractions / formality / profanity** — confirm the defaults, since these swing by
  audience and the sample may be one point on that range.
- **The tell test** — "What makes writing instantly read as AI-generated to you?" Their
  answer goes straight into the kill-list; it's the most personal de-slop signal there is.

Record stated preferences in the profile and mark them as **stated** (vs **observed**
from the sample). When they conflict, stated preference wins — it's the conscious choice.

### 4. Build the de-slop kill-list
Two layers:
- **Universal AI tells** (strip always): em-dash-as-connector, "not just X, it's Y" /
  "it's not A, it's B" antithesis, rule-of-three cadence, marketing register
  (seamless, powerful, robust, leverage, unlock, delve, elevate, game-changing,
  transformative, thrilled, dive in, testament to, "in today's ... world"),
  exclamation points, "Whether you're X or Y", a summarizing "In conclusion/Ultimately"
  outro, emoji-as-decoration, every-paragraph-perfectly-balanced.
- **Person-specific** — anything the sample *proves* they never do (e.g. "sample has 0
  em-dashes across 400 words → em-dashes are banned for this voice specifically"), plus
  the stated bans from the interview.

### 5. Persist the profile
Save it to `.claude/voice/<name>.md` (or the user's memory dir) so future rewrites reuse
it instead of re-deriving. Keep the **observed** / **stated** tags. Reuse and refine it
when more samples or corrections appear.

### 6. Rewrite, then run the checklist
Draft in the voice, then verify against the profile before returning. This step is the
skill — an unverified rewrite is where the tells survive:

- [ ] Em-dash count matches the sample's rate (usually 0). Grep the output.
- [ ] Zero "not X, it's Y" antithesis constructions.
- [ ] No word from the marketing kill-list or the person's stated bans.
- [ ] Sentence openers and connectives match the profile's list.
- [ ] Sentence-length distribution roughly matches the sample.
- [ ] Honesty tics present if the person uses them (kept the dead ends, the "here's what's broken").
- [ ] Read one paragraph aloud against a sample paragraph — same person?

If any box fails, fix that specific thing and re-check. Do not return on first draft.

## Common mistakes

- **Generic-casual ≠ their voice.** "Made it conversational" is not the job; matching
  *their specific* habits is. A dry numbers-first writer rendered as a breezy blogger
  fails even with every AI word gone.
- **Injecting your own tells while removing theirs.** The em-dash and the antithesis are
  the two that survive most often — they feel like "good writing", so agents add them
  back. The checklist exists because self-assessment misses them.
- **Over-applying de-slop.** If the person genuinely uses semicolons or the occasional
  em-dash, keep them at their rate. De-slopping means matching the human, not stripping
  to a lowest-common-denominator plainness.
- **Inventing quirks from a thin sample.** One paragraph can't tell you their opener
  habits. Mark unknowns; don't fabricate a persona. The interview (step 3) is how you
  fill gaps the sample leaves — ask, don't guess.

## Profile template

```markdown
# Voice profile — <name>
Distilled from: <sources>. Tags: observed = seen in samples; stated = told directly.

## Dimensions
- Sentence length & rhythm (observed): ...
- Punctuation (observed): ...
- POV & address (observed): ...
- Openers & connectives (observed): ...
- Register (observed): ...
- Concreteness (observed): ...
- Honesty tics (observed): ...
- Signature move (observed): ...

## Kill-list (never, for this voice)
- Person-specific (observed absent): ...
- Stated bans (interview): ...
- Universal AI tells: ...

## Register range (stated): ...
## Open (ask next time): ...
```
