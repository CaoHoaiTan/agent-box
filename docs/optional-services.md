# Optional Postgres and Redis

Use only disposable local development data. Never point a box at real or
shared company databases, production services or replicas containing secrets.
Anything in these databases is readable and writable by its box's agent.

Enable all four services and start/wait for the boxes:

```bash
COMPOSE_PROFILES=services bin/agentbox up
docker compose --profile services up -d --wait personal-postgres personal-redis work-postgres work-redis
```

The CLI starts both boxes and enabled-profile services; the second command
waits for service health checks. `agentbox up work` selects only the work box;
start its optional peers explicitly with Compose when using that form.
To have `docker compose up` include them
by default, export `COMPOSE_PROFILES=services` in your host shell. Base usage
without that profile starts only the two boxes.

| Box | Postgres host:port | Redis host:port |
|---|---|---|
| personal | personal-postgres:5432 | personal-redis:6379 |
| work | work-postgres:5432 | work-redis:6379 |

Postgres uses database/user `agentbox`. Set each box's own
`PERSONAL_POSTGRES_PASSWORD`, `WORK_POSTGRES_PASSWORD`, `PERSONAL_REDIS_PASSWORD`
and `WORK_REDIS_PASSWORD` in the host `.env`; examples are `changeme`. Do not
reuse host/production credentials. Redis requires authentication. Your app in
the box needs the corresponding development password; do not copy the whole
host `.env` into the workspace. Compose config/inspect can show these values,
so do not paste their output publicly when using customized passwords.

The services use tag-and-digest-pinned Postgres 16 and Redis 7, named data
volumes and no published host ports. Each service is on its own box's
`internal: true` network. Boxes also retain separate outbound networks with
explicit default gateways. The other box cannot resolve or reach these
services; no shared database network is used. See
[Docker networking](https://docs.docker.com/compose/how-tos/networking/).

`PERSONAL_SERVICES_SUBNET` and `WORK_SERVICES_SUBNET` fix the two private IPv4
subnets. Compose passes only the matching subnet to that box's
`EXTRA_ALLOWED_CIDRS` firewall allowance. Keep them distinct and unused by
existing Docker/VPN networks. Boxes attach to their empty private network even
without the profile; enabling services adds only the intended service peers.

Check health with `docker compose --profile services ps`, and run `make verify`
to confirm providers still work and example.com remains blocked. Clients can
use the DNS names above; no database client packages are added to the box.

`agentbox down` stops boxes only. Stop services too with
`docker compose --profile services down`; this retains all named data/login
volumes. Database credentials in an existing Postgres volume are not changed
by editing `.env`; update them inside that development database or recreate
only its disposable data volume through trusted host Docker administration.
`agentbox reset` affects agent login volumes, not databases. Avoid `down -v`
unless you intend to delete both boxes' login and database data.
