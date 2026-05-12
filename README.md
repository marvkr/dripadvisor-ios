# DripAdvisor

SwiftUI iOS app for wardrobe capture, outfit composition, and AI-styled chat.

## Product Shape

Three tabs:
1. **Wardrobe** — capture clothing from social-media screenshots (Instagram / Pinterest / Facebook / TikTok) or photo library. On-device background removal via Apple Vision (`VNGenerateForegroundInstanceMaskRequest`) produces transparent-bg PNGs.
2. **Outfits (center FAB)** — compose top/bottom/shoes onto the user's full-body reference photo via Gemini Nano Banana Pro (`gemini-3-pro-image-preview`, 14 ref-image support). Tagged by occasion, weather, time-of-day.
3. **Chat** — iMessage-clone (tapbacks, typing, read receipts, reply threading, streaming replies, stickers, voice notes, effects). 1:1 and group. AI stylist agent is a first-class participant via `ai_agents` table + per-chat opt-in for wardrobe sharing.

External sharing carries a watermark. Outfits carry a "Remix" deep link — tapping opens the outfit in the viewer's app (installs if needed).

## Stack

- **iOS** — SwiftUI, Swift 6, `@Observable` store, SwiftData + CloudKit private DB for body reference photos (never leave device except transiently during try-on).
- **Backend** — Go + Postgres + Redis **co-located on a single Hetzner VPS**. Starts on CCX13 (~€12.50/mo); upgrade path within VPS-land goes CCX13 → CCX23 (~€25/mo) → CCX43 (~€75/mo) → AX162-R dedicated (~€400/mo, 96 cores / 1TB RAM) — sufficient for millions of DAU. Systemd-managed, UptimeRobot + Better Stack monitoring, nightly `pg_dump` cron to Cloudflare R2 with monthly restore drills.
- **Database** — Postgres (self-hosted on the Hetzner box). All string columns use `TEXT` + `CHECK` constraints, never `VARCHAR(n)`.
- **Cache / Realtime** — Redis (self-hosted on the same box). AOF `fsync everysec` + RDB snapshots every 5 min. Holds per-chat sequence numbers via `INCR`, pub/sub fan-out keyed by `user:{id}`, typing-indicator TTL.
- **Job queue** — River (Postgres-backed) for all durable jobs (`extract_garment`, `ingest_bookmark`, `compose_outfit`, `stylist_reply`, `push_send`, `aged_message_purge`). Raw Redis `PUBLISH` for chat fan-out + typing indicators (ephemeral). Same durable-vs-fast split as Slack (Kafka + Redis), scaled down.
- **Object storage** — Cloudflare R2 (zero egress). Stores wardrobe item PNGs, outfit composites. **Never stores body reference photos.**
- **Image generation** — Gemini Nano Banana Pro (`gemini-3-pro-image-preview`) for outfit compositing. Nano Banana 2 (`gemini-3.1-flash-image-preview`) for low-cost ops. Go SDK: `google.golang.org/genai`.
- **Stylist LLM** — Gemini 3 Pro via OpenAI-compatible endpoint at `https://generativelanguage.googleapis.com/v1beta/openai/`. Function calling for wardrobe lookup + recommendation.
- **Auth** — Apple Sign In (primary), Google OAuth, Facebook OAuth, Email magic link (Resend), Phone OTP (Twilio Verify via `ASWebAuthenticationSession`). Account linking on collision prompts the user.
- **Push** — APNs. App-level heartbeats every 10s with 5s pong timeout (15s max dead-connection detection, matching WhatsApp's pattern). Heartbeat piggybacks user's latest `max(seq)` across chats for gap detection.

## Architecture Notes

### Message ordering
Per-chat monotonic sequence (`seq BIGINT`) assigned via `redis.INCR chat:{id}:seq`. `created_at` is stored but decorative; all sorting is by `seq`. On Redis cold-start, seed the key from `SELECT MAX(seq) FROM messages WHERE chat_id=$1`. Heartbeats include the user's latest server-known `seq` so clients can detect gaps within 15s (WhatsApp pattern).

### Fan-out & pub/sub
**Revised 2026-05-12 — was per-`user:{id}`, now per-`chat:{id}`.**

Redis channels keyed by **`chat:{chat_id}`**. Original locked decision was per-`user:{id}` channels (justified by 1:1-dominated assumption). Group chats are now core to the v1.1 chat product (iMessage-style w/ AI agent as participant + friends), so per-user fan-out cost is O(N members) `PUBLISH` calls per message — not acceptable as the default path.

Per-chat topology (industry standard — Discord, Slack, getstream.io):
- Publisher does 1 `PUBLISH chat:{id} <msg>` per outgoing message.
- Each gateway server subscribes to `chat:{id}` for every chat that has at least one locally-connected member. On user connect, gateway subscribes to all of that user's chats; on disconnect, gateway unsubscribes from any chat with no remaining local subscribers (reference-counted in-memory map).
- Membership lookup cached in Redis hash `chat:{id}:members` (TTL 60s, invalidated on add/remove), source of truth in Postgres `chat_participants`.
- Group size cap = 8 → per-chat fan-out is trivially small.

WhatsApp-pattern Inbox table (durability backstop) still applies — receivers ack each Inbox row; unacked rows resync on reconnect.

### Delivery & durability
- Chat fan-out over Redis `PUBLISH` (at-most-once) + persistent **Inbox table** per recipient is the durability backstop. Undelivered messages stay in Inbox until the client sends an `ack`. This is the exact WhatsApp Inbox pattern.
- Client `ACK` timeouts (500–2000ms) trigger server retry; after N retries, server closes the WebSocket and forces reconnect + Inbox sync.
- Durable jobs use **River (Postgres WAL)**. At-least-once semantics + idempotency at the worker (via River's unique-jobs feature keyed on `user_id + source_hash` for `ingest_bookmark`, etc.) — exactly the default the Message Brokers 101 reference recommends.

### Sharding
Not needed until we exhaust a single Hetzner AX162-R dedicated box (~5–10M DAU on current workload estimates). Scaling order:
1. **Vertical** — upgrade Hetzner VPS class as we grow (CCX13 → CCX23 → CCX43 → AX162-R). Zero code changes.
2. **Read replicas** — add a Postgres streaming replica on a second Hetzner box; route reads there. Still zero app-level sharding.
3. **Horizontal (only if needed)** — consistent-hash on `user_id` across multiple primary Postgres nodes. Precedent: WhatsApp's "island" fragment-per-node pattern.
See `writeup.md` for the reasoning behind staying on VPS rather than moving to managed Postgres.

### Sensitive data — privacy tiers
**Two tiers, distinct lifecycles:**

1. **Body reference photo (avatar) — never persisted server-side.**
   Lives only in SwiftData + CloudKit private DB. Uploaded transiently to the Go backend during try-on, passed to Gemini, dropped immediately after response. Never persisted server-side. Never in R2.

2. **Try-on composites + garment cutouts — opt-in shareable.**
   Default `visibility = private` (only owner can fetch). When user explicitly shares to a chat OR saves as a public outfit, the asset is uploaded to R2 (CDN) and a row created in `outfits` / message snapshot. Access is gated by ACL: `private` → owner only; `friends` → mutuals only; `public` → any authenticated user; `shared-to-chat` → chat members only (via `chat_participants` membership check). Asset URLs are signed (TTL 1h, refreshed on access).

   Composites contain the user's face/body — privacy-sensitive but functionally required for sharing. By keeping default private + explicit share-action, no body image leaves the device without an explicit user gesture.

### Idempotency
All write endpoints that trigger expensive AI work (`compose_outfit`, `ingest_bookmark`, `stylist_reply`) accept a client-generated idempotency key (UUID). Duplicate keys within 24h return the original response instead of re-processing. Pattern from Slack's client-salt approach for handling retry-induced duplicates.

## Push Notification Strategy

| Notif type | `thread-id` | Priority | Interruption level | Rich? | Collapse? |
|---|---|---|---|---|---|
| 1:1 chat message | `user:{other_user_id}` | 10 | time-sensitive | text-only (v1) | no |
| Group chat message | `chat:{chat_id}` | 10 | active | text-only (v1) | no |
| Stylist agent reply | `chat:{chat_id}` | 10 | active | **NSE-rich (outfit thumbnail)** | no |
| Reaction | `user:{other_user_id}` or `chat:{chat_id}` | 5 | active | text-only | per-message |
| Outfit shared to you | `outfit-share:{sender_id}` | 5 | active | **NSE-rich (outfit preview)** | no |
| Friend joined | `friend-requests` | 5 | active | text-only | per-sender |
| Daily outfit idea | `system` | 5 | passive | text-only | per-day |
| Streak lapse | `system` | 5 | passive | text-only | per-day |
| Remix of your outfit | `outfit-share:{remixer_id}` | 5 | active | **NSE-rich (remix preview)** | no |

- Payload budget: 4 KB per APNs docs. Keep bodies terse.
- **Notification Service Extension** in v1 only for outfit-share + agent-reply-with-outfit (the visual payoff matters most there). Text-only for chat bodies; NSE coverage expands in v1.1.
- **Silent push** (`content-available: 1`) only for badge sync + inbox-invalidation. iOS throttles silent push to ~2–3/hour — we never use it for message delivery.
- **Deep links**: `dripadvisor://chat/{chat_id}?msg={msg_id}` + Universal Link fallback at `https://open.dripadvisor.app/chat/{chat_id}?msg={msg_id}`. Requires `apple-app-site-association` at `/.well-known/apple-app-site-association`.
- **Copy templates**: literal for 1:1 (`Sarah: nice fit 🔥`), teaser for groups/system (`Your Stylist just replied in [group] — tap to see the fit`).
- **Send-time**: timezone-aware fixed sends in v1 (7am daily idea, 6pm streak reminder). Per-user best-time learning in v1.1 after 30 days of engagement data.

## Onboarding / Conversion Design

Funnel: **quiz → reveal → free magic → soft paywall**. Targets 40%+ quiz completion, 8–12% paid conversion.

Top tactics (ranked by leverage):
1. Psychographic quiz onboarding (Noom/Cal AI pattern) — 9 questions on style archetype, pain, events, brands.
2. "Building your Style DNA" loading screen → personalized reveal (Cal AI, Noom).
3. Fear/loss-framed personalized calculation ("Women with your profile waste $1,847/year …") — Opal pattern.
4. Soft paywall with free try-on quota (3 try-ons + 2 AI replies/week free); hard wall kills AI consumer apps.
5. Steep anchored discount ("$119 ~~~~ → $39.99/year, 67% off") with optional 7-day trial toggle (off by default) — Lensa pattern.
6. Dense social-proof screen immediately before paywall.
7. Before/after hero imagery throughout onboarding.
8. Widget prompt at onboarding end (Outfit-of-the-Day) — Finch/Duolingo commitment device.
9. Attribution quiz ("Where did you hear about us?") doubling as UA segmentation.
10. Sensitive-photo ask only after first successful try-on with default model — never cold at onboarding.

Full 28-screen onboarding blueprint in `/docs/onboarding.md` (TBD).

## Product Decisions (locked)

### Watermark on shared outfits
- **Content**: Logomark + user's `@handle` ("@marvink · made with DripAdvisor") — bottom-left, 70% opacity.
- **Rendering**: Baked client-side via Core Graphics before Share Sheet hand-off.
- **Pro benefit**: Pro users can toggle watermark off. Free users always watermarked.
- **Scope**: All shared outfits (AI-generated or manually composed), not individual wardrobe items.
- **Provenance**: C2PA-style metadata attached in addition to visual mark (AI-disclosure readiness).

### Friends & Invites
- **Discovery**: Both contact-book matching (SHA-256 client-side hash, server-side hash table match — no raw contacts stored) AND `@username` search. Contacts skippable at onboarding.
- **Invite flow**: Primary CTA = pre-filled iMessage via `MFMessageComposeViewController` with rich link + preview outfit image. Secondary = iOS Share Sheet.
- **Referral reward**: 5 free try-ons + 1 free month Pro per installed friend, capped at 3 rewarded invites per user.
- **Visibility model**: Per-outfit `visibility` enum (`private` / `friends` / `public`). Default for new outfits = `friends`. Wardrobe items are always private.

### External sharing
- **Format**: PNG for iMessage/Pinterest, 9:16 3-second MP4 with parallax for Instagram Stories / TikTok / Reels — auto-detected by share target via `UIActivityViewController`.
- **First-class handlers (v1)**: Instagram Stories (deep link `instagram-stories://share`) + iMessage. Everything else via standard Share Sheet. v1.1 adds TikTok SDK + Pinterest SDK.
- **Caption**: Pre-filled, context-aware from the outfit's occasion tag ("My rooftop dinner fit 🥂 — built in DripAdvisor"). User-editable.
- **Remix deep links**: Shipped in v1. Every shared outfit carries a Universal Link that opens the outfit in the viewer's app (or prompts install). Highest organic-growth lever.

### Image processing pipeline
- **River (Go + Postgres)** for all durable jobs. Reasoning: Postgres WAL beats Redis AOF/RDB for durability; if Postgres holds the source-of-truth data, the queue should be at least as durable as that data (River author's argument, verified in system-design-mcp's Message Brokers 101 — Redis Lists/Pub-Sub are at-most-once without Streams).
- **Raw Redis `PUBLISH`** for ephemeral chat fan-out + typing indicators + presence. Same durable-vs-fast split Slack uses (Kafka + Redis), at a smaller scale.
- **Concurrency caps** — `compose_outfit`: 20, `extract_garment`: 50, `stylist_reply`: 40, rest unbounded. Protects Gemini quota and cost during retry storms.
- **Idempotency** — River unique-jobs keyed on `user_id + source_hash` for `ingest_bookmark`. Write endpoints accept client-generated idempotency keys (Slack pattern).
- **Retry policy** — `compose_outfit` MaxAttempts = 3 (expensive), others = 5. Exponential backoff. Failed → `discarded`, alert via Better Stack if > 10/hour.
- **Priority queues** — `critical` (stylist_reply, compose_outfit — user actively waiting), `default` (extract, ingest), `low` (purge, analytics).

### Database schema (Postgres, self-hosted)

Tables: `users`, `wardrobe_items`, `outfits`, `outfit_items`, `chats`, `chat_participants`, `ai_agents`, `messages`, `message_reactions`, `inbox`, `friendships`, `devices`, `wardrobe_ingestions`.

Schema decisions:
- **All string columns** are `TEXT` + `CHECK (char_length(col) <= n)` constraints. Never `VARCHAR(n)`.
- **Tags** (`wardrobe_items.tags`) stored as `TEXT[]` with GIN index. v1 simplicity; separate tags table only if hitting 10M+ items.
- **Read receipts** — per-chat `last_read_seq` on `chat_participants` (iMessage-style "Read at 2:34pm"), not per-message double-checks.
- **Message retention** — free tier ages out at 1 year; Pro = forever. Cost-lever decision at 100k DAU × 100 msgs/day = ~3.6B rows/year.
- **Ingestion pipeline** — `wardrobe_ingestions` table (status: `pending` / `extracting` / `done` / `failed`, + retry count). Decouples upload from extraction; feeds queue-depth metrics. `wardrobe_items` row created on success.
- **Message edits** — simple `edited_at TIMESTAMPTZ`, body replaced in place. No separate audit table in v1.
- **Outfit remix** — `outfits.remix_of UUID REFERENCES outfits` tracks viral spread ("24 people remixed this").
- **Reactions** — separate `message_reactions` table (PK on `message_id, user_id, emoji`), not JSON on messages. Needed for efficient "who reacted with 🔥" queries.
- **AI agent as participant** — `chat_participants` has `user_id` OR `agent_id` (one-of), plus `shares_wardrobe BOOLEAN` for per-chat opt-in.

### v1.1 Chat Design (locked 2026-05-12)

Recorded from a grill-me design session. Supersedes any earlier per-chat assumptions.

**iOS deployment target — dropped from 26.0 to 18.0.**
- Universal compatibility goal — ~95–98% of active iPhones reachable on iOS 18 floor.
- iOS 26-only APIs gated with `if #available(iOS 26, *)`:
  - `glassEffect` (Liquid Glass) — used in `ChatComposer`. Fallback: `.background(.ultraThinMaterial, ...)`.
  - `FoundationModels` framework (`SystemLanguageModel`, `LanguageModelSession`, `@Generable`, `@Guide`) — used only for the on-device agent-intent classifier. Fallback: explicit @mention only.
- Action item: `IPHONEOS_DEPLOYMENT_TARGET = 18.0` in `DripAdvisor.xcodeproj/project.pbxproj`. All 5 occurrences (Debug + Release × configs).

**Chat shape.**
- iMessage-style: 1:1 (`dm`), group (`group`), and stylist-solo (`stylist_solo`).
- `chats.kind text check (kind in ('dm','group','stylist_solo'))`.
- Group cap = **8 members** (incl. agent). Enforced both app-side (pre-write) and DB-side (`check (member_count between 1 and 8)`).
- AI stylist is a first-class user with its own `user_id` (not a sidecar). Treated identically to humans in fan-out, ACL, reactions, mentions.

**Message content — typed rows.**
```sql
messages (
  id uuid pk,
  chat_id uuid,
  sender_user_id uuid,        -- agent or human, both real users
  seq bigint,                 -- redis INCR chat:{id}:seq
  kind text check (kind in ('text','outfit_share','garment_share','agent_proposal','image')),
  text text,                  -- nullable
  ref_id uuid,                -- soft ref → outfits.id or wardrobe_items.id
  payload jsonb,              -- frozen snapshot for shares (see below)
  edited_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz
)
reactions (
  message_id uuid,
  user_id uuid,
  emoji text check (char_length(emoji) <= 16),
  created_at timestamptz,
  primary key (message_id, user_id, emoji)
)
```
- Five kinds: `text`, `outfit_share`, `garment_share`, `agent_proposal`, `image`.
- iOS renderer dispatches on `kind`.
- Pattern is industry-standard (Slack `message_type ENUM('text','file','system')`, Discord typed messages, WhatsApp text/image/voice/etc.).

**Outfit/garment shares — snapshot + soft ref.**
- `payload` is a **frozen snapshot** captured at share-time: composite URL, item names, occasion. Chat-history immutability: friend reactions reference the thing-as-it-was-shared, owner edits/deletes don't break the chat thread.
- `ref_id` is a **soft pointer** to the live `outfits.id` / `wardrobe_items.id` — used for "Open in Outfits tab" deep-link, gracefully degrades to "Owner deleted this" badge if the ref is gone.

**Reactions — same on agent and human messages.**
- Reactions table same primary key (`message_id`, `user_id`, `emoji`) regardless of message sender. No special "can't react to agent" rule. Reactions on shared content go on the message row, not the asset (covers text + share uniformly).

**Agent invocation rules.**
- `stylist_solo` chat: every user message auto-routes to agent. No mention required.
- `dm` / `group` chats with agent as member:
  - Explicit `@stylist` → agent always replies.
  - **iOS 26 + Apple Intelligence-eligible device**: on-device classifier via `FoundationModels` framework (`SystemLanguageModel(useCase: .contentTagging)` + `@Generable` struct `StylistIntent { isStylingQuestion: Bool }`) runs on each outgoing message. If `isStylingQuestion == true`, client invisibly auto-injects `@stylist` mention.
  - **iOS 18 / iOS 26 ineligible device**: explicit `@stylist` only. No server-side classifier fallback (privacy + cost win).
- Plus: auto-react when user shares an outfit/garment to a chat with agent present (toggleable via `chats.agent_auto_react bool default true`).

**Read receipts.**
- Per-chat `chat_participants.last_read_seq bigint`. Updated on chat open / scroll-to-bottom.
- "Read at HH:MM" rendered for 1:1; aggregate "Seen by N" for group.

**Typing indicators.**
- Ephemeral via Redis `PUBLISH chat:{id}:typing {user_id, started_at}`.
- TTL 5s — typing fades out automatically without an explicit "stopped typing" message.
- Not persisted, not in Inbox table. Lossy by design.

**Editing / deleting.**
- Edit own message ≤ 15 min after send; sets `edited_at`; body replaced in place (no audit history in v1.1).
- Delete own message = soft delete (`deleted_at` set); UI shows tombstone "Message deleted" placeholder so reply/reaction refs don't break.
- No edit/delete on others' messages even for admins (matches iMessage).

**Roles.**
- Chat creator = admin.
- Admin: add/remove members, delete the entire chat, transfer ownership.
- Non-admin: leave the chat.
- 1:1 (`dm`) and `stylist_solo` have no role concept.

**Threading / replies.**
- v1.1 ships flat conversation only. Quoted-message ("reply-to-message") via `messages.reply_to_id uuid nullable` (renders inline quote bubble). No threaded sub-conversations.
- Full threading (`thread_ts` Slack-style) deferred to v2.

**Chat list ordering.**
- Sorted by latest message `seq` desc within chat (since `seq` is per-chat, the "last activity" comparator uses each chat's `max(seq)` mapped to `messages.created_at` for cross-chat sort).
- Implementation: `chats.last_message_at timestamptz` denormalized column, updated on insert via trigger.

**Message retention.**
- Free tier: 1-year rolling window. Free `aged_message_purge` River job runs nightly.
- Pro tier: forever.
- Same policy as v1.

**Search.**
- Deferred to v2 (Elasticsearch / OpenSearch + async indexer from Postgres). v1.1 ships no full-text search.

### Never-use / avoid list
- **Supabase** — not used or recommended anywhere.
- **Managed Postgres / Redis as default** (Neon, Upstash, RDS, Aurora, etc.) — we run Postgres + Redis on the same Hetzner VPS as the Go server. See `writeup.md`.
- **`VARCHAR(n)`** — not used. `TEXT` + `CHECK` everywhere.
- **Seedream / Flux for image gen** — we use Gemini Nano Banana family exclusively.
- **S3 for body photos** — body reference photos never leave the device except transiently.
- **Silent push for message delivery** — iOS throttles silent push heavily. Silent push only for badge sync + inbox-invalidation. Messages always use visible pushes.
- **Asynq (Redis-based queue) for durable jobs** — Redis persistence (AOF/RDB) is weaker than Postgres WAL; durable queue must be at least as durable as the data it writes.

## Milestone Cut

**v1 = 4-week closed beta. Wardrobe + try-on + paywall only.** Chat, AI agent, social sharing, widgets → v1.1.

Rationale: the revenue thesis is "people will pay for AI try-on." If that fails, no amount of chat saves the business. Ship the narrowest pipeline that proves the core thesis (DoorDash menu-transcription "baseline MVP" pattern — prove the system works end-to-end before layering on features). WhatsApp's "clarity over cleverness" principle also backs the narrow-first approach.

### v1 (weeks 1–4)
- **Week 1 — Foundation**: Go backend + Postgres + Redis co-located on Hetzner CCX13, TLS via Caddy, DB schema, River worker bootstrap, Apple Sign In + JWT sessions, nightly `pg_dump` cron to R2 (with a rehearsed restore), iOS `DripStore` hooked to backend (no longer local-only).
- **Week 2 — Wardrobe ingestion**: Photos picker → upload → `wardrobe_ingestions` row → River `extract_garment` job (Apple Vision BG removal on-device for v1) → R2 upload + CDN. Bookmark via Share Extension receiver for Instagram/Pinterest URLs.
- **Week 3 — Outfits + try-on**: Gemini Nano Banana Pro integration, `compose_outfit` River job, body-ref on-device storage + transient upload flow, free-quota enforcement (3 try-ons/week free-tier), composite storage in R2.
- **Week 4 — Onboarding + paywall**: 28-screen quiz flow, Style DNA reveal, StoreKit 2 paywall (7-day trial, annual, lifetime), attribution capture, TestFlight closed beta.

### v1.1 (weeks 5–8) — see "v1.1 Chat Design (locked)" above for full spec
- Chat core: 1:1 + groups (cap 8) + stylist-solo. `chats.kind` enum. Per-`chat:{id}` Redis pub/sub.
- Typed messages (5 kinds). Outfit/garment shares as frozen `payload` snapshot + soft `ref_id`.
- Reactions table, read receipts (`last_read_seq`), typing indicators (Redis ephemeral 5s TTL), edit ≤15min, soft-delete tombstone.
- Stylist agent as first-class user. Invocation: explicit `@stylist` universal; on-device `FoundationModels` classifier (iOS 26 + Apple Intelligence devices) auto-injects `@stylist` for detected styling questions.
- APNs pipeline, streaming agent replies via Gemini 3 Pro function calling.
- Friends (contacts hash + @username), iMessage invite flow, watermarked share composite, Remix deep links.
- Widget (Outfit-of-the-Day), daily/streak push notifications.
- Action item: drop `IPHONEOS_DEPLOYMENT_TARGET` to `18.0` + add `if #available(iOS 26, *)` guards for `glassEffect` + `FoundationModels`.

### Deferred (v2+)
- TikTok / Pinterest first-class share SDKs.
- Notification Service Extension for all chat notifs (v1.1 ships NSE only for outfit-share).
- Per-user best-time notification send (needs 30d engagement data first).
- Message edit-history audit table.
- Normalized `item_tags` table (vs current `TEXT[]`).
- Android.
- Multi-body-reference support.

## Research / Verification Log

Design decisions above are cross-referenced against:
- **system-design-mcp** (Hello Interview corpus): WhatsApp breakdown + case study, Slack case study, Message Brokers 101, Messaging Patterns Explained, How to Choose a Message Queue.
- **Exa web search** (2025–2026): River vs Asynq benchmarks, APNs best practices, iOS push notification patterns.
- **context7**: Gemini Go SDK, Apple framework APIs.

Specific findings that adjusted the design:
1. **Per-user Redis pub/sub channels** (not per-chat) — WhatsApp breakdown explicit recommendation for 1:1-dominated traffic.
2. **Heartbeat piggybacks `seq` for gap detection** — WhatsApp's explicit pattern; cheap enhancement to the sequence-number design.
3. **River over Asynq for durable jobs** — confirmed by Message Brokers 101 (Redis Lists/Pub-Sub are at-most-once; only Streams give at-least-once, and even that relies on RDB persistence).
4. **Slack's durable-vs-fast split** directly parallels our River-vs-Redis-PUBLISH split.
5. **"Baseline MVP" sequencing** (DoorDash menu case study) backs the 4-week closed-beta cut over an 8-week all-in v1.

## Repo Layout

```
DripAdvisor/
├── Screens/            # SwiftUI views (per-tab + modals)
├── Store/              # @Observable DripStore (app state)
├── Models/             # Value types: WardrobeItem, Outfit, ChatMessage, UserProfile
└── Theme/              # Colors, cards, button styles
research/
└── paywall-onboarding/ # Mobbin research screenshots (66 screens from 13 apps)
```

## Code Conventions

- SwiftUI, Swift 6 strict concurrency.
- `@Observable` + `@MainActor` for stores (not `ObservableObject`).
- `NavigationStack` (not `NavigationView`).
- `async`/`await` + structured concurrency throughout.
- Postgres columns use `TEXT` + `CHECK`, never `VARCHAR(n)`.

> For agent-specific instructions (which MCP tools to query, locked decisions, workflow), see `CLAUDE.md`.

## Status

- **Current** — v0 prototype: 3-tab scaffolding, local `DripStore` with in-memory wardrobe / outfits / chat, simulated try-on, toy word-streaming stylist reply.
- **Next** — v1 closed-beta build (weeks 1–4): wardrobe + try-on + paywall.
