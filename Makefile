# DripAdvisor monorepo — top-level task runner.
# Per-app commands live in apps/*/Makefile.

.PHONY: help up down ios-build ios-test backend backend-build backend-test chrome-lint test fmt lint all clean

help:
	@echo "DripAdvisor monorepo targets:"
	@echo "  make up             # docker compose Postgres + Redis + MinIO"
	@echo "  make down           # stop docker compose"
	@echo "  make ios-build      # xcodebuild iOS app (iPhone 17 Pro sim)"
	@echo "  make backend        # run Go backend"
	@echo "  make backend-build  # go build ./..."
	@echo "  make test           # all tests"
	@echo "  make fmt            # format Swift + Go"
	@echo "  make all            # build everything"

up:
	docker compose -f infra/docker-compose.yml up -d

down:
	docker compose -f infra/docker-compose.yml down

ios-build:
	xcodebuild -project apps/ios/DripAdvisor.xcodeproj \
		-scheme DripAdvisor \
		-destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
		-configuration Debug build

ios-test:
	xcodebuild -project apps/ios/DripAdvisor.xcodeproj \
		-scheme DripAdvisor \
		-destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
		test

backend:
	cd apps/backend && go run ./cmd/server

backend-build:
	cd apps/backend && go build ./...

backend-test:
	cd apps/backend && go test ./...

chrome-lint:
	cd apps/chrome-extension && node -e "const m=require('./manifest.json'); if(m.manifest_version!==3) process.exit(1); console.log('manifest_version', m.manifest_version);"

# Sync apps/ios/screens/*.png into the Notion screens page.
# Requires NOTION_API_KEY env var (see scripts/README.md).
screens-sync:
	cd scripts && (test -d node_modules || npm install --silent) && node sync-screens-to-notion.mjs

test: backend-test ios-test

fmt:
	cd apps/backend && go fmt ./...

lint:
	cd apps/backend && go vet ./...

all: backend-build ios-build chrome-lint

clean:
	cd apps/backend && go clean
	rm -rf ~/Library/Developer/Xcode/DerivedData/DripAdvisor-*
