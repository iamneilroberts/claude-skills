# frontier-spend

**A doctrine (and Claude Code skill) for spending scarce or expiring access to a
premium frontier-tier model — so that what you bought survives after the access is
gone.**

Written for the July 2026 Fable-leaves-Pro/Max cliff (50% weekly cap until July 7,
unaffordable pay-per-use after), but the doctrine applies to any setup where one model
tier is markedly smarter, markedly more expensive, and capped: spend it so the value
lands in **durable artifacts** a cheaper model can execute later.

## TL;DR

A scarce premium model is a **non-renewable judgment credit**, not a faster typist.
After the cap or the cliff, the only value you keep is what got crystallized into
plans, verdicts, audits, and tests. Four rules, each countering something capable
agents get wrong *by default* (verified — see [Testing](#testing) below):

1. **Adjudicate, don't author.** Don't have the premium model write plans/specs/ADRs
   from scratch — planning is its fastest token burn (practitioner reports put one
   planning pass at ~35% of a usage window). Instead: **cheap model drafts →
   independent cross-vendor reviewer audits → premium model adjudicates the
   disagreements and patches.** Same banked artifact; several times more of them per
   cap. From-scratch authoring only after a cheap draft comes back structurally wrong
   twice.
2. **Ration audits to a named budget.** Comprehensive review sweeps feel high-value
   and exhaust a cap fastest. Pick the audit count up front (default: **two**) and
   name them — e.g. a golden-path adversarial review before an important demo, and one
   tech-debt/architecture sweep whose output is a prioritized backlog for the cheap
   model to grind through later. Everything else gets triage-grade attention or none.
3. **Tune the effort slider.** Run the premium model at reduced reasoning effort for
   triage-grade judgment (queue ranking, routine verdicts) — low-effort premium can
   undercut the mid-tier model's cost. Max effort is reserved for the named audits and
   plan adjudication.
4. **Review the premium output too.** The premium model is smarter *and* more
   confidently wrong — the worst combination to trust blindly. Keep an external,
   different-vendor review gate on its artifacts; don't exempt them because "the smart
   model wrote it".

Plus standing hygiene most agents get right unprompted but that's worth pinning:
pre-digested context packs (never let the premium model explore a repo raw), one
judgment deliverable per session, no long sequential checklists (a known
rogue-behavior trigger), and budget math first — a 50% weekly cap at 2× burn is
**4–6 tight sessions**, not "three days of use".

## A worked endgame template (3 days left, capped)

1. **Bank the plan queue** (highest leverage). Cheap model drafts implementation plans
   for the 4–6 biggest post-cliff backlog items; cross-vendor reviewer audits each;
   **one batch premium session adjudicates all of them.**
2. **Audit A** — adversarial end-to-end review of the product's golden path (premium
   model judges; cheap subagents drive the browser/HTTP and report raw observations).
3. **Audit B** — tech-debt/architecture sweep → prioritized cleanup backlog.
4. **Judgment-dense prose** you actually need (docs where reasoning quality shows).
5. **Sweep-up**: remaining budget re-adjudicates the plan queue against late changes —
   no new scope. Keep a small reserve until after your critical event.

## Testing

The skill was built test-first, the way you'd TDD code:

- **Baseline (no skill):** a fresh mid-tier agent given the "3 days of premium access
  left, plan my spend" scenario already produced ~70% of the doctrine on its own —
  durable artifacts, judgment-vs-typing, pre-narrowing context. What it missed, every
  time: it had the premium model **authoring** the plans itself, scheduled ~6
  unrationed audit sweeps, never mentioned effort tuning, and never subjected premium
  output to review.
- **With the skill loaded:** the same scenario produced all four missing behaviors —
  two named audits chosen up front, draft-cheap-then-adjudicate flow, effort tiering,
  and self-review of its own audits.

That's why the skill text carries **only the four counter-default rules** and keeps
the parts agents already get right to a short hygiene list — skills that restate the
obvious get skimmed.

## Install (Claude Code)

Copy the skill directory into your project or user skills dir:

```bash
cp -r skills/frontier-spend ~/.claude/skills/frontier-spend    # user-wide
# or  .claude/skills/frontier-spend                            # per-project
```

Claude Code picks it up automatically; it triggers on planning premium-model spend
("how should I spend my remaining premium budget", model-deprecation cliffs, usage
caps). The skill file itself is [SKILL.md](SKILL.md).

## Companion tooling (same repo)

The doctrine assumes two cheap substitutes exist; both live in this repo:

- [`llm-tools`](../llm-tools/) — `llm-ask` / `llm-write` / `llm-extract` CLIs that
  route bulk reading and boilerplate to a cheap OpenAI-compatible worker (~125×
  cheaper for "summarize / find facts"). This is what builds the pre-digested context
  packs.
- [`codex-review`](../codex-review/) — the cross-vendor review gate: a different
  vendor's model returns a structured JSON verdict scored against a severity schema,
  and a script converts it to a pass/fail exit code, so a blocking finding gets fixed
  or escalated instead of re-argued by the model that wrote the code. This is both the
  "audit" step in rule 1 and the "review the premium output" gate in rule 4.

## Provenance

The judgment/mechanical split matches the prevailing published pattern for
frontier-tier models (orchestrator + final synthesis on the premium tier;
implementation on mid-tier; scan/extract on the cheap tier). The four rules were
distilled from practitioner reports in r/ClaudeAI —
[the redeployment thread](https://www.reddit.com/r/ClaudeAI/comments/1ukafrm/) for the
cliff/cap constraints and
["Alright, I finally gave Fable a spin today"](https://www.reddit.com/r/ClaudeAI/comments/1unmssy/)
for the planning-burn measurements, the adjudicator pattern, and the effort-slider
observation — then A/B-tested as described above.
