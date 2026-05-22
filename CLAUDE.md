# CLAUDE.md — DripAdvisor agent instructions

Project-specific guidance for Claude Code when working in this repository. The README.md describes the product and architecture for humans; this file is directives for the agent.

## Monorepo layout (locked 2026-05-13 — see `docs/adr/0001-monorepo-restructure.md`)

```
apps/
  ios/              — Xcode project + Swift sources + Share Extension target
    DripAdvisor.xcodeproj
    DripAdvisor/
    DripAdvisorTests/
    DripAdvisorShareExtension/
  backend/          — Go API + River workers + DB migrations
  chrome-extension/ — MV3 extension
  web/              — placeholder (marketing + Universal Link landing)
packages/
  design-tokens/    — shared color/typography source of truth
  shared-types/     — OpenAPI 3.1 (planned)
infra/
  docker-compose.yml
  hetzner/          — prod placeholder
docs/
  adr/              — architecture decisions
research/           — Mobbin reference screenshots
mise.toml + Makefile + .github/workflows/
```

**Critical**: when reading existing files, use these paths — never `DripAdvisor/Screens/`. Always prefix with `apps/ios/DripAdvisor/`.

## Research tools — use before writing code

Always query these MCP servers for up-to-date information rather than relying on training recall. Hit them before making non-obvious claims or writing code against unfamiliar APIs.

- **swift-mcp** — `mcp__swift-mcp__list-sources`, `mcp__swift-mcp__query-snippets`
  Use for current Apple framework APIs: SwiftUI, SwiftData, Vision, PhotosPicker, CloudKit, StoreKit 2, ASWebAuthenticationSession, UserNotifications, APNs, WidgetKit, Core Graphics, UIKit interop. First stop for any Swift/SwiftUI code in this repo.

  **Mandatory call rhythm — not optional, not "first stop only":**
  - Before planning any iOS feature: query swift-mcp for the primary APIs you intend to use (e.g. `phaseAnimator`, `matchedGeometryEffect`, `symbolEffect`, `glassEffect`, `@Observable`, `NavigationStack(path:)`, `task(id:)`, `SubscriptionStoreView`, `VNGenerateForegroundInstanceMaskRequest`).
  - Before EVERY distinct iOS write that touches a SwiftUI/Apple API symbol you haven't queried in the current session, run a fresh `query-snippets`. One query at session start does NOT cover later writes — Apple frequently revises modifier signatures, parameter labels, and deprecates symbols.
  - Cite the snippet (URL or `/apple/swiftui` source) in your reasoning when adopting a non-trivial API so the user can audit.
  - If you find yourself reaching for an API from memory and you have not queried it this session, STOP and query first. Do not guess parameter labels, availability, or iOS-version gating.
  - Target iOS 26+ unless explicitly told otherwise — prefer the newest APIs (`@Observable`, `phaseAnimator`, `symbolEffect`, `.spring(duration:bounce:)`, `glassEffect`, Liquid Glass) over their iOS 16/17 predecessors.

- **context7** — `mcp__context7__resolve-library-id`, `mcp__context7__query-docs`
  Use for third-party library docs: Gemini Go SDK (`google.golang.org/genai`), River (Go + Postgres queue), pgx, pgvector, Resend, Twilio Verify, Universal Links / AASA, and any Swift Package Manager dependency.

- **Exa** — `mcp__exa__web_search_exa`, `mcp__exa__web_fetch_exa`
  Use for general web research: benchmarks, pricing, industry data, comparisons, case studies, incident postmortems. Prefer Exa over generic web search for grounded recommendations.

- **system-design-mcp** — `mcp__system-design-mcp__resolve-topic`, `mcp__system-design-mcp__get-design-content`
  Use to validate distributed-systems decisions against the Hello Interview corpus (WhatsApp, Slack, Discord, Meta Threads, Message Brokers 101, etc.). Already referenced in README's Verification Log — run fresh queries when introducing new architectural patterns.

Rule of thumb: if you're about to assert a performance number, a library behavior, a best practice, or an API shape — search first.

## Verification tools — use after writing code

- **ios-simulator-mcp** — `mcp__ios-simulator__open_simulator`, `mcp__ios-simulator__get_booted_sim_id`, `mcp__ios-simulator__install_app`, `mcp__ios-simulator__launch_app`, `mcp__ios-simulator__screenshot`, `mcp__ios-simulator__record_video`, `mcp__ios-simulator__stop_recording`, `mcp__ios-simulator__ui_describe_all`, `mcp__ios-simulator__ui_describe_point`, `mcp__ios-simulator__ui_find_element`, `mcp__ios-simulator__ui_tap`, `mcp__ios-simulator__ui_type`, `mcp__ios-simulator__ui_swipe`, `mcp__ios-simulator__ui_view`.

  **Mandatory for any user-visible iOS change.** A clean `xcodebuild` is not proof the feature works. After every SwiftUI / UX / animation / navigation / state-flow change, you MUST:
  1. `xcodebuild` for an iOS Simulator destination (e.g. `iPhone 17 Pro`, OS 26.x).
  2. Boot sim (`open_simulator`), install the `.app` from DerivedData (`install_app`), launch via bundle id `com.dripadvisor.DripAdvisor` (`launch_app`).
  3. Drive the affected flow with `ui_tap` / `ui_type` / `ui_swipe`, capture `screenshot` (or `record_video` for animations) at each key state.
  4. Inspect `ui_describe_all` to confirm expected accessibility tree / labels / states.
  5. Only after visual + a11y confirmation, claim the change works.

  Never report a SwiftUI change as "done" based on compile success alone. If the simulator can't be reached, say so explicitly — do not claim verification.

  **Self-enforcement rule (added 2026-05-18):** every reply that delivers an iOS UI change MUST end with either:
  - `verified-in-sim: <one-line description of what you saw>` if you ran the sim flow and the screenshot/a11y dump matches expectation, OR
  - `NOT verified-in-sim: <reason>` if you skipped or were unable.
  Saying nothing = lying about verification. The user has explicitly asked for this guardrail; never silently skip it.

