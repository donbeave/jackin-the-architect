# PR workflow inside The Architect

Reference for which Claude Code command to run at which point in a PR's life.

## When to use which review command

| Command | What it does | When to run |
|---|---|---|
| `/review` | Single-agent comprehensive PR review (the simpler one). Reads diff, returns one prose review with critical / important / suggestions. | Quick first pass on a small or medium PR. Fast, low token cost. |
| `/pr-review-toolkit:review-pr` | Spawns 5+ specialized agents in parallel: code reviewer, comment analyzer, test analyzer, silent-failure hunter, type-design analyzer, simplifier. Each returns its own findings. | Big PR, or one you care about. Catches things one-agent review misses. Higher token cost. |
| `/simplify` | Spawns 3 agents on changed files: code reuse, code quality, efficiency. Auto-applies fixes after aggregating findings. | Right after writing a feature, before opening a PR — or on an already-open PR to clean up. |
| `/autofix-pr` | Auto-applies review feedback as commits on the PR branch. | After a `/review` or `/pr-review-toolkit:review-pr` run when you want findings turned into commits without typing each fix. |

## Recommended flow on a feature PR

1. Write the feature. Push the first commit and open the PR.
2. `/simplify` — clean up reuse / quality / efficiency before any reviewer looks at it.
3. `/pr-review-toolkit:review-pr` on the cleaned PR — comprehensive multi-agent review.
4. Address critical and important findings (manually, or with `/autofix-pr` for the mechanical ones).
5. Verify locally per the PR body's "Verify locally" section.
6. Operator review.
7. `merge it` — Claude runs `gh pr merge --squash`.

## Don't run multiple reviews in series on the same diff

If `/pr-review-toolkit:review-pr` found nothing critical, a follow-up `/review` will not catch new things — same diff, same docs, smaller agent. Run again only after the diff changes.

## Common slash commands by source

| Command | Source |
|---|---|
| `/review` | `code-review` plugin (claude-plugins-official) |
| `/pr-review-toolkit:review-pr`, `/pr-review-toolkit:code-reviewer`, etc. | `pr-review-toolkit` plugin |
| `/simplify` | built-in skill |
| `/autofix-pr` | `pr-review-toolkit` plugin (when present) |
| `/commit-commands:commit`, `/commit-commands:commit-push-pr`, `/commit-commands:clean_gone` | `commit-commands` plugin |
| `/feature-dev:feature-dev` | `feature-dev` plugin (guided feature dev with codebase understanding) |
| `/claude-md-management:revise-claude-md` | `claude-md-management` plugin (audit / improve CLAUDE.md) |
| `/jackin-dev:release`, `/jackin-dev:release-notes`, `/jackin-dev:release-check` | `jackin-dev` plugin (release flow for the jackin Rust CLI) |
| `/caveman ultra` / `/caveman full` / `/caveman lite` | `caveman` plugin (verbosity mode) |

## Plugin troubleshooting

When a plugin or MCP server status shows degraded in the launch banner:

| Plugin / MCP | Fix |
|---|---|
| `caveman-shrink` MCP fails to register | Restart the agent, or run `claude mcp list` to see the registration state. The caveman plugin still works without the shrink MCP — only the token-stat reporting subset is degraded. |
| `github` plugin → `github` MCP fails | Re-auth on the host: `gh auth login`, then restart the agent. The plugin reads `gh`'s token; if `gh`'s token is invalid or scoped wrong, the MCP fails to connect. |
| `shellfirm`, `tirith` MCPs | Connected by default. For `tirith`, remember `export TIRITH=0` before pasting verify-locally output that contains expected-failure tokens. |

## TL;DR — picking a command on the spot

- "Just review my PR" → `/review`
- "Thorough review before merge" → `/pr-review-toolkit:review-pr`
- "Clean up code I just wrote" → `/simplify`
- "Apply review findings as commits" → `/autofix-pr`
- "Make a commit" → `/commit-commands:commit`
- "Open a PR" → `/commit-commands:commit-push-pr`
- "Cut a release" → `/jackin-dev:release`
