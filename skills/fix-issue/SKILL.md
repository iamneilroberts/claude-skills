---
name: fix-issue
description: |
  Take a GitHub issue and actually resolve it end to end — read the issue, reproduce it,
  fix it in an isolated branch with a test, verify, and open a PR that closes the issue.
  The counterpart to /idea (which files issues): /idea captures, /fix-issue clears. Works
  off `gh` in whatever repo you're in. Triggers on `/fix-issue <number|url>`, "fix issue
  #N", "resolve this github issue", "pick up and fix issue N".
user_invocable: true
args: "<issue-number | issue-url> — the GitHub issue to resolve"
---

# /fix-issue — resolve a GitHub issue, branch → fix → PR

Turns a filed issue into a merge-ready change: understand, reproduce, fix with a test, verify, and
open a PR that closes the issue. Never pushes or opens a PR without showing the diff first.

## Steps

1. **Load the issue.** Resolve the arg to an issue number (bare number or full URL). Read it and
   its discussion:
   ```bash
   gh issue view <n> --comments
   ```
   Extract the actual problem, repro steps, acceptance criteria, and linked PRs/commits. If the
   issue is vague or already closed, say so and ask before proceeding — don't guess at scope.

2. **Confirm scope (one beat).** State in one or two lines what you're changing and what "done"
   means for this issue. If the issue is really several changes, do the smallest coherent one and
   note the rest. Don't expand scope beyond what the issue asks.

3. **Isolate the work.** Create a dedicated branch/worktree so this doesn't collide with other
   work. Prefer the `branch` skill if it's installed (`/branch fix-<n>-<slug>`); otherwise `git
   worktree add`, or at minimum `git checkout -b fix-<n>-<slug>`. Check `git status` first — never
   start on top of another session's uncommitted WIP.

4. **Reproduce before fixing** (for a bug). Write a failing test that captures the issue, or
   otherwise demonstrate the broken behavior concretely — a fix with no reproduction is a guess.
   For a feature/chore, write the test that encodes the acceptance criteria. (TDD applied to the
   issue: red first.)

5. **Fix it.** Make the smallest change that turns the test green. Touch only what the issue
   needs — don't reformat or refactor adjacent code on the way past.

6. **Verify — evidence, not assertion.** Run the real commands and read the output: the new test
   passes, the existing suite still passes, typecheck/lint clean, and (if relevant) a manual check
   of the behavior the issue described. If anything fails, keep working — do not open the PR.

7. **Review (optional but recommended).** Run `/codex-review` or `/review-panel` if installed, and
   address anything critical/important before opening the PR. `/curate`, if installed, can confirm
   the "fixed" claim against actual repo state.

8. **Open the PR (with your confirmation).** Show the diff summary, then open a PR whose body
   **closes the issue**:
   ```bash
   gh pr create --title "<imperative summary> (closes #<n>)" \
     --body "Closes #<n>\n\n<what changed and why, one short paragraph + the verification you ran>"
   ```
   Use `Closes #<n>` so merging the PR auto-closes the issue. Don't push or create the PR until
   you've shown the change and gotten a go-ahead.

9. **Report.** One line: branch, PR URL, and the issue it closes. Note any follow-up the issue
   implied but you consciously left out of scope.

## Guardrails

- **Reproduce first, or say you couldn't.** If you can't reproduce a bug, don't ship a speculative
  fix — report what you tried and ask for more detail.
- **Scope discipline.** One issue, one focused change. File anything extra you notice with `/idea`
  rather than dragging it into this PR.
- **No silent success.** Every "passes / fixed / done" must be backed by a command you ran this
  session and its output.
