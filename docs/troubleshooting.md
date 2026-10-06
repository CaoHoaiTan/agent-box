# Troubleshooting

## Connectivity

```bash
docker compose ps -a
docker compose logs box-work
bin/agentbox refresh-firewall work
bin/agentbox verify work
```

Unresolved domains warn and are omitted. Check with dig +short api.openai.com A in the box. CDN addresses change; refresh re-resolves the image's allowlist. To add a host, edit config/allowed-domains.txt and run bin/agentbox up to rebuild/recreate. Keep the list narrow.

Firewall OK proves example.com is blocked; verify also checks provider connectivity. HTTP 401/403 can pass. Neither confirms account/model access. Strict DNS needs Docker's embedded resolver on user-defined networks; use Compose.

## OAuth callback

Run codex login --device-auth in the box and complete the link/code on the host. Enable device login in account settings or ask your workspace admin if necessary; [official OpenAI guidance](https://learn.chatgpt.com/docs/auth).

Run claude, open its printed URL manually and paste the browser code at the terminal prompt; [Claude authentication](https://code.claude.com/docs/en/authentication). No host credential mount or callback port is needed.

## Kernel firewall support

The host/VM kernel must support ipset and iptables/nftables. Containers need NET_ADMIN/NET_RAW. Ask the Linux runtime administrator to enable required modules, or update/restart Colima. Startup must stop if setup fails. Do not bypass it with privileged mode or extra capabilities. Re-run make verify.

## Apple Silicon

Use native linux/arm64 with current Docker/Colima and Buildx. The base digest is a multi-architecture index; Claude's native installer selects the build architecture. Diagnose with docker buildx build --platform linux/arm64 .; amd64 emulation is slower and requires QEMU/binfmt. Keep version/digest pins.

## Permissions

On Linux, grant workspace access only to UID 1000; [Linux setup](linux.md). Runtime root intentionally lacks CHOWN/DAC_OVERRIDE, so root-owned or otherwise malformed login volumes can stop startup. agentbox reset removes only the selected box's logins after typed confirmation and keeps workspace data. To retain logins, repair the known volume offline through trusted host Docker administration instead.

## Fetch

The clean clone must be outside both workspaces, independent and have local main. Linked source worktrees and .git symlinks are refused. Git refuses fetching over a checked-out destination branch or a non-fast-forward update. Review existing changes before choosing another AI branch; the helper never force-updates. Do not run host Git in the source. [Workflow](workflow.md).

## Optional network conflicts

If a fixed subnet overlaps Docker/VPN networks, set distinct unused PERSONAL_SERVICES_SUBNET and WORK_SERVICES_SUBNET in .env and recreate. Those values configure both private networks and their matching firewall allowances. [Optional services](optional-services.md).
