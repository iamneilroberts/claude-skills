# Adapter: example-http (reference)

This is the **reference adapter** — a working example against a plain HTTP JSON app, written
to document the adapter contract for anyone building a new one. It targets a fictional "Notes
API" (`POST /api/notes` to create a note, `GET /api/notes?q=` to search). Copy this file's
structure, not its literal endpoints, when writing a real adapter.

An adapter is a directory at `adapters/<name>/` containing at minimum this file,
`adapter.md`. It may also contain adapter-specific code (a mapper, like
`adapters/voygent/map_to_board.py`) if its sink needs one. Everything an adapter declares is
consumed by `SKILL.md` and by the persona/judge subagents it dispatches — an adapter is pure
declaration, never itself imported by `lib/`.

## Required hook 1: reach/interact

Describes how a persona subagent actually reaches the app and carries out one turn of
interaction. For this adapter: the app is a plain HTTPS JSON API.

- **Base URL** — `$EXAMPLE_HTTP_BASE_URL` (env var; e.g. `http://localhost:4000`).
- **Auth** — `Authorization: Bearer $EXAMPLE_HTTP_TOKEN` on every request.
- **One turn** — the persona subagent, in character, decides what it wants next (in plain
  language, per its persona file), translates that into one HTTP call, and reads the JSON
  response as the app's "reply". Example turn:

  ```bash
  curl -sS -X POST "$EXAMPLE_HTTP_BASE_URL/api/notes" \
    -H "Authorization: Bearer $EXAMPLE_HTTP_TOKEN" \
    -H "Content-Type: application/json" \
    --data '{"title":"grocery list","body":"eggs, bread"}'
  ```

- The subagent records each turn as a `{intent, appResponse, note}` entry in the run record's
  `steps` array (`intent` = what the persona was trying to do; `appResponse` = a short
  paraphrase of what came back, not the raw JSON dump; `note` = anything the persona noticed,
  in character).
- A **reach failure** (connection refused, 5xx, auth rejected) is itself a step — record it
  verbatim in `appResponse` and let the persona react to it the way their `Interaction
  tendencies` say they would (retry, give up, etc.). Never silently skip a failed call.

## Required hook 2: done

Describes how the driver subagent decides a run is over, and how it fills in `completed` and
(for adapters that track it) `terminatedBy`.

A run ends the first time one of these is true:

1. **Goal achieved** — the persona's stated `Goal` (from its persona file) is satisfied by an
   app response. `completed: true`, `terminatedBy: "goal_achieved"`.
2. **Persona quits** — the persona's `Interaction tendencies` or `Constraints` describe a quit
   condition (e.g. "quits after 2 dead ends") and the run record shows that condition met.
   `completed: false`, `terminatedBy: "persona_quit"`.
3. **Turn cap** — 8 turns elapse with neither of the above. `completed: false`,
   `terminatedBy: "turn_cap"`.
4. **Unrecoverable error** — a reach failure the persona's tendencies don't cover as a retry
   case. `completed: false`, `terminatedBy: "error"`.

Whichever fires, the driver writes the run record per `lib/schema.py`'s `validate_run_record`
shape and stops — it does not keep going past the terminating condition to "see what happens
next".

## Required hook 3: context

A short, adapter-authored description of the app's domain, its core user task(s), and its
terminology — fed verbatim to `lib/generate-personas.md` when the run generates additional
personas beyond the starter library.

```
context: A personal note-taking API. Users create short text notes and search past notes
by keyword. Core tasks: capture a note quickly, find a note you vaguely remember later.
No accounts, no sharing, no attachments — text only.
```

## Optional overrides

An adapter may declare any of these; when it doesn't, `SKILL.md` uses the defaults from
`rubric.md` and writes only the local report.

### Judge dimensions override

Replaces the three default dimensions (`task_completion`, `correctness`, `ux_friction`) with a
domain-specific set, passed to the judge subagent (`lib/judge.md`) in place of the rubric
defaults. This adapter doesn't need one and uses the rubric defaults as-is. An adapter that
did would declare it like:

```
judge_dimensions: task_completion, correctness, data_integrity
```

(`data_integrity` illustrative only — see `adapters/voygent/adapter.md` for a real override.)

### Pass threshold override

Replaces `rubric.md`'s default pass formula (`task_completion >= 3 AND correctness != 0`).
Not used by this adapter.

### Sink override

Beyond the local report (`sinks/local_report.py`), which `SKILL.md` always writes, an adapter
may declare an additional sink that posts the aggregated results somewhere else — typically
`sinks/http_post.py` against an endpoint, optionally through an adapter-owned mapper (like
`adapters/voygent/map_to_board.py`) that reshapes the judged results into that endpoint's
body first. This adapter has no external system to report to, so it declares none — the local
Markdown report under `runs/<run_id>/report.md` is the only output.

## Env vars

- `EXAMPLE_HTTP_BASE_URL` — base URL of the target app.
- `EXAMPLE_HTTP_TOKEN` — bearer token for the target app.

Neither is required to exist for the default (non-live) test suite — this file documents the
contract; nothing in `tests/run_integration.sh` calls this adapter's `reach` hook for real.
