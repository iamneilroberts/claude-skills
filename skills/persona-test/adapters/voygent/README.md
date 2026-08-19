# voygent adapter — setup

Required env vars to run this adapter for real (not needed for the default, non-live test
suite — see `tests/run_integration.sh`):

| Var | Purpose |
|---|---|
| `VOYGENT_HOST` | Base URL of the target Voygent Worker for the sink POST, e.g. `https://staging.voygent.ai` or `https://voygent.ai`. |
| `AUTH_KEYS` (local) / `STAGING_AUTH_KEYS_BEARER` (staging) / a per-user `?token=` (prod) | MCP bearer credential for the `reach` hook — read the same way `.claude/skills/voygent/voygent-mcp.sh` does, from `.dev.vars` or `.env` in the voygent-lite repo. |
| `PERSONA_INGEST_TOKEN` | Bearer token for the sink's `POST $VOYGENT_HOST/admin/persona/ingest` call (read via `sinks/http_post.py --token-env PERSONA_INGEST_TOKEN`). |

**Never commit any of these.** They belong in a gitignored `.env` / `.dev.vars`, exported into
the shell environment, or supplied by whatever secret store the calling session already uses
for voygent-lite credentials — never written into a persona run record, a judged result, a
report, or this adapter directory.

## The ingest route is inert until provisioned

`POST /admin/persona/ingest` on the Worker returns **404** until `PERSONA_INGEST_TOKEN` is set
as a secret on that Worker (`npx wrangler secret put PERSONA_INGEST_TOKEN` in voygent-lite).
Until then, the sink step of a voygent-adapter run will fail — by design, this is a
**graceful** failure per `SKILL.md`'s degradation rules: the local report
(`runs/<run_id>/report.md`) is written first and is unaffected, only the board-ingest sink
step reports the failure back to the user.
