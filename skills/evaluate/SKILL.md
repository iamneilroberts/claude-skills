---
name: evaluate
description: |
  Tear down a third-party product/tool/library from a single URL and answer two questions:
  (1) is the product worth adopting as-is — installed into your Claude Code workflow (a CLI,
  MCP server, skill, or dotfile) or otherwise kept around — and (2) are there features or
  code worth lifting into your current repo. Most evaluations are hunting for one of those
  two wins. It resolves the URL to its source (repo, README, launch post — with Reddit and
  paywalled-fetch fallbacks), characterizes the product from its docs, clones the code
  locally when it's open source, then fans out read-only subagents — each handed a subset of
  the codebase plus your repo's context — to find liftable features with file:line evidence
  and portability notes. The calling session merges the findings into a verdict (adopt / lift
  / partial / skip) with per-finding analysis and writes a report to docs/evaluations/. Use
  for "is this repo worth anything to me?", "should I start using this", competitive
  teardowns, "should we adopt X", "evaluate this Show-HN / r/mcp / Product Hunt link".
  Triggers on `/evaluate <url>`, "evaluate this product", "deep dive this repo for things we
  can lift", "is this tool worth using", "teardown <url>", "what can we steal from <project>".
user_invocable: true
args: "<url> (product page, GitHub repo, Reddit/HN post, or launch blog) — optionally followed by a focus hint, e.g. '/evaluate <url> focus: tool-routing'"
---

# /evaluate — teardown a product from a URL and decide what's worth keeping

Given one URL, produce an evidence-backed verdict plus a detailed findings report. The
work is delegated: subagents crawl the code in digestible chunks so the **calling session
never loads the whole codebase** — it keeps only conclusions and writes the verdict.

## Two questions, every time

You are normally hunting for one of two wins — judge **both**, don't collapse to "lift
code into your repo":

1. **ADOPT AS-IS** — is the *product itself* worth keeping/running? Could it slot into
   your **Claude Code workflow** (a CLI he'd put on PATH, an MCP server he'd wire into a
   session, a `/skill` or hook pattern, a dotfile/tool worth installing), or is it just a
   good tool to keep around? This is a *use-it* judgment, mostly made from docs + how it
   runs — not a code port. Note install/runtime cost and whether it's Worker-irrelevant
   but still useful at the workstation.
2. **LIFT** — are there *features/code/patterns* worth pulling into **your repo** (this
   repo), or worth keeping as a reference snippet? This is the code-crawl axis.

A product can win on one, both, or neither. The verdict names which.

## Operating principles

- **Subagents protect the main context.** The calling session orchestrates and
  synthesizes; it does NOT read the cloned tree file-by-file. Every chunk of code is
  read by a subagent that reports back a structured digest. Pull conclusions into the
  driver thread, not file dumps.
- **Evidence or it didn't happen.** Every claimed feature must cite `path:line` in the
  clone. No "it probably has X." Subagents that can't find evidence say so.
- **Portability is the whole point.** A feature is only interesting if it can plausibly
  land in *this* repo. Each finding is scored against this repo's runtime, deps, and
  license — not evaluated in the abstract.
- **Read-only. Never execute cloned code.** Clone, read, grep. Do **not** run install
  scripts, `npm install`, build steps, or the product itself. Untrusted code.
- **Docs-only is a valid path.** If the product is closed-source (no repo), skip cloning
  and deliver a docs-based verdict — say so explicitly rather than faking a code review.

## Steps

### 0. Resolve the URL → find the source

Identify the product and locate (a) its canonical docs/README and (b) its source repo.

- Try `WebFetch` first. If it's **blocked (Reddit, some blogs)**, fall back to
  `mcp__fetch__fetch` against `old.reddit.com/...` (the `www.reddit.com` host and its
  `.json` 403; `old.reddit.com` works). For HN, fetch the linked article + the repo,
  not just the comment thread.
- Extract the **GitHub/GitLab repo URL** from the post/README. If none exists, mark the
  product **closed-source** and jump to step 5 (docs-only verdict).

### 1. Characterize from docs (before cloning)

Read README + landing page + launch post. Capture, in your own words:

- **The pitch** — what problem it claims to solve, in one sentence.
- **Headline claims** — the specific technical assertions (benchmarks, token counts,
  "works with X"). Note which are testable.
- **Architecture** — runtime/platform, language, how it's deployed, key dependencies.
- **License** — record it. Flag copyleft (GPL/AGPL) loudly: lifting *code* from those
  carries obligations; lifting *ideas* does not. This gates step 4's guidance.
- **Adopt-as-is read (axis 1)** — decide here, mostly from docs, whether the product is
  worth *using* in your Claude Code workflow. How is it installed/run (`npm i -g`, an
  MCP endpoint, a binary, a skill)? Does it complement Claude Code (a tool to put on
  PATH, an MCP server to wire into sessions, a hook/skill pattern), or is it Worker-
  irrelevant but still handy at the workstation? Note the install/runtime cost and any
  obvious blockers (needs a hosted service, heavy runtime, paid tier). This axis often
  needs **no code crawl** — if the only question is "should I use this," you may be able
  to answer from docs and skip straight to step 5.

Write a 4-6 line **repo-context block** describing THIS repo for the subagents (pull
from the local `CLAUDE.md` / `README.md`): what we are, our runtime/platform
constraints, our architecture, and the kinds of things worth lifting. This block is
pasted into every subagent prompt so findings come back pre-filtered for portability —
it drives axis 2 (LIFT). The adopt-as-is axis stays with the calling session.

### 2. Clone & inventory (read-only)

Run the helper — it shallow-clones to a scratch dir outside the repo and prints an
inventory (tree, LOC by dir, languages, manifests, entry points):

