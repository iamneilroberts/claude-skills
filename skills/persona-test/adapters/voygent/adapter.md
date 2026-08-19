# Adapter: voygent

Targets the Voygent MCP server (`voygent-lite`). See `adapters/example-http/adapter.md` for
the general shape every adapter follows — this file only states what voygent does
differently.

## Required hook 1: reach/interact

Reach is the MCP `/mcp` StreamableHTTP driver, not a plain REST call — one turn is one
`tools/call` JSON-RPC request against the target Worker, following the same pattern as
`.claude/skills/voygent/voygent-mcp.sh` in the voygent-lite repo (that script *is* the
reference implementation for this hook; a driver subagent either shells out to it directly or
follows its request/response shape).

- **Targets** — `local` (`http://localhost:8787/mcp`), `staging`
  (`https://staging.voygent.ai/mcp`), `prod` (`https://voygent.ai/mcp` or
  `https://voygent.ai/mcp/u/<user_id>?token=<token>`). `--target` on `persona-test.sh` selects
  one; default to `staging` for anything that isn't an explicitly Neil-authorized prod run.
- **Auth** — bearer token in the `Authorization` header (local/staging) or a `?token=`
  query param (prod per-user URLs). Read from `.dev.vars` (local) or `.env`
  (`STAGING_AUTH_KEYS_BEARER`, staging) exactly as `voygent-mcp.sh` does — never hardcode a
  token in a persona run record or report.
- **One turn** — the persona subagent picks the next voygent tool call that matches what it,
  in character, would ask for or click next (e.g. `get_started`, `manage_trip_goal`,
  `board_pick`), issues it, and records the human-readable result as `appResponse`. Prefer
  calls a real advisor/traveler conversation would produce over calling every tool
  mechanically.
- A tool error (JSON-RPC error, non-2xx, MCP-level `isError`) is a step like any other —
  record it verbatim and let the persona react per its tendencies.

## Required hook 2: done

Same three non-error terminating conditions as `example-http` (goal achieved / persona quits
/ turn cap — 8 turns), plus: a call that would require Neil's own approval (a real payment, a
publish to an external client, a prod write outside `VOYGENT_ALLOW_PROD=1`) ends the run
immediately with `terminatedBy: "guardrail"`, `completed: false` — the driver does not attempt
to work around it.

## Required hook 3: context

```
context: Voygent is a travel-advisor MCP assistant. Users are travel advisors (and, on the
free tier, travelers) building a trip: searching flights/hotels/tours, assembling a Folio
(the client-facing proposal), and walking a Board (compare-and-pick UI) to firm up choices.
Core terms: Trip, Folio, Board, Draft/Final, Preview/Propose/Share/Publish.
```

## Judge override: board dimensions

Voygent's judge subagent scores against **board dimensions**, not the rubric defaults —
`lib/judge.md` is given this override in place of `rubric.md`'s three default dimensions:

- `comprehension` (0–5) — did the app correctly understand what the persona was asking for?
- `elicitation` (0–5) — did the app ask good clarifying questions when it needed to, without
  over-asking?
- `free_surface` (0–5) — did the app surface relevant options/information the persona didn't
  explicitly ask for but needed (gaps, alternatives, caveats)?
- `funnel` (0–5) — did the app move the persona toward a concrete, bookable outcome rather
  than stalling in open-ended chat?

Plus three fields the judge adds to the standard judged-result shape for this adapter (not
part of `lib/normalize.py`'s generic shape — carried through unnormalized to the board
mapper):

- `fabricationCount` (int ≥ 0) — number of times the app stated something as fact that the
  run record shows was false or unverifiable (a price that didn't match, a policy invented on
  the spot). Judge counts these from `steps`/`observations`; never estimate.
- `crossCheckPassed` (bool) — whether anything the app claimed and that mattered to the
  persona's decision was actually verifiable from a second signal in the run record (e.g. a
  quoted price appearing consistently across two steps). `false` if nothing needed
  cross-checking, so this is not a distinct "not applicable" state.
- `terminatedBy` — copied from the run record's own `terminatedBy` (hook 2 above).

Pass threshold override — same shape as `rubric.md`'s default (a boolean function of the
active dimensions), substituting `funnel` for `task_completion` and `comprehension` for
`correctness`:

```
verdict = "pass"  if  funnel >= 3  AND  comprehension != 0
verdict = "fail"  otherwise
```

## Sink: board ingest

After the local report (`sinks/local_report.py`, always written), voygent additionally maps
and posts:

1. `adapters/voygent/map_to_board.py`'s `map_to_board(run_id, date, results, issues)` reshapes
   the judged results (already carrying the board dimensions + the three extra fields above)
   into the exact ingest body `POST /admin/persona/ingest` expects — see that file's docstring
   for the field-by-field contract (verified against voygent-lite prod commit `a58e150c`).
2. `sinks/http_post.py` POSTs that body to `$VOYGENT_HOST/admin/persona/ingest`, bearer
   `$PERSONA_INGEST_TOKEN` (read via `--token-env PERSONA_INGEST_TOKEN`).

Per the graceful-degradation rule in `SKILL.md`: if this POST fails (network error, 404
because the route isn't provisioned yet, bad token), the run still succeeds — the local report
under `runs/<run_id>/report.md` was already written in step 1 and is not rolled back.

## Env vars

See `adapters/voygent/README.md` for the required env vars and the never-commit warning.
