# PLAN.md — `agent-box`

> Implementation plan for Claude Code. Read this whole file before writing any code.
> Work **one phase at a time**. At the end of each phase, run its checkpoint, report results, and **stop and wait for approval** before starting the next phase.

---

## 0. Project summary

`agent-box` is an open-source, reusable setup that runs AI coding agents (Claude Code and OpenAI Codex CLI) inside isolated Docker containers with an outbound network allowlist, so the agent cannot read the host's personal data, credentials, or other projects.

Target users: developers who want to use AI coding agents on both personal and work code without giving the agent access to their whole machine.

Primary platform: macOS on Apple Silicon using Colima. Secondary: Linux with native Docker.

### Core idea

- One image, **two separate boxes** by default: `box-personal` and `box-work`. Each box only sees its own workspace folder and has its own agent login volumes. A compromised agent in one box cannot see the other box's code.
- Containers start as root only to install firewall rules, then all interactive work happens as the unprivileged `node` user, with no `sudo` installed.
- Outbound traffic is denied by default; only domains listed in `config/allowed-domains.txt` are reachable.
- The agent never has SSH keys, GPG keys, or git push credentials. The human reviews and pushes from a clean clone on the host using a safe fetch helper.

---

## 1. Hard rules for the implementer

These apply to every phase. If a task conflicts with a rule, stop and ask.

1. **No identifying information anywhere in the repo.** No employer or company names, no personal names, emails, usernames, GitHub org names, internal hostnames, IPs, or key IDs. Use only generic terms: `personal`, `work`, `company`, `example.com`, `your-org`.
2. **No real secrets.** No API keys, tokens, `.env` files with values. Example files use obvious placeholders (`changeme`, `sk-placeholder`).
3. **Never mount** into any container: `/var/run/docker.sock`, `~/.ssh`, `~/.gnupg`, `~/.gitconfig`, `~/.aws`, `~/.config`, the user's home directory, or any path outside the configured workspace folders.
4. **No `sudo`** in the image. No `--privileged`. No `network_mode: host`.
5. All shell scripts: `#!/usr/bin/env bash`, `set -euo pipefail`, must pass `shellcheck` with no warnings.
6. Dockerfile must pass `hadolint` (justify any ignored rule inline with a comment).
7. Pin versions: base image by tag **and** digest; Codex CLI and Claude Code versions via build `ARG`s with defaults documented in `README.md`.
8. Keep dependencies minimal. Do not add a tool unless a phase requires it.
9. Prefer clear, boring Bash over clever one-liners. Comment the *why*, not the *what*.
10. Do not run destructive commands on the host (`rm -rf` outside the repo, `docker system prune -a`, etc.).

---

## 2. Target repository layout

```
agent-box/
├── README.md
├── SECURITY.md
├── LICENSE                      # MIT
├── .gitignore
├── .env.example
├── Dockerfile
├── docker-compose.yml
├── Makefile                     # thin wrapper around bin/agentbox
├── bin/
│   └── agentbox                 # main CLI (bash)
├── config/
│   ├── allowed-domains.txt      # one domain per line, comments with '#'
│   ├── codex-config.toml        # default Codex config copied into the box
│   └── claude-settings.json     # default Claude Code settings copied into the box
├── scripts/
│   ├── entrypoint.sh            # runs as root: firewall, then sleep
│   ├── init-firewall.sh         # builds iptables/ipset rules
│   ├── verify.sh                # isolation self-test, runs inside a box
│   ├── safe-fetch.sh            # host side: fetch AI branch into a clean clone
│   └── check-leaks.sh           # pre-commit / CI denylist scan
├── docs/
│   ├── macos-colima.md
│   ├── linux.md
│   ├── workflow.md
│   ├── optional-services.md
│   └── troubleshooting.md
├── workspaces/
│   ├── personal/.gitkeep
│   └── work/.gitkeep
└── .github/
    └── workflows/
        └── ci.yml
```

`workspaces/*/` contents (except `.gitkeep`) must be git-ignored.

---

## 3. Phases

### Phase 1 — Repo skeleton and leak guard

**Tasks**
- Create the layout above with empty or stub files.
- `LICENSE` (MIT, holder: `agent-box contributors`).
- `.gitignore`: `workspaces/*/*`, `!workspaces/*/.gitkeep`, `.env`, `.leak-denylist`, OS junk files.
- `.env.example` with:
  ```
  PERSONAL_WORKSPACE=./workspaces/personal
  WORK_WORKSPACE=./workspaces/work
  BOX_CPUS=4
  BOX_MEMORY=4g
  STRICT_DNS=0
  ```
