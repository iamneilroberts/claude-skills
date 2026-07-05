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
