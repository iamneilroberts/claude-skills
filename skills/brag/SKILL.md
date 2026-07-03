---
name: brag
description: Memorialize something you just built by generating a self-contained deep-dive "showcase" page for it — what it is, why it's notable, how it works — with a screenshot if one can be found or captured, and links to related showcase pages. Fast by design, like /idea: ask only what's needed, build the page, don't turn it into a project. Triggers on `/brag <subject>`, "brag about this", "make a showcase page for X", "write up what I just did".
user_invocable: true
args: "<subject> — the thing you're proud of (a feature, fix, trick, or artifact)"
---

# /brag — memorialize something clever, fast

You reach for this in the moment you think "that came out well" and want it recorded before you
move on. It builds one deep-dive page about the subject and links it into a running showcase index.
Treat it like `/idea`: capture quickly, ask only when genuinely blocked, never spiral into a rabbit
hole.

## Output location (resolve once, up front)

- Default: a local `showcase/` directory at the repo root — `showcase/<YYYY-MM-DD>-<slug>.html`
  plus a `showcase/index.html` that lists every page.
- If the project defines a showcase/demo output another way (a `SHOWCASE_DIR` env var, a
  `showcase/.config`, or an existing `showcase/`/`demo/` dir), use that instead.
- Deploying to a live site is **optional and separate** — see step 6. Never assume a deploy target.

## Steps

1. **Take the subject.** `<subject>` is the thing being bragged about. Infer a short `slug`
   (kebab-case) and a working title from it.

2. **Clarify only if needed (0–2 questions, then stop).** Ask a question only when you can't build a
   good page without the answer. Good reasons to ask: you can't tell *what makes it notable*, or
   *where the relevant code/artifact lives*, or *who the page is for* (a teammate vs. a public
   demo — changes how much you explain). If the subject + repo context already answer these, skip
   straight to building. Do not interview the user for polish.

3. **Gather the substance (read-only, quick).** Pull the concrete details the page needs:
   - `git log --oneline -10` and `git diff --stat` (and `git show` on the relevant commit) to see
     what actually changed.
   - Read the key file(s) the subject touches — enough to describe the mechanism honestly, not a
     full audit. Prefer `path:line` specifics over hand-waving.
   - Note a genuine before/after or the problem it solves, if there is one.

4. **Handle the screenshot.** A showcase page wants one visual.
   - Look for an existing image tied to the subject: a recent file under `screenshots/`, `docs/`,
     `assets/`, or the repo's image dirs; an artifact the work just produced.
   - If the subject is a running UI and you can drive a browser (e.g. a screenshot/devtools tool is
     available) **and** you know the URL, offer to capture one.
   - Otherwise, ask the user to drop an image in and give you the path — but don't block on it: if
     they decline, build the page with a captioned placeholder and note that a screenshot can be
     added later.
   - Copy any image into the showcase dir (e.g. `showcase/assets/<slug>.<ext>`) and reference it
     relatively — never hotlink an external or local absolute path.

5. **Build the page.** Write a single self-contained HTML file (inline CSS, no external requests) to
   `<output>/<date>-<slug>.html` with, in order:
   - Title + one-line summary of what it is.
   - **Why it's notable** — the actual cleverness, stated plainly (no marketing adjectives).
   - **How it works** — the mechanism, with `path:line` or a short code snippet where it helps.
   - The screenshot (or placeholder).
   - **Related** — links to existing showcase pages whose slug/tags overlap this subject (scan the
     index; link 1–3 genuinely related ones, skip the section if none).
   - A small footer: date, and the commit SHA it describes if there is one.
   Then update `<output>/index.html`: add/refresh this page's card (title, date, one-liner, thumb),
   newest first. Create the index if it doesn't exist.

6. **Offer to publish (optional, never automatic).** If — and only if — the project has a configured
   way to publish the showcase (a deploy script, a `SHOWCASE_DEPLOY_CMD`, a publish skill like a
   `/mock`-style HTTP PUT), offer to run it and show the resulting URL. If there's no configured
   target, say the page is local and stop. Do not invent a deploy path or push anywhere unprompted.

7. **Confirm and get out of the way.** Print the file path (and URL if deployed), and offer to open
   it. Don't propose follow-up work — the point was to memorialize, not to start a new task.

## Keep it honest

- Describe what's actually there. If the "clever" part has a caveat or a rough edge, a one-line note
  beats overselling — this is a record you'll reread, not a sales page.
- Read-only except for the showcase files (and a copied screenshot). Never edit the code you're
  bragging about, and never deploy without the explicit offer in step 6.
