# Writing an adapter for your app

`/persona-test` is app-agnostic. Everything specific to *your* app lives in one directory,
`adapters/<name>/`, containing at least an `adapter.md`. This guide shows how to write that
file for the common app shapes — a JSON API, a server-rendered HTML site, a Node.js app, or a
Playwright-driven browser app. Read `adapters/example-http/adapter.md` alongside it: that is
the fully-worked reference (a plain HTTPS JSON API), and this guide is the "…but my app isn't
an HTTP JSON API" companion.

Run your finished adapter with:

```bash
./persona-test.sh --adapter <name> --target <label>
```

## What an adapter is

An adapter is **pure declaration** — Markdown the skill and its subagents read, never code
that `lib/` imports. `adapter.md` declares three required hooks and any optional overrides:

| Hook | Answers |
|---|---|
| `reach/interact` | How does a persona subagent reach the app and take **one turn**? |
| `done` | When is a run over, and how is `completed` / `terminatedBy` set? |
| `context` | One paragraph — the app's domain, core tasks, and vocabulary — fed to persona generation. |

Optional overrides (`judge_dimensions`, pass threshold, an extra `sink`) are documented in
`example-http/adapter.md` under **Optional overrides**; they are stack-independent, so this
guide doesn't repeat them. If your app has no external system to report to, declare no sink —
the local Markdown report under `runs/<run_id>/report.md` is always written regardless.

## Invariants — true for EVERY adapter, whatever the stack

These do not change between an HTTP API and a browser app. Only the *mechanics* of "one turn"
in the `reach/interact` hook differ; everything below is fixed.

1. **One turn = one user-meaningful action.** Whatever "the persona does one thing" means for
   your app (one API call, one page navigation, one button click, one CLI invocation), that is
   one turn — not "call every endpoint" or "script the whole happy path in one shot."
2. **Every turn is recorded as a step** in the run record's `steps` array. The reference shape
   is `{intent, appResponse, note}`:
   - `intent` — what the persona was *trying* to do, in plain language.
   - `appResponse` — a short **paraphrase** of what came back, not a raw dump (no full JSON
     body, no full HTML, no base64 screenshot inline).
   - `note` — anything the persona noticed, in character.
   You may add fields (e.g. `screenshotPath`), but keep these three.
3. **A reach failure is itself a step.** Connection refused, 5xx, auth rejected, a selector
   that doesn't exist, a crashed process — record it verbatim in `appResponse` and let the
   persona react the way its `Interaction tendencies` say (retry, give up). Never silently skip
   a failed turn.
4. **The persona stays in character.** It chooses the next turn from what *it* would do next
   per its persona file, not from a fixed script and not by exhaustively exercising the API.
5. **The run ends on the first `done` condition** (below) and the driver stops there — it does
   not keep going "to see what happens next."
6. **The driver emits one run record** matching `lib/schema.py`'s `validate_run_record`:
   required `personaId`, `scenario`, `mode` (strings), `steps` (array), `completed` (bool),
   `observations` (array), `suspectedIssues` (array), plus `personaSource`. A record that fails
   validation is dropped from the run — so produce the exact shape.

### The `done` hook (also stack-independent)

A run ends the first time one of these is true — copy this list into your `adapter.md`, adding
any app-specific guardrail as an extra terminal condition:

1. **Goal achieved** — the persona's `Goal` is satisfied. `completed: true`,
   `terminatedBy: "goal_achieved"`.
2. **Persona quits** — a quit condition in the persona's `Constraints` / `Interaction
   tendencies` is met (e.g. "quits after 2 dead ends"). `completed: false`,
   `terminatedBy: "persona_quit"`.
3. **Turn cap** — 8 turns elapse with neither of the above. `completed: false`,
   `terminatedBy: "turn_cap"`.
4. **Unrecoverable error** — a reach failure the persona's tendencies don't cover as a retry.
   `completed: false`, `terminatedBy: "error"`.
5. *(optional, app-specific)* **Guardrail** — a turn that would do something the run must never
   do for real (a payment, a destructive write, a publish to a real recipient). End
   immediately; `completed: false`, `terminatedBy: "guardrail"`. Name the exact actions that
   trip it so the driver can recognise one before it fires the call.

## Per-stack `reach/interact` recipes

Pick the one that matches your app. Each is a drop-in shape for the `reach/interact` section of
your `adapter.md` — describe your app's specifics (URLs, selectors, auth) in prose the way
`example-http` does, and give one concrete example turn.

### 1. HTTP / JSON API

Use `adapters/example-http/adapter.md` as-is — it *is* this recipe. One turn is one HTTP
request; `appResponse` paraphrases the JSON reply. State your base URL, auth header, and one
example `curl`.

### 2. Server-rendered HTML site (pages, links, forms)

The app has no JSON API — the persona navigates pages and submits forms, and the "reply" is a
rendered page. One turn = **one navigation or one form submission**.

- **Reach** — HTTP `GET` a page URL, or `POST` a form's fields to its `action`. Carry the
  session cookie the site sets (log in once, reuse the `Set-Cookie`).
- **appResponse** — parse the returned HTML and paraphrase the *meaningful* content: the
  page's heading, the visible options, any error banner, the form fields now presented. Do
  **not** dump the raw HTML into the step.
- **Reach failure** — a 4xx/5xx, or a page that renders an error/validation message, is a
  step; record the message text and let the persona react.

```
- Base URL — $MYAPP_BASE_URL. Session cookie from POST /login (username+password form).
- One turn — the persona decides what it wants, then either GETs the next page or submits
  one form. Example: submit the search form —
    curl -sS -b cookies.txt "$MYAPP_BASE_URL/search" --data-urlencode 'q=blue widgets'
  Read the returned page, paraphrase "results list: 3 widgets, cheapest $4" into appResponse.
