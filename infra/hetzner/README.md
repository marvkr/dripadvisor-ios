# infra/hetzner

Production infra targets a single Hetzner box (locked decision — see top-level
README "Backend" section). Path will hold:

- `cloud-init.yaml` — first-boot setup (caddy, postgres, redis, minio, systemd units)
- `terraform/` — when Hetzner Cloud Terraform provider replaces hand-rolled provisioning
- `caddy/Caddyfile` — TLS termination + reverse proxy
- `systemd/` — service units for `dripadvisor-backend.service`, `dripadvisor-river-worker.service`
- `backups/` — `pg_dump` cron → R2 + restore drill scripts

Not committed yet — current backend runs locally via `infra/docker-compose.yml`.