## Codebase conventions

- **SwiftUI + Swift 6 strict concurrency.** Not UIKit. Not Swift 5.
- **State** — `@Observable` + `@MainActor` for stores. Not `ObservableObject`. Not `@StateObject`/`@ObservedObject`.
- **Navigation** — `NavigationStack`, not `NavigationView`.
- **Async** — `async`/`await` + structured concurrency. Not completion handlers. Not `DispatchQueue.main.async` unless bridging legacy APIs.
- **Images** — Apple Vision (`VNGenerateForegroundInstanceMaskRequest`) for background removal of **user-originated** images only (selfies, in-closet shots, body avatar). Scraped ecommerce images (Lulu, Uniqlo, Zara) route through server-side rembg (Bria RMBG 2.0 / BiRefNet on the Hetzner box) instead — Vision is unreliable on commercial studio shots with low contrast vs backdrop. Locked 2026-05-22 after Lulu + Uniqlo sim verification both showed Vision returning empty `allInstances`.
- **DB columns** — `TEXT` + `CHECK (char_length(col) <= n)`. Never `VARCHAR(n)`. Never `VARCHAR(255)`.
- **Queue** — River (Postgres-backed) for durable jobs. Raw Redis `PUBLISH` for ephemeral chat fan-out. Never Asynq for durable work.
- **Image models** — Gemini Nano Banana Pro (`gemini-3-pro-image-preview`) / Nano Banana 2 (`gemini-3.1-flash-image-preview`). Never Seedream / Flux / SDXL.
- **Never mention Supabase** — managed Postgres means Neon / RDS / Aurora / Crunchy / Fly / Render / self-hosted Hetzner.

## Decisions already locked

See README.md's "Product Decisions (locked)" and "Architecture Notes" sections. Do not re-litigate these unless explicitly asked — and if asked to change one, update both README.md and any dependent decisions.

Key locked items:
- 3-tab product shape (Wardrobe / Outfits / Chat)
- iOS deployment target = **18.0** (was 26.0; dropped 2026-05-12 for universal compat). Gate iOS 26-only APIs (`glassEffect`, `FoundationModels`) with `if #available(iOS 26, *)`.
- Per-chat `seq` ordering via `redis.INCR chat:{id}:seq`; `created_at` is decorative; `seq` is `bigint`
- **Per-`chat:{id}` Redis pub/sub channels** (revised 2026-05-12; was per-`user:{id}`). Group cap = 8 members.
- 10s heartbeat / 5s pong timeout, piggyback `seq` for gap detection
- Inbox table as durability backstop for Pub/Sub at-most-once
- River for durable jobs, Redis PUBLISH for ephemeral
- Body reference photos never leave device except transiently during try-on. Try-on composites + garment cutouts opt-in shareable, stored in R2 only on explicit share/save.
- Typed messages: `kind text check (kind in ('text','outfit_share','garment_share','agent_proposal','image'))`. Outfit/garment shares store **frozen snapshot in `payload jsonb` + soft `ref_id`**.
- Postgres bounded strings: `TEXT` + `CHECK` (never `VARCHAR(n)`, never `ENUM`).
- AI stylist agent = first-class `user_id`. Invocation: explicit `@stylist` universal; iOS 26 + Apple Intelligence device auto-detects styling questions via on-device `FoundationModels` classifier (no server-side classifier fallback).
- 4-week closed-beta v1: wardrobe + try-on + paywall only; chat/social to v1.1

## Writing code in this repo

- Start by reading existing files (`apps/ios/DripAdvisor/Screens/`, `apps/ios/DripAdvisor/Store/`, `apps/ios/DripAdvisor/Models/`, `apps/backend/internal/`) before adding new ones.
- Prefer editing existing files over creating new ones.
- Never commit unless explicitly asked.
- Never co-author Claude in commits or include Claude-Code attribution.
- Never pass `--no-verify` or skip hooks unless the user explicitly asks.
- Before claiming CI-safe, verify Swift compile (Xcode build) for iOS code and `go build ./...` + `golangci-lint run` for Go backend code.

## Working with the user

- Be concise. Skip preamble.
- Match locked decisions — if a new recommendation conflicts, say so explicitly instead of silently deviating.
- Never recommend an approach that contradicts the "Never-use / avoid list" in README.md.
- For exploratory questions ("what could we do about X?"), give 2–3 sentences with a recommendation + tradeoff. Don't implement until user agrees.