- A rendered validation error ("pick a date") is a step, not a skip.
```

### 3. Node.js app

Two shapes — pick by whether you can import the app in-process or must run it.

**3a. In-process (import and call).** If the persona's action maps to calling one of the
app's own functions/handlers, import them and call one per turn. This is the fastest, most
deterministic reach and needs no running server.

```
- Reach — import { handleCommand } from '<app>/src/api.js'; one turn = one handleCommand(...)
  call, its return value read as the app's reply.
- appResponse — paraphrase the returned object (not a JSON dump).
- A thrown error / rejected promise is a step: record the message, persona reacts.
```

**3b. Spawn-and-drive.** If the app is a service, start it once, then drive it as whatever it
exposes (usually HTTP — fall back to recipe 1 or 2 for the per-turn shape).

```
- Setup (once, not a turn) — `npm start` on port $PORT; wait for /health 200; tear down at end.
- Per turn — one request against the running server, per recipe 1 (JSON) or 2 (HTML).
- A non-2xx or a crash (process exits) is a step; record it, persona reacts.
```

### 4. Playwright / browser app (SPA, canvas, anything you click)

The app is a real page a human operates. One turn = **one user action** (click, type, select,
press) identified by **accessible name**, not pixel position.

- **Reach** — drive a Chromium page with Playwright (a small driver script the subagent runs)
  or a browser MCP if one is available. Each turn locates a control by role+name
  (`getByRole('button', { name: 'Search' })`), performs one action, then reads the resulting
  page.
- **appResponse** — paraphrase the page's *accessible* state after the action: the visible
  text, the named controls now present, any alert/toast. Optionally save a screenshot to
  `runs/<run_id>/<persona>-turn<N>.png` and put the **path** in a `screenshotPath` field —
  never the image bytes.
- **Reach failure** — a locator that matches nothing, a timeout waiting for an element, a
  navigation error. Record it as a step ("no control named 'Checkout' appeared") and let the
  persona react; a persona whose tendencies say "gives up after two dead ends" should quit.
- Prefer **headed for debugging, headless for the run.** Log in once in a setup step and reuse
  the storage state; don't re-auth every turn.

```
- Reach — Playwright Chromium at $MYAPP_URL; storageState from a one-time login.
- One turn — locate by role+name, do ONE action, read the page. Example:
    await page.getByRole('textbox', { name: 'Destination' }).fill('Lisbon');
    await page.getByRole('button', { name: 'Search' }).click();
    // appResponse: "results grid appeared, 6 hotels, 'Sort by price' control visible"
- A missing locator or timeout is a step; do not retry silently past the persona's patience.
```

### 5. Anything else (CLI, gRPC, a chat/MCP endpoint, …)

The pattern holds: define what *one turn* of interaction is for your app, how the persona
reads the reply, and how a failure is recorded. For a CLI, one turn is one invocation with
args and `appResponse` paraphrases stdout/exit code. For an MCP/chat endpoint, one turn is one
tool call or one message. State it explicitly and give one example.

## New-adapter checklist

- [ ] `adapters/<name>/adapter.md` exists with all three hooks.
- [ ] `reach/interact` names the target(s), the auth, defines **one turn** for your stack, and
      shows **one concrete example turn**.
- [ ] `reach/interact` states that a reach failure is recorded as a step, not skipped.
- [ ] `done` lists the four terminal conditions (+ any guardrail) with the `completed` /
      `terminatedBy` each sets.
- [ ] `context` is one paragraph: domain, core task(s), vocabulary.
- [ ] Steps are recorded as `{intent, appResponse, note}` with `appResponse` **paraphrased**,
      never a raw body/HTML/screenshot dump.
- [ ] Optional overrides declared only if needed (`judge_dimensions`, pass threshold, sink +
      mapper) — see `example-http/adapter.md`.
- [ ] `./persona-test.sh --adapter <name> --target <label>` resolves and runs.
- [ ] No secrets in `adapter.md`, in any persona run record, or in the report — creds come from
      env vars / a gitignored file, exactly as `example-http` documents.