- `scripts/check-leaks.sh`:
  - Reads a **local, git-ignored** file `.leak-denylist` (one case-insensitive term per line). If the file is missing, print a notice and exit 0.
  - Scans all tracked files (`git ls-files`) and fails with file:line output on any match.
  - Also always fails on generic secret patterns: `sk-[A-Za-z0-9]{20,}`, `ghp_[A-Za-z0-9]{20,}`, `github_pat_`, `-----BEGIN .*PRIVATE KEY-----`.
- Document in `README.md` how to install it as a git `pre-commit` hook (`ln -s ../../scripts/check-leaks.sh .git/hooks/pre-commit`).

**Checkpoint**
- `tree` output matches the layout.
- Create a temporary `.leak-denylist` containing a test word, put that word in a scratch tracked file, confirm `check-leaks.sh` fails; remove the word, confirm it passes. Delete the scratch file afterwards.

---

### Phase 2 — Docker image

**Tasks**
- `Dockerfile` based on `node:22-bookworm-slim` (pinned by digest, multi-arch: must build on `linux/arm64` and `linux/amd64`).
- Install only: `git curl ca-certificates iptables ipset dnsutils ripgrep jq zsh less procps openssh-client`. Clean apt lists.
- Install Codex CLI globally via npm at version `ARG CODEX_VERSION`.
- Switch to `node` user and install Claude Code with the official native installer, version controlled by `ARG CLAUDE_CODE_VERSION` if the installer supports pinning; otherwise document that it installs latest.
- Copy `scripts/entrypoint.sh`, `scripts/init-firewall.sh`, `scripts/verify.sh` to `/usr/local/bin/`, mode `755`, owned by root.
- Copy `config/allowed-domains.txt` to `/etc/agent-box/allowed-domains.txt`, owned by root, mode `644`.
- Copy `config/codex-config.toml` and `config/claude-settings.json` to `/etc/agent-box/defaults/`.
- `WORKDIR /workspace`, final `USER root`, `ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]`.
- Confirm `sudo` is **not** present in the final image.

**`config/codex-config.toml` defaults**
```toml
# The container + firewall is the sandbox; Codex's own sandbox may not work inside Docker.
sandbox_mode = "danger-full-access"
approval_policy = "on-request"
```
Add a comment explaining this is only acceptable inside agent-box, never on a host machine.

**`config/claude-settings.json` defaults**: a minimal settings file; no permission bypass by default. Document in `README.md` how a user can opt into skipping permissions inside the box and the trade-off.

**Checkpoint**
- `docker build .` succeeds.
- `docker run --rm --entrypoint sh <image> -c 'command -v sudo || echo no-sudo'` prints `no-sudo`.
- `claude --version` and `codex --version` work as the `node` user.

---

### Phase 3 — Firewall and entrypoint

**`scripts/init-firewall.sh`** requirements
- Read domains from `/etc/agent-box/allowed-domains.txt`, ignoring blank lines and `#` comments.
- Resolve each domain's A records with `dig +short`, keep only IPv4 addresses, add to ipset `agentbox-allowed` (`hash:net`, `-exist`). Warn (do not fail) on domains that resolve to nothing.
- Rules on `OUTPUT`:
  1. Flush existing `OUTPUT` rules and recreate the ipset idempotently (script must be safe to run twice).
  2. Allow loopback.
  3. DNS: if `STRICT_DNS=1`, allow port 53 only to Docker's embedded resolver `127.0.0.11`; else allow port 53 to any destination. Document the DNS-exfiltration trade-off.
  4. Allow `ESTABLISHED,RELATED`.
  5. Allow destinations in `agentbox-allowed`.
  6. If env `EXTRA_ALLOWED_CIDRS` is set (comma-separated), allow those CIDRs (used by optional services in Phase 8).
  7. Default policy `DROP`.
- IPv6: set `ip6tables -P OUTPUT DROP` (tolerate absence of ip6tables).
- Self-test at the end: request to `https://example.com` must fail within 5 s; if it succeeds, print `FIREWALL FAIL` and exit non-zero. Print `Firewall OK` on success.

**`config/allowed-domains.txt`** initial content, grouped with comments:
```
# Claude Code
api.anthropic.com
claude.ai
console.anthropic.com
statsig.anthropic.com
# OpenAI Codex
api.openai.com
auth.openai.com
chatgpt.com
# Package registries
registry.npmjs.org
# GitHub (read-only: the box has no credentials)
github.com
api.github.com
codeload.github.com
objects.githubusercontent.com
```

**`scripts/entrypoint.sh`**
- Must run as root. Run `init-firewall.sh`; if it fails, exit non-zero so the container does not stay up unprotected.
- On first start, copy defaults into the `node` home if absent: `/etc/agent-box/defaults/codex-config.toml` → `/home/node/.codex/config.toml`, `claude-settings.json` → `/home/node/.claude/settings.json`. Fix ownership to `node`.
- `exec sleep infinity`.

