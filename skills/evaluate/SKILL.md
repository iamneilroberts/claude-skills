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

Given one URL, produce an evidence-backed verdict plus a report. Subagents crawl the code
in chunks; the calling session keeps only conclusions.

## Two questions, every time

Judge both — don't collapse to "lift code":

1. **ADOPT AS-IS** — is the product itself worth keeping/running, slotted into your Claude
   Code workflow (a CLI on PATH, an MCP server, a `/skill` or hook pattern, a dotfile)?
   Judged from docs + how it runs, not a code port. Note install/runtime cost and whether
   it's handy at the workstation even if Worker-irrelevant.
2. **LIFT** — features/code/patterns worth pulling into **this repo**, or worth keeping as
   a reference snippet. The code-crawl axis.

A product can win on one, both, or neither — the verdict names which.

## Operating principles

- **Subagents protect the main context** — orchestrate and synthesize only; never read the
  clone file-by-file yourself; pull conclusions, not file dumps.
- **Evidence or it didn't happen** — every claimed feature cites `path:line`; no evidence,
  no claim.
- **Portability is the point** — score findings against this repo's runtime, deps, license.
- **Docs-only is valid for closed-source** — skip cloning, deliver a docs-based verdict,
  say so explicitly. Read-only rules: see Guardrails.

## Steps

### 0. Resolve the URL → find the source

Locate the product's docs/README and source repo. Try `WebFetch` first; if blocked
(Reddit, some blogs), fall back to `mcp__fetch__fetch` against `old.reddit.com/...`
(`www.reddit.com`/`.json` 403, `old.reddit.com` works). For HN, fetch the linked article +
repo, not just comments. No GitHub/GitLab URL found → mark **closed-source**, jump to step 5.

### 1. Characterize from docs (before cloning)

Read README + landing page + launch post. Capture, in your own words: the **pitch** (one
sentence); **headline claims** (benchmarks, "works with X" — note which are testable);
**architecture** (runtime/platform, language, deployment, deps); **license** (flag
copyleft — GPL/AGPL — loudly: lifting *code* carries obligations, lifting *ideas* doesn't;
gates step 4). Then make the **axis-1 call** (mostly from docs): install/runtime cost,
blockers (hosted service, heavy runtime, paid tier). Often answerable from docs alone —
skip straight to step 5 if so.

Write a 4-6 line **repo-context block** describing this repo (from local `CLAUDE.md`/
`README.md`: what it is, runtime/platform constraints, architecture, what's worth
lifting). Paste it into every subagent prompt to pre-filter findings for portability —
drives axis 2; axis 1 stays with the calling session.

### 2. Clone & inventory (read-only)

```bash
bash .claude/skills/evaluate/survey.sh <git-url> <slug>
```

Shallow-clones to `/tmp/evaluate/<slug>/`, prints tree/LOC/languages/manifests/entry
points. Do **not** `cd` in and run anything. Large tree → partition harder in step 3.

### 3. Partition the codebase into subsets

Carve into coherent, non-overlapping subsets — one subagent each — by concern/module, not
file count. Group by top-level dir/subsystem (`connectors/`, `auth/`, `ui/`, etc.); size
each for close reading (a handful of files to a few thousand LOC, split fat dirs, merge
thin ones); skip noise (`node_modules`, lockfiles, `dist/`, `.github/`, generated/vendored
code, test fixtures unless tests are the point). Typical eval = 3-7 subagents; see
"Scaling" for a genuinely large codebase.

### 4. Dispatch subagents (parallel, read-only)

Send all subagents in a **single message**, `Explore` or `general-purpose` type. Give
each: scratch path, its assigned file/dir list, the repo-context block, the license note,
any focus hint. Prompt template:

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

For 2+ subagents, invoke `superpowers:dispatching-parallel-agents`.

### 5. Synthesize the verdict & write the report

The calling session, not a subagent, produces the verdict — only it sees all subsets at
once and holds the repo's strategic context. Deliver in chat AND write
`docs/evaluations/<date>-<slug>.md`, answering both axes:

- **One-line verdict per axis** — *Adopt as-is:* ADOPT AS-IS / TRY IT / SKIP, with the
  install/run path if adopt/try (e.g. `npm i -g X`, "wire MCP endpoint Y", "drop in
  `~/.claude/skills/`"). *Lift:* LIFT / PARTIAL / SKIP.
- **Why** — 2-4 sentences tied to real wins/blockers.
- **Findings table (LIFT)** — feature · value · liftability · effort · blocker, sorted by
  value.
- **What to lift now** — concrete shortlist with porting notes.
- **What to adopt/try as-is** — exact setup step, cost/auth/runtime caveats; offer to
  install/wire it.
- **What to park** — good ideas not a fit today but findable later (pointer in
  roadmap/ADR, or `/idea`) — often the most valuable output, capturing the pattern even
  when the code doesn't port.
- **What to skip & why.**

A product can land ADOPT-AS-IS + SKIP-lift, SKIP-as-is + LIFT, both, or neither — make the
combination clear. Closed-source → note no code was reviewed; axis 1 still applies.

## Scaling

Default is the `Agent`-tool fan-out above, no opt-in needed. For a very large codebase, or
on explicit request for a workflow/"ultracode", use a `Workflow` pipeline —
`pipeline(subsets, crawl, verify)` — adding a stage that adversarially verifies top
findings exist as described before they reach the verdict.

## Guardrails

- **Never execute the clone** — no install/build/run. Findings confirmable only by running
  are marked "claimed, unverified," not run to check.
- **License before copy-paste** — no verbatim lifts from GPL/AGPL/unlicensed repos;
  reimplement the pattern instead. MIT/Apache/BSD: reuse fine with attribution.
- **Don't pollute the repo tree** — clone stays in `/tmp/evaluate/<slug>/`; the only repo
  artifact is the report under `docs/evaluations/`.
- **Stay honest about fit** — SKIP with one parked idea beats an inflated "adopt"; anchor
  findings to a real portability story.
- **Clean up (optional)** — `rm -rf /tmp/evaluate/<slug>` once the report is written,
  unless the user wants to keep poking at the clone.
