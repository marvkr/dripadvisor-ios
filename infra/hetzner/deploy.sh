#!/usr/bin/env bash
# One-shot deploy: ssh in, git pull, rebuild backend image, run migrations,
# bring stack up. Idempotent — safe to re-run.
#
# First-run prerequisites on the box (run once manually):
#   apt-get update && apt-get install -y ca-certificates curl git make
#   curl -fsSL https://get.docker.com | sh
#   mkdir -p /opt/dripadvisor /etc/dripadvisor
#   git clone https://github.com/marvkr/dripadvisor-ios.git /opt/dripadvisor
#   cp /opt/dripadvisor/infra/hetzner/env.example /etc/dripadvisor/env
#   $EDITOR /etc/dripadvisor/env             # fill secrets
#   ln -s /etc/dripadvisor/env /opt/dripadvisor/.prod.env
#   # Point DNS A record api.dripadvisor.app -> this box, then:
#   bash /opt/dripadvisor/infra/hetzner/deploy.sh

set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-root@5.78.141.236}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_hetzner}"
REPO_DIR="${REPO_DIR:-/opt/dripadvisor}"
ENV_FILE="${ENV_FILE:-/etc/dripadvisor/env}"
COMPOSE_FILE="infra/hetzner/docker-compose.yml"

ssh_exec() {
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new "$REMOTE_HOST" "$@"
}

main() {
    echo "==> 1/4  git pull on box"
    ssh_exec "cd $REPO_DIR && git fetch --quiet && git reset --hard origin/main"

    echo "==> 2/4  build backend image"
    ssh_exec "cd $REPO_DIR && docker compose -f $COMPOSE_FILE --env-file $ENV_FILE build backend"

    echo "==> 3/4  run migrations"
    ssh_exec "cd $REPO_DIR && docker compose -f $COMPOSE_FILE --env-file $ENV_FILE run --rm backend -migrate"

    echo "==> 4/4  bring stack up"
    ssh_exec "cd $REPO_DIR && docker compose -f $COMPOSE_FILE --env-file $ENV_FILE up -d --remove-orphans"

    echo "==> waiting for backend healthcheck"
    sleep 5
    ssh_exec "curl -fsS http://localhost/healthz" || true
    echo
    echo "done. https://api.dripadvisor.app/healthz"
}

main "$@"