**Checkpoint**
- Container logs show `Firewall OK`.
- Running `init-firewall.sh` twice in a row succeeds both times.
- As `node`: `iptables -L` fails with a permission error.

---

### Phase 4 — Compose with two boxes

**`docker-compose.yml`** requirements
- A shared YAML anchor `x-box` with:
  - `build: .`
  - `cap_drop: [ALL]`, `cap_add: [NET_ADMIN, NET_RAW]`
  - `security_opt: ["no-new-privileges:true"]`
  - `cpus: ${BOX_CPUS:-4}`, `mem_limit: ${BOX_MEMORY:-4g}`, `pids_limit: 512`
  - `environment: STRICT_DNS: ${STRICT_DNS:-0}`
  - `init: true`
- Service `box-personal`: mounts `${PERSONAL_WORKSPACE:-./workspaces/personal}:/workspace` plus named volumes `personal-claude:/home/node/.claude`, `personal-codex:/home/node/.codex`.
- Service `box-work`: same pattern with `WORK_WORKSPACE`, `work-claude`, `work-codex`.
- Each box on its **own** network so the two boxes cannot reach each other.
- A loud comment block listing the forbidden mounts from Hard Rule 3.

**Checkpoint**
- `docker compose config` renders with no warnings.
- `docker compose up -d` starts both boxes; both log `Firewall OK`.
- From `box-personal`, `ls /workspace` shows only the personal workspace; same for `box-work`.
- `box-personal` cannot reach `box-work` by container name.

---

### Phase 5 — `bin/agentbox` CLI and verify script

**`bin/agentbox`** subcommands (bash, with `--help` for each):

| Command | Behavior |
|---|---|
| `agentbox up [box]` | `docker compose up -d` for one or all boxes, then tail until `Firewall OK` or failure |
| `agentbox down [box]` | Stop, keep volumes |
| `agentbox shell <box>` | `docker compose exec -u node <box> zsh` |
| `agentbox verify <box>` | Run `verify.sh` inside the box as `node` |
| `agentbox refresh-firewall <box>` | Re-run `init-firewall.sh` as root (IPs behind CDNs change) |
| `agentbox reset <box>` | Confirm with a typed prompt, then remove the box and its named volumes (wipes agent logins) |
| `agentbox fetch <box> <repo> <branch> <clean-clone-path>` | Calls `scripts/safe-fetch.sh` |

`<box>` accepts `personal` or `work`, mapped to service names.

**`scripts/verify.sh`** (runs inside a box as `node`) prints PASS/FAIL per check and exits non-zero on any FAIL:
1. `https://api.anthropic.com` reachable.
2. `https://api.openai.com` reachable.
3. `https://example.com` blocked.
4. No `~/.ssh` content from the host, no `/Users` or `/home/<other>` host paths visible.
5. `/var/run/docker.sock` does not exist.
6. `iptables -L` fails (not root).
7. `sudo` not found.
8. `/workspace` is writable.

**`Makefile`**: targets `up`, `down`, `shell-personal`, `shell-work`, `verify`, `lint`, `leaks` delegating to `bin/agentbox` and scripts.

**Checkpoint**
- `bin/agentbox verify personal` and `bin/agentbox verify work` both report all PASS.
- `bin/agentbox reset personal` refuses without the typed confirmation.

---

### Phase 6 — Safe review and push workflow

**Problem to solve:** the agent can write to `.git/hooks` and `.git/config` (for example `core.sshCommand`, `core.fsmonitor`) in repos inside the workspace. Running `git` directly in that folder on the host could execute attacker-controlled code with the user's credentials.

**`scripts/safe-fetch.sh <workspace-repo-path> <branch> <clean-clone-path>`**
- Validate both paths exist and are git repos; refuse if they are the same directory.
- Run git **only inside the clean clone**, fetching from the workspace repo by path:
  `git -C <clean-clone> -c core.hooksPath=/dev/null fetch <workspace-repo> <branch>:<branch>`
- Never `cd` into or run git with `-C` on the workspace repo.
- After fetch, print a summary: commit list (`git log --oneline main..<branch>`), changed files, and a **warning list** of risky changed paths: `package.json`, lockfiles, `*.sh`, `Makefile`, `Dockerfile`, `.github/**`, `.husky/**`, `.vscode/**`, `.claude/**`, `.codex/**`.
- Do not push. Print the exact commands the user should run to review and push manually.

