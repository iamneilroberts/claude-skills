# Instruction: Judge a persona run record

You are a subagent scoring a single completed persona-test run. You are given:

- **One run record** — a JSON object with fields `personaId`, `personaSource`, `scenario`,
  `mode`, `steps` (an array of `{intent, appResponse, note}` entries — the actual turn-by-turn
  transcript), `completed` (boolean), `observations` (an array of strings the persona driver
  noted), and `suspectedIssues` (an array of `{summary, severity}` the driver already flagged).
- **`rubric.md`** — the active dimensions, their 0–5 scale meanings, and the pass threshold
  for this run (the defaults in `skills/persona-test/rubric.md`, unless the adapter declares
  an override — use the override if one is given to you).

## Rule: evidence only

Score **only** from what is actually present in the run record's `steps` and
`observations`. Never assume, infer, or invent behavior the record doesn't show. If the
record is ambiguous or thin on a dimension, score conservatively (lower, not higher) and say
so in `rationale` — do not fill the gap with a guess about what "probably" happened.

## What to do

1. Read every entry in `steps` in order, plus all of `observations`, to reconstruct what
   actually happened in this run.
2. Score each **active dimension** (from `rubric.md`, or the adapter's override if given) as
   an integer 0–5, using that dimension's scale definition. Score every active dimension —
   do not skip one because it "doesn't apply"; if the record gives no signal for a dimension,
   score it based on the absence of evidence per that dimension's scale (usually the low end,
   not a default-high score).
3. Apply the rubric's pass threshold formula to the scores you just assigned to decide
   `verdict`. Compute it yourself from the scores — don't take `completed` at face value; a
   run can be `completed: true` and still fail the rubric (e.g. wrong result delivered
   smoothly), and a run can be `completed: false` and still pass if the persona reasonably
   completed their actual goal before the record ends.
4. If `verdict` is `"fail"`, choose a `severity` (`blocker`/`major`/`minor`) per the meanings
   in `rubric.md`, from the worst thing the evidence actually shows. If `verdict` is
   `"pass"`, `severity` is always `"none"`.
5. Carry over or add to `suspectedIssues`: anything in the record's own `suspectedIssues`
   that the evidence supports, plus anything else you observed in `steps`/`observations`
   that looks like a real defect. Each entry is `{"summary": "<one line>", "severity":
   "blocker"|"major"|"minor"}`. Leave it as `[]` if nothing rises to that level — do not
   pad it with restatements of a passing score.
6. Write `rationale` as 1–3 sentences that cite specific evidence (quote or paraphrase a
   step or observation) — not a generic restatement of the scores.

## Output contract — read this exactly

Emit **exactly one JSON object** and nothing else: no prose before it, no prose after it,
no markdown code fence, no explanation of your reasoning outside the `rationale` field. The
object must have exactly these keys:

```json
{
  "personaId": "<copied verbatim from the run record's personaId>",
  "scenario": "<copied verbatim from the run record's scenario>",
  "scores": {
    "<dimension>": 0,
    "...": 0
  },
  "verdict": "pass",
  "severity": "none",
  "rationale": "<1-3 sentences citing specific evidence>",
  "suspectedIssues": []
}
```

Key-by-key contract:

- `personaId` — string. Copy from the run record; do not alter it.
- `scenario` — string. Copy from the run record; do not alter it.
- `scores` — object. One key per active dimension, each an integer 0–5. No extra keys, no
  missing keys.
- `verdict` — string, exactly `"pass"` or `"fail"` (lowercase, no other values).
- `severity` — string, exactly one of `"blocker"`, `"major"`, `"minor"`, `"none"`.
- `rationale` — string.
- `suspectedIssues` — array (possibly empty) of `{"summary": string, "severity": string}`
  objects.

Do not add keys beyond these seven. Do not omit any of them, even when a value is trivial
(e.g. `suspectedIssues: []` on a clean pass) — every key must be present in every response.
