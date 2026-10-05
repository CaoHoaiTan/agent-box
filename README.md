# agent-box

Run AI coding agents (Claude Code, OpenAI Codex CLI) inside isolated Docker
containers with an outbound network allowlist.

> Work in progress. Full documentation is added in a later phase.

## Leak guard

`scripts/check-leaks.sh` scans tracked files for generic secret patterns and,
if present, for terms in a local, git-ignored `.leak-denylist` file (one
case-insensitive term per line).

Install it as a git pre-commit hook:

```bash
ln -s ../../scripts/check-leaks.sh .git/hooks/pre-commit
```
