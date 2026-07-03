---
name: gemini-review
description: Get a second-opinion review of the current diff (or a chosen focus — architecture, security, docs, design, performance, tests) from the Gemini CLI, then present its findings alongside your own analysis. Single-reviewer counterpart to /codex-review and /review-panel; needs the `gemini` CLI installed. Triggers on `/gemini-review [focus]`, "gemini review this", "get a gemini second opinion on this diff".
user_invocable: true
---

# Gemini External Review

Invoke the Gemini CLI (Google's CLI agent) as an external reviewer for a second opinion.

**Arguments:** `$ARGUMENTS`

## Determine Review Type

Parse `$ARGUMENTS` to determine the review focus. If empty, default to `code`.

| Argument | Focus |
|----------|-------|
| *(empty)* | Code review — bugs, security, quality, performance |
| `code` | Code review — bugs, security, quality, performance |
| `architecture` or `arch` | Architecture — structure, patterns, separation of concerns, scalability |
| `security` or `sec` | Security audit — vulnerabilities, auth issues, data exposure, OWASP |
| `docs` | Documentation — accuracy, completeness, clarity, examples |
| `design` | Design review — API design, naming, abstractions, DX |
| `performance` or `perf` | Performance — bottlenecks, memory, queries, caching |
| `test` or `tests` | Test review — coverage, edge cases, test quality, flaky tests |
| Anything else | Use the argument text as a custom review prompt/focus |

## Your Task

1. **Gather context:**
   - Read the project's README or main docs if present.
   - Run `git status`, `git diff --stat`, `git diff` (staged + unstaged; keep it reasonable size),
     and `git log --oneline -10`.
   - Identify the stack (package.json, Cargo.toml, pyproject.toml, etc.) and note project structure.

2. **Prepare the review request** — build a prompt for Gemini with: project name/description,
   stack, summary of recent changes, the actual diff/relevant code, the review focus, and an
   instruction to act as a senior engineer/reviewer.

3. **Execute the review** in plan (read-only) mode:
   ```bash
   gemini --approval-mode plan -o text -p "PROMPT_HERE"
   ```
   Flags: `--approval-mode plan` = read-only, no file modifications · `-o text` = plain text
   output (cleanest to parse) · `-p` = non-interactive prompt mode.

4. **Present results** — summarize key findings, highlight critical issues, note any
   disagreements with Gemini's assessment, give your own take on whether the suggestions are
   valid, and ask the user if they want to act on any of them.

## Important Notes

- Always use `--approval-mode plan` — read-only, no exceptions.
- If the diff is very large, summarize key changes instead of including everything.
- Present both Gemini's opinion and your own analysis; say so if you disagree.

## Prompt Template

Adapt the review questions based on the review type determined above.

```
You are reviewing [PROJECT_NAME], a [DESCRIPTION].
Tech stack: [TECHNOLOGIES]

Recent commits:
[GIT LOG]

Current changes:
[GIT DIFF or relevant code]

Review focus: [REVIEW_TYPE]

[TYPE-SPECIFIC QUESTIONS based on the table above]

Be direct and critical. This is a real review, not a validation.
```

Now gather the context and execute the Gemini review.
