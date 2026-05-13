# ADR 0001 — Monorepo restructure

Date: 2026-05-13
Status: Accepted
Author: marvkr + Claude Code

## Context

Repo started as iOS-only (`DripAdvisor.xcodeproj` + `DripAdvisor/` at root). Over the v1 / v1.1 design lock the scope grew to include:

- A Go backend (`backend/`)
- A Chrome extension (`chrome-extension/`)
- A future marketing / Universal-Link / OAuth-callback web app
- Shared design tokens + (eventually) shared API types

Keeping each in a separate repo would prevent atomic commits across a single feature ("add a new `/v1/wardrobe/scrape` field" needs to touch iOS DTO + Go DTO + chrome-ext popup in lockstep) and split CI / docs / ADRs across many places.

## Decision

Restructure to a polyglot monorepo:

```
apps/
  ios/        — Xcode project + Swift sources + Share Extension target
  backend/    — Go API + River workers + DB migrations
  chrome-extension/ — MV3 extension
  web/        — placeholder, marketing + universal-link landing
packages/
  design-tokens/ — colors, typography (Theme.swift mirror)
  shared-types/  — OpenAPI 3.1 (planned)
infra/
  docker-compose.yml — local dev stack
  hetzner/    — placeholder for prod cloud-init / terraform
docs/
  adr/        — this directory
  writeup.md
research/     — Mobbin reference screenshots (unchanged)
mise.toml     — unified tool versions
Makefile      — top-level targets
.github/workflows/ — per-app + smoke CI
```

## Rationale

- **Atomic cross-stack commits**: API field additions touch all clients in one PR.
- **Shared config / docs**: one `CLAUDE.md`, one `README.md`, one set of ADRs.
- **Industry-validated**: `first-fluke/fullstack-starter`, `kochan/saru`, `theatlantic/polyglot-nx` all colocate Swift/Flutter + Go + web in production monorepos.
- **No Xcode pain**: `.xcodeproj` opens at any subpath. Moving the project file alongside its source siblings preserves every `<group>`-relative pbxproj path.

## Verified post-move

- `xcodebuild -project apps/ios/DripAdvisor.xcodeproj … build` → `** BUILD SUCCEEDED **`
- `cd apps/backend && go build ./...` → clean

## Consequences

- Existing branches need rebase (no in-flight PRs at time of change).
- `git log --follow apps/ios/DripAdvisor/Models/WardrobeItem.swift` resolves history across the rename — blame intact.
- CI now keyed off path filters; cold cache for the first run.

## References

- [first-fluke/fullstack-starter](https://github.com/first-fluke/fullstack-starter) — Next + FastAPI + Flutter monorepo
- [kochan / saru](https://dev.to/kochan/nextjs-go-monorepo-managing-4-portals-x-4-apis-as-a-solo-developer-part-3-58e) — Next×4 + Go×4 + Turborepo
- [Atlantic / polyglot-nx](https://building.theatlantic.com/building-a-polyglot-monorepo-with-react-rails-and-go-using-nx-868af31d01e7) — React + Rails + Go via Nx plugins
- [Yaninyz / Managing monorepos in Go](https://medium.com/@yaninyzwitty/managing-monorepos-in-go-what-works-and-what-doesnt-363d01497d7f)
