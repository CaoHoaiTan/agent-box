# Linux

Install Docker Engine and Compose/Buildx using [official distribution instructions](https://docs.docker.com/engine/install/). Install Bash, Git, Make, jq and realpath from your package manager. Confirm docker info, docker compose version and docker buildx version work, then follow README quick start.

Native Docker shares the host kernel. Prefer a dedicated VM sharing only workspace folders for stronger isolation. Rootless Docker reduces daemon privileges, but this setup also needs working NET_ADMIN, iptables/ipset and Docker DNS. Run make verify; if those features fail under rootless Docker, use Docker inside a VM. Do not grant privileged mode, a host network or socket mount to fix it.

The image's node user has UID/GID 1000. Bind-mounted workspaces must be writable by that UID. Use matching ownership or a targeted ACL for only the workspace directories, not a writable home mount. Docker initializes named login volumes from node-owned image defaults.

Host Docker group membership grants broad daemon control; restrict it to trusted host users. Never share host agent/Git/cloud credentials. See [security](../SECURITY.md).