**`docs/workflow.md`** explains end to end:
1. Clone a repo **on the host** into the box's workspace folder (host credentials stay on host).
2. Create an `ai/<task>` branch inside the box; run `claude` or `codex` there.
3. Agent commits locally only.
4. On the host, use `agentbox fetch` into a separate clean clone, review the diff, push from the clean clone (commits signed with the user's own keys).
5. Never open the workspace folders with a host editor in normal mode; use VS Code "Dev Containers: Attach to Running Container" instead.
6. Never copy real `.env` files or production credentials into a workspace; treat anything in a box as readable by the agent and by the model provider.

**Checkpoint**
- With a scratch repo: make a commit inside a box on `ai/test`, plant a hook file in that workspace repo's `.git/hooks/` that would create a marker file, run `agentbox fetch`, and confirm the branch arrives in the clean clone **and the marker file was never created**. Clean up afterwards.

---

### Phase 7 — Documentation

**`README.md`** sections:
1. What it is, in three sentences.
2. What it protects against / what it does **not** (link to `SECURITY.md`).
3. Requirements (macOS + Colima, or Linux + Docker Engine).
4. Quick start (copy-paste commands, under 10 steps): clone, `cp .env.example .env`, `make up`, `make verify`, `agentbox shell work`, log in (`claude`, `codex login --device-auth`).
5. Daily usage.
6. Adding allowed domains, then `agentbox refresh-firewall`.
7. Version pinning and upgrading.
8. FAQ.

**`SECURITY.md`**: threat model.
- Protects: host files outside workspaces, host credentials, other workspace, arbitrary outbound network, privilege changes inside the box.
- Does not protect: code and prompts are sent to the model provider; prompt injection can still send data to allowlisted domains; DNS exfiltration when `STRICT_DNS=0`; container/VM escape bugs (keep runtime updated); anything the user puts into a workspace (secrets included).
- How to report vulnerabilities (placeholder contact, e.g. GitHub private security advisories).

**`docs/macos-colima.md`**
- `brew install colima docker docker-compose`
- `colima start --vm-type vz --cpu 4 --memory 8 --disk 60 --mount <repo>/workspaces:w`
- **Verification step:** `colima ssh -- ls /Users` must not list the user's home. If it does, explain how to restrict mounts via `colima start --edit`.
- Note: disable other Docker runtimes or switch context with `docker context use colima`.

**`docs/linux.md`**: native Docker shares the host kernel (weaker than a VM); recommend rootless Docker or running inside a VM for stronger isolation.

**`docs/troubleshooting.md`**: agent cannot connect (check logs, add domain, refresh firewall); OAuth callback fails (use `codex login --device-auth`, paste-code flow for Claude Code); `ipset` missing in kernel; Apple Silicon build issues.

**Checkpoint**
- A person following only `README.md` quick start on a clean machine reaches `make verify` all PASS (simulate by following the steps literally).
- `check-leaks.sh` passes.

---

### Phase 8 — Optional: local backing services (Postgres, Redis)

Only implement after Phases 1–7 are approved.

- Add a compose profile `services` with `postgres:16` and `redis:7` (pinned), credentials only from `.env` with placeholder defaults.
- Put each box's services on an `internal: true` network attached only to that box (personal services are not reachable from the work box and vice versa).
- Pass that network's subnet to the box via `EXTRA_ALLOWED_CIDRS`; fix subnets explicitly in compose so the CIDR is known.
- `docs/optional-services.md` explains usage and warns: never point a box at real or shared company databases.

**Checkpoint**
- From `box-work` with the profile enabled: `pg_isready`-style check to its Postgres succeeds; `box-personal` cannot reach it; `example.com` is still blocked.

---

### Phase 9 — CI

**`.github/workflows/ci.yml`** on push and pull request:
1. `shellcheck` on `bin/agentbox` and `scripts/*.sh`.
2. `hadolint Dockerfile`.
3. `scripts/check-leaks.sh` (generic secret patterns only; the denylist file is local and absent in CI).
4. Build the image for `linux/amd64` and `linux/arm64` via buildx (arm64 build only, no run, if emulation is slow).
5. Run one box on the amd64 runner with `NET_ADMIN`, wait for `Firewall OK`, run `verify.sh` with the host-path checks adapted for CI.

Do not use third-party actions beyond official `actions/*` and `docker/*` ones; pin them by commit SHA.

**Checkpoint**
- Workflow file passes `actionlint` if available; otherwise explain how it was validated.

---

## 4. Definition of done

- All phase checkpoints pass and were reported.
- `make lint`, `make leaks`, and `bin/agentbox verify` for both boxes pass.
- No identifying information in any tracked file (Hard Rule 1), confirmed by `check-leaks.sh` with the user's local denylist.
- README quick start works end to end.

## 5. Out of scope

- GUI apps, browser automation, or MCP servers inside the box.
- Windows hosts.
- Local LLMs.
- Automatic pushing or PR creation from inside a box.