```bash
bash .claude/skills/evaluate/survey.sh <git-url> <slug>
```

The clone lands in `/tmp/evaluate/<slug>/`. **Do not** `cd` into it and run anything.
If the survey shows a very large tree, note it — partition harder in step 3.

### 3. Partition the codebase into subsets

Carve the tree into coherent, non-overlapping subsets — **one subagent each**. Partition
by concern/module, not by arbitrary file count:

- Group by top-level dir or subsystem (e.g. `connectors/`, `auth/`, `discovery/`, `ui/`).
- Aim for subsets a single agent can read closely — a handful of files / up to a few
  thousand LOC each. Split a fat directory; merge thin sibling ones.
- Skip noise: `node_modules`, lockfiles, `dist/`, `.github/`, generated code, vendored
  deps, test fixtures (unless tests are the point of the eval).
- Typical eval = **3-7 subagents**. For a genuinely large codebase, see "Scaling" below.

### 4. Dispatch subagents (parallel, read-only)

Send all subagents in a **single message** (parallel). Use the `Explore` or
`general-purpose` agent type. Give each one: the scratch path, its assigned file/dir
list, the repo-context block from step 1, the license note, and the focus hint if the
user gave one. Use this prompt template:

```
You are evaluating a third-party codebase to find features worth lifting into OUR repo.
READ-ONLY: read and grep files; never run, install, or build anything.

OUR REPO (what we'd be lifting INTO):
<repo-context block from step 1 — runtime, platform constraints, architecture, license>

THE PRODUCT'S LICENSE: <license> — <if copyleft: lifting code carries obligations; focus
on patterns/ideas we'd reimplement, not copy-paste>.

YOUR SUBSET (read closely; ignore everything else in the clone):
  scratch path: /tmp/evaluate/<slug>/
  files/dirs:   <the assigned subset>
FOCUS HINT (if any): <hint>

For THIS subset, report back as a list of candidate findings. For each:
  - name + one-line description
  - evidence: the key file:line locations
  - what it does (mechanism, briefly)
  - liftability into OUR repo: drop-in | adapt | incompatible — and WHY (name the
    concrete blocker: runtime mismatch, heavy dep, license, host constraint, etc.)
  - dependencies it drags in
  - rough effort to port (S/M/L)
Then one line: your overall read of this subset (is there anything here for us?).
Return ONLY this digest — no preamble. If the subset has nothing liftable, say so plainly.
```

(For 2+ independent subagents, the `superpowers:dispatching-parallel-agents` skill
applies — invoke it.)

### 5. Synthesize the verdict & write the report

Collect the digests. The calling session — NOT a subagent — produces the verdict, because
only it sees all subsets at once and holds the repo's strategic context.

Deliver in chat AND write to `docs/evaluations/<date>-<slug>.md`. Answer **both axes
explicitly** — don't let the LIFT analysis swallow the adopt-as-is call:

- **One-line verdict** per axis:
  - *Adopt as-is (use it in my workflow):* ADOPT AS-IS / TRY IT / SKIP — with the one-line
    install/run path if adopt/try (e.g. `npm i -g X`, "wire MCP endpoint Y", "it's a skill,
    drop in `~/.claude/skills/`").
  - *Lift into your repo:* LIFT / PARTIAL / SKIP.
- **Why** — 2-4 sentences tied to the real wins/blockers (workflow fit for axis 1; this
  repo's runtime/deps/license for axis 2).
- **Findings table (LIFT)** — each candidate feature: what it is · value to us ·
  liftability · effort · blocker. Sort by value.
- **What to lift now** — the concrete shortlist, if any, with the porting note.
- **What to adopt/try as-is** — if the product (or a sub-tool of it) is worth running in
  the Claude Code workflow, say so with the exact setup step; flag any cost/auth/runtime
  caveat. Offer to actually install/wire it.
- **What to park** — good ideas that aren't a fit today but should be findable later
  (offer to drop a pointer in the roadmap/ADR area, or `/idea` it). Often the most valuable
  output: capture the *pattern* even when the *code* doesn't port.
- **What to skip & why.**

A product can land ADOPT-AS-IS + SKIP-lift (great tool, nothing to port), or
SKIP-as-is + LIFT (don't want to run it, but steal a pattern), or both, or neither. Make
the combination clear.

For closed-source products, the report is docs-only: state that no code was reviewed,
and base the verdict on claims + architecture fit (the adopt-as-is axis still applies —
you can often decide "should I use this" without source).

## Scaling

Default is an `Agent`-tool fan-out (above) — no special opt-in. For a **very large**
codebase, or when the user explicitly asks for a workflow / "ultracode", a `Workflow`
pipeline fits well: `pipeline(subsets, crawl, verify)` — crawl each subset, then have a
second stage adversarially verify the top findings actually exist as described before
they reach the verdict. Only reach for `Workflow` on explicit opt-in (see its tool docs).

## Guardrails

- **Never execute the clone.** No `npm i`, no build, no run. If a finding can only be
  confirmed by running code, mark it "claimed, unverified" — don't run it to check.
- **License before copy-paste.** Don't recommend lifting code verbatim from
  GPL/AGPL/unlicensed repos — recommend reimplementing the pattern. MIT/Apache/BSD: code
  reuse is fine with attribution per the license.
- **Don't pollute the repo tree.** The clone lives in `/tmp/evaluate/<slug>/`, never
  inside the working repo. The only artifact written into the repo is the report under
  `docs/evaluations/`.
- **Stay honest about fit.** The most useful verdict is often SKIP with one parked idea.
  Don't inflate a teardown into "adopt" to feel productive — anchor every finding to a
  real portability story.
- **Clean up when done** (optional): `rm -rf /tmp/evaluate/<slug>` once the report is
  written, unless the user wants to keep poking at the clone.
