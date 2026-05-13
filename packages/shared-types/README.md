# @dripadvisor/shared-types

JSON Schemas for backend ↔ iOS ↔ web type sharing.

## Status

v0: skeleton. iOS hand-rolls types in `apps/ios/DripAdvisor/Services/DripAPI.swift`.
Backend hand-rolls in `apps/backend/internal/httpapi/server.go`.

## Plan

- [ ] Author OpenAPI 3.1 spec for `/v1/*` endpoints
- [ ] Generate Swift types via `apple/swift-openapi-generator`
- [ ] Generate Go types via `oapi-codegen`
- [ ] Generate TS types via `openapi-typescript` (for chrome-ext + future web)

Single spec → 3 typed clients. Eliminates drift.
