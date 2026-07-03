---
name: gemini-review
description: Get a second-opinion review of the current diff (or a chosen focus — architecture, security, docs, design, performance, tests) from the Gemini CLI, then present its findings alongside your own analysis. Single-reviewer counterpart to /codex-review and /review-panel; needs the `gemini` CLI installed. Triggers on `/gemini-review [focus]`, "gemini review this", "get a gemini second opinion on this diff".
user_invocable: true
---

# Gemini External Review

You are invoking Gemini CLI (Google's CLI agent) as an external reviewer to get a second opinion.

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

1. **Gather Context** - Collect information about the current project:
   - Read the project's README.md or main documentation if it exists
   - Run `git status` and `git diff --stat` to see current changes
   - Run `git diff` to get the actual diff content (limit to reasonable size)
   - Run `git log --oneline -10` to see recent commits
   - Identify the main technologies (check package.json, Cargo.toml, pyproject.toml, etc.)
   - Note the current working directory and project structure

2. **Prepare the Review Request** - Build a prompt for Gemini that includes:
   - Project name and description
   - Main technologies/stack
   - Summary of recent changes (staged and unstaged)
   - The actual diff or relevant code
   - The specific review focus determined above
   - Ask Gemini to act as a senior engineer/reviewer

3. **Execute Gemini Review** - Run Gemini in plan (read-only) mode:
   ```bash
   gemini --approval-mode plan -o text -p "PROMPT_HERE"
   ```

   Notes on Gemini CLI flags:
   - `--approval-mode plan` — read-only mode, no file modifications
   - `-o text` — plain text output (cleanest for parsing)
   - `-p` — non-interactive prompt mode

4. **Present Results** - After getting Gemini's response:
   - Summarize the key findings
   - Highlight critical issues or concerns
   - Note any disagreements you have with Gemini's assessment
   - Provide your own analysis of whether their suggestions are valid
   - Ask the user if they want to act on any of the suggestions

## Important Notes

- Always use `--approval-mode plan` for safety (read-only)
- If the diff is very large, summarize key changes instead of including everything
- Present both Gemini's opinion AND your own analysis
- Be honest if you disagree with Gemini's assessment

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
