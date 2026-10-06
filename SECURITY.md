# Security model

Treat workspace code, agent output and fetched commits as untrusted. The host, clean review clone, runtime and root-owned image files are trusted. Run agents through agentbox shell as node, never a root shell.

## Intended boundaries

- Only the configured workspace is bind-mounted. Never mount host SSH/GPG/cloud/Git configuration, home or Docker socket. Restrict Colima VM mounts too.
- Personal/work code and agent logins use separate mounts, volumes and networks. Optional databases also have separate private networks.
- Root installs default-deny OUTPUT rules and starts an idle process. The node agent cannot edit root-owned firewall files or change iptables. Capabilities are limited; no-new-privileges prevents gaining privileges through setuid programs. There is no sudo.
- IPv4 destinations are allowlisted by resolved IP; IPv6 OUTPUT is dropped. Startup exits on firewall failure. No host Git push credentials are supplied.

## Limits

Code, prompts and anything put in a workspace can be read by the agent and sent to the model provider. Prompt injection can exfiltrate through allowed destinations, registries or shared CDN IPs. The firewall does not restrict HTTP methods or make GitHub read-only: lack of credentials is the push boundary.

DNS exfiltration is possible with STRICT_DNS=0. Strict mode restricts direct resolver access but Docker still forwards arbitrary queries. Established connections remain permitted during refresh. Allowed providers are not trusted recipients for secrets.

Runtime/VM escape bugs, kernel vulnerabilities, host malware and runtime administration are outside these boundaries. Keep Docker, Colima and Git updated. Native Linux Docker shares the host kernel; a dedicated VM adds a boundary. Root/NET_ADMIN and the host Docker administrator remain trusted.

Agents can modify Git hooks/config, editor tasks, dependencies and build scripts. Fetch into a trusted independent clone and review before checkout, builds or editor use. The helper still parses untrusted Git data; it does not protect against Git implementation vulnerabilities. Fetched commits retain their author metadata and signatures.

Do not put real .env files, production credentials, shared company databases or personal documents into a workspace. Optional services hold only local development data with disposable placeholder credentials.

## Reporting

Use the repository's GitHub **Security → Advisories → Report a vulnerability** when private reporting is enabled. Otherwise contact maintainers privately using the repository's advertised contact channel. Do not publish credentials or real company details in an issue.
