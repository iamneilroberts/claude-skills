# Persona-Test Scoring Rubric

This rubric defines how a judge subagent scores one persona run record. It is the default
used by every adapter unless the adapter explicitly overrides dimensions and/or the pass
threshold (see "Adapter overrides" below).

## Default dimensions

Score each active dimension as an integer **0–5**. Only score the dimensions that are
active for this run (default three, unless overridden — see below).

### `task_completion`
Did the persona actually get to a working outcome for their stated goal?

- **5** — goal fully achieved, no dead ends, no unresolved steps.
- **4** — goal achieved with a minor detour (e.g. one retry) that didn't require giving up.
- **3** — goal achieved, but only after friction that a real user might have abandoned at.
- **2** — goal partially achieved; persona got a usable partial result but not the actual ask.
- **1** — goal not achieved; persona hit a dead end but the run record shows some progress.
- **0** — goal not achieved at all, or the run errored/crashed before any progress.

### `correctness`
Was what the app told/showed the persona actually true and internally consistent?

- **5** — every response the persona received was accurate and consistent end to end.
- **4** — accurate, with a cosmetic inconsistency (e.g. a label mismatch) that didn't mislead.
- **3** — mostly accurate; one minor inaccuracy that a careful user would catch and route around.
- **2** — a real inaccuracy that could mislead a normal user (wrong price, wrong count, stale data).
- **1** — a significant inaccuracy that would cause the persona to make a bad decision.
- **0** — a fabrication, a contradiction, or a response that materially misrepresents what happened.

### `ux_friction`
How much unnecessary effort, confusion, or wasted motion did the persona experience?

- **5** — no friction; the app matched the persona's tendencies and mental model.
- **4** — negligible friction (one clarifying question, resolved immediately).
- **3** — some friction (a confusing label, a step that needed a second look) but the persona
  pushed through without help.
- **2** — real friction; the persona had to guess, backtrack, or repeat itself.
- **1** — heavy friction; the persona nearly abandoned per their own stated tendencies.
- **0** — the friction alone would have caused this persona to abandon (per their
  `interaction tendencies`), independent of whether the task technically completed.

## Pass threshold (default)

```
verdict = "pass"  if  task_completion >= 3  AND  correctness != 0
verdict = "fail"  otherwise
```

`ux_friction` does not gate pass/fail by default — it is diagnostic. A run can pass with
low `ux_friction` if the persona still got to a correct outcome; low `ux_friction` on
otherwise-passing runs is a signal for follow-up, not a build blocker.

## Severity meanings (for a `fail` verdict)

- **`blocker`** — the persona could not complete their core task at all, hit an error,
  or was given information that would cause real harm (wrong charge, lost data, unsafe
  advice). Ship-stopping.
- **`major`** — the persona completed the task but only by working around a real defect,
  or received something incorrect that a normal user would act on. Needs a fix before
  the next release, not necessarily before this deploy.
- **`minor`** — friction or a small inaccuracy that a persona routed around without real
  cost. Worth filing, not worth blocking on.
- **`none`** — reserved for `pass` verdicts. A `fail` must never carry `severity: "none"`;
  if severity is genuinely unclear on a fail, default to `major` rather than `none`.

## Adapter overrides

An adapter may override this rubric for its domain:

- **Dimensions** — an adapter may declare a different set of active dimensions (e.g.
  additional domain-specific axes) in place of, or in addition to, the three defaults
  above. When it does, the judge scores exactly the dimensions the adapter declares
  active — no more, no fewer — and defines what each dimension's 0–5 scale means for
  that domain, following the same "0 = worst, 5 = best" convention.
- **Pass threshold** — an adapter may replace the default threshold formula with its own,
  as long as it stays expressible as a boolean function of the active dimension scores.

When no adapter override is present, use the defaults on this page exactly as written.
