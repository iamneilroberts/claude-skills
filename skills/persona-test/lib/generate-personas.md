# Instruction: Generate domain-specific personas

You are a subagent generating additional personas for a persona-test run, tailored to the
app under test. You are given:

- **`context`** — a short description of the app's domain, its core user task(s), and its
  terminology, produced by the adapter's `context` hook.
- **`M`** — how many persona files to produce.
- The **starter persona library** at `skills/persona-test/personas/*.md`, for shape and tone
  reference (`budget-traveler.md`, `power-user.md`, `frustrated-first-timer.md`,
  `cautious-skeptic.md`, `accessibility-first.md`).

## What to do

1. Read `context` to understand what kind of user would plausibly use this app, and what
   distinct ways they'd approach it (different goals, different risk tolerance, different
   familiarity with the domain, different interaction channels).
2. Produce exactly `M` personas that are **distinct from each other** — do not generate near
   duplicates of the starter library or of one another. Prefer covering different failure
   modes (impatient vs. cautious, expert vs. novice, terse vs. verbose) over covering the
   same trait twice.
3. Each persona must follow the **exact same shape** as the starter library:

   ```markdown
   # Persona: <Name>
   **Goal:** <what they're trying to accomplish, and what makes them give up>
   **Temperament:** <a few adjectives describing how they engage>
   **Constraints:** <what they will and won't do or accept>
   **Interaction tendencies:** <concrete, observable behaviors — phrasing, pacing, quit conditions>
   ```

   Four fields, in that order, each a single paragraph (not a nested list). Keep each field
   to one or two sentences — these are inputs a driver subagent role-plays from, not
   biographies.

## What NOT to do

- **Never name the app, its vendor, or any of its brand names, screen names, or feature
  names** inside a persona. A persona describes a *type of user* — their goals, temperament,
  constraints, and interaction tendencies — never the app's own vocabulary, UI, or menu
  structure. If `context` mentions app-specific terms, translate them into a generic
  description of the underlying user need instead of repeating the term verbatim.
- **Never include anything that looks like a credential, API key, internal URL, account
  ID, or other secret**, even if `context` happens to contain one. If `context` leaks a
  secret, ignore it — it has no place in a persona description.
- Do not invent a persona whose goal or constraints require information you don't actually
  have from `context` (e.g. don't assume a pricing model, a specific policy, or a specific
  limit that wasn't stated).

## Output contract

Emit your `M` personas as a sequence of **file blocks**, one per persona, in this exact
form — nothing before the first block, nothing between blocks except a blank line, nothing
after the last block:

```
### FILE: personas/generated/<slug>.md
# Persona: <Name>
**Goal:** ...
**Temperament:** ...
**Constraints:** ...
**Interaction tendencies:** ...
```

- `<slug>` is the persona name, lowercased, spaces replaced with `-` (e.g. `Anxious
  Delegator` → `anxious-delegator`).
- Produce exactly `M` blocks — not more, not fewer.
- Do not wrap the blocks in an outer JSON object, a numbered list, or commentary. The
  `### FILE: <path>` line is a machine-parsed delimiter — keep its format exact.
