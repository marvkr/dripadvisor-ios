# infra/hetzner

Production deploy for the single Hetzner box (locked decision — see top-level
README "Backend" section + `docs/writeup.md`). One Go binary + Postgres +
Redis + MinIO + Caddy, all on one host, talking over an internal Docker
network.

```
infra/hetzner/
├── docker-compose.yml   prod stack (backend, postgres, redis, minio, caddy)
├── Caddyfile            TLS + reverse proxy on api.dripadvisor.app
├── env.example          template for /etc/dripadvisor/env
├── deploy.sh            one-shot ssh + git pull + build + migrate + up -d
└── README.md            this file
```

## First-run setup (~10 min)

On your laptop:

```bash
# Generate the secrets you'll need
openssl rand -base64 48      # JWT_SIGNING_SECRET
openssl rand -base64 32      # PG_PASSWORD
openssl rand -hex 16         # S3_ACCESS_KEY
openssl rand -hex 32         # S3_SECRET_KEY
```

Point a DNS A record `api.dripadvisor.app → 5.78.141.236` (Caddy needs it
for Let's Encrypt).

SSH into the box:

```bash
ssh -i ~/.ssh/id_ed25519_hetzner root@5.78.141.236

apt-get update
apt-get install -y ca-certificates curl git make
curl -fsSL https://get.docker.com | sh

mkdir -p /opt/dripadvisor /etc/dripadvisor
git clone https://github.com/marvkr/dripadvisor-ios.git /opt/dripadvisor
cp /opt/dripadvisor/infra/hetzner/env.example /etc/dripadvisor/env
chmod 600 /etc/dripadvisor/env
$EDITOR /etc/dripadvisor/env     # paste in the secrets you generated
```

Back on your laptop:

```bash
make deploy
```

That runs `infra/hetzner/deploy.sh` → ssh in, git pull, build the backend
image, run migrations, bring the stack up. Idempotent.

## Ongoing deploys

After every commit you want live:

```bash
git push origin main && make deploy
```

Two minutes from `git push` to live, including DB migration and zero-downtime
container swap.

## What runs on the box

| Service  | Port    | Exposed?    | Purpose                                     |
|----------|---------|-------------|---------------------------------------------|
| caddy    | 80, 443 | public      | TLS termination + reverse proxy             |
| backend  | 8080    | internal    | Go API + River workers (same process)       |
| postgres | 5432    | internal    | Source of truth (also River queue tables)   |
| redis    | 6379    | internal    | Per-chat seq, pub/sub, typing indicators    |
| minio    | 9000    | internal    | S3-compatible blob storage (R2 swap later)  |

The 4 internal services share `dripnet` Docker network — backend talks to
them via service names. Nothing but Caddy is reachable from the public
internet.

## Verifying

```bash
curl https://api.dripadvisor.app/healthz
# {"ok": true}
```

iOS:

```swift
// apps/ios/DripAdvisor/Services/APIClient.swift
baseURL: URL = URL(string: "https://api.dripadvisor.app")!
```

(Currently hard-coded to `localhost:8080` for sim dev — flip when ready.)

## Backups

Locked decision: nightly `pg_dump` to Cloudflare R2 with rehearsed restore
drills (README "Backend" section). Not yet wired in this folder. TODO:
`infra/hetzner/cron/pg-dump-r2.sh` + `crontab` entry.

## Scaling

Stay on this single-VPS layout until exhausted. Per locked decision:

1. **Vertical** — bump CCX13 → CCX23 → CCX43 → AX162-R inside Hetzner.
   Zero code changes, ~5-min downtime per resize.
2. **Read replicas** — add a Postgres streaming replica on a second Hetzner
   box; route reads there.
3. **Horizontal** — only at AX162-R saturation (~5–10M DAU). Consistent-hash
   on `user_id` across multiple primary nodes.

See `docs/writeup.md` for cost / scaling math and the rationale for staying
on VPS rather than moving to managed Postgres.
