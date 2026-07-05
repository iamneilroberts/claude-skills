---
name: frontier-spend
description: Use when planning how to spend scarce or expiring access to a premium frontier-tier model (usage-capped, deprecation cliff, "how should I spend my remaining premium-model budget", 2x burn rate, model leaving the plan) — before starting any premium-model session or writing a spend plan.
---

# Frontier Spend

## Overview

A scarce premium-tier model is a **non-renewable judgment credit**. The only value that
survives the cap or the cliff is what lands in durable artifacts (plans, verdicts,
audits, tests) that a cheaper model executes later. Most agents get "spend on judgment,
not typing" right on their own — the four rules below are the ones they miss.

## The four rules (each one counters a default failure)

1. **Adjudicate, don't author.** Do NOT have the premium model write specs/plans/ADRs
   from scratch — planning is its fastest token burn (practitioner reports: ~35% of a
   usage window on one planning pass). Instead: **cheaper model drafts → an independent
   cross-vendor reviewer audits → premium model adjudicates the disagreements and
   patches.** Same banked artifact, several times more of them per cap. From-scratch
   authoring only after a cheap draft comes back structurally wrong twice.
2. **Ration audits to a named budget.** Comprehensive sweeps feel high-value and are the
   fastest way to exhaust a cap. Pick the audit count up front (default: **two**) and
   name them (e.g. golden-path adversarial review + tech-debt sweep). Everything else
   gets triage-grade attention or none.
3. **Tune the effort slider.** Reduced reasoning effort for triage-grade judgment
   (queue ranking, routine verdicts) — low-effort premium can undercut the mid-tier
   model's cost. Max effort only for the named audits and plan adjudication.
4. **Review the premium output too.** The premium model is smarter AND more confidently
   wrong — keep the external review gate on its artifacts, don't exempt them because
   "the smart model wrote it".

## Native mechanism for rule 1 (Claude Code v2.1.170+): the Advisor tool

Anthropic shipped a first-party **Advisor tool** (`code.claude.com/docs/en/advisor`) that
implements "premium judges, doesn't type" directly: a cheaper executor model consults a
higher-intelligence advisor model mid-generation. The relevant pairing for a capped
premium tier is **executor-main + premium-advisor** (e.g. Sonnet main + Fable advisor):
premium guidance at decision points without running the premium model throughout. Prefer
this over a hand-rolled adjudication loop for *mid-task* decisions when it is available.

It does **not** replace the rest of the doctrine, and three known limits are why:
- **Server-side, not hookable.** You cannot gate it to specific phases — it is a prose-only
  rule available to any eligible agent. Rationing (rule 2) and effort tuning (rule 3)
  remain your manual discipline.
- **It still spends the cap, unbounded.** A consult on a large session burns premium
  budget; budget-first math still applies.
- **It vanishes at the cliff.** When affordable premium access ends, the premium-advisor
  pairing goes with it — so the durable-artifact core (bank plans/audits/tests a cheap
  model executes later) is what survives, unchanged. Use the Advisor tool for live
  decisions *now*; keep banking artifacts for *after*.

## Standing hygiene (agents mostly do this unprompted; keep anyway)

- Pre-digest context: open every premium session with a brief built by a cheap model
  (≤2k words); never let the premium model explore a repo raw.
- One judgment deliverable per session; if it drifts mechanical, hand off and switch
  models mid-session.
- No long sequential checklists (known rogue failure mode) and no bulk reads.
- Budget math first: a 50% weekly cap at 2× burn ≈ 4–6 tight sessions, not "3 days".

## Red flags — you are about to waste the credit

- "I'll just have the premium model draft the plan itself" → rule 1.
- "While we're at it, let's also audit X" beyond the named budget → rule 2.
- Running max effort on a triage question → rule 3.
- Shipping a premium-authored artifact unreviewed → rule 4.
- The premium session's first action is a grep/read of the repo → hygiene 1.
