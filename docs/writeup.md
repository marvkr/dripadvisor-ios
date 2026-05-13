# DripAdvisor — Decision Writeup

This file records the **why** behind key architectural and product decisions. README.md states *what* we're doing; writeup.md explains *why we chose it over alternatives* so future-us doesn't re-litigate settled trades.

Date of initial writeup: **2026-04-22**.
Decisions are listed roughly in order of how hard they are to reverse (hardest first).

---

## 1. Self-hosted Postgres + Redis on a single Hetzner VPS (not Neon + Upstash)

### Decision
Run Go + Postgres + Redis co-located on one Hetzner Cloud VPS. Start on CCX13 (~€12.50/mo, 2 vCPU / 8 GB RAM). Upgrade path stays inside VPS-land: CCX13 → CCX23 → CCX43 → AX162-R dedicated (96 cores / 1 TB RAM, ~€400/mo).

### Alternatives considered
- **Neon (managed Postgres) + Upstash (managed Redis).** Serverless scale-to-zero, branching, fully managed backups/HA.
- **AWS RDS + ElastiCache.** Enterprise-grade managed services. ~$100+/mo minimum.
- **Fly.io Postgres clusters.** Global managed Postgres. ~$50/mo minimum.

### Why self-hosted won
**Scale.** A single Hetzner AX162-R dedicated box can sustain ~100k writes/sec on Postgres, ~500k reads/sec warm-cache, ~1M Redis ops/sec, and ~1M concurrent WebSockets on Go. For DripAdvisor at 1M DAU × 100 msgs/day, peak load is ~5,000 msgs/sec — **5% of a single box's capacity.** We probably never outgrow one machine.

Precedent for VPS-only at massive scale:
- **Pieter Levels** — Nomadlist/RemoteOK, **$3M+ ARR on a single Hetzner box** for years (solo dev).
- **Stack Overflow** — 2B+ pageviews/month on ~9 physical servers, two SQL Servers. No managed Postgres.
- **Plenty of Fish** — 60M users, 3 servers, 2 employees at peak.
- **WhatsApp** — 450M users on ~150 bare-metal servers at acquisition. No managed services.

**Cost.** €12.50/mo vs. ~$80–$120/mo managed equivalent. ~6x–10x cheaper. At closed-beta scale with zero paying users, cost matters.

**Latency.** Postgres/Redis on localhost = <0.1ms round-trips. Upstash from Hetzner = ~20–50ms depending on region. Every `redis.INCR chat:{id}:seq` pays that latency on managed. Compounds in chat UX.

**No vendor lock-in.** Standard Postgres + Redis means `pg_dump` and walk away at any time.

**Simpler mental model.** One box, one systemd unit, one log stream, one backup cron. Ops burden is minimal for a solo dev.

### What we give up
- **HA.** Hetzner Cloud advertises ~99.9% uptime = ~8 hours of downtime/year. Neon promises 99.95% = ~4 hours. Delta is ~4 hours/year. For a fashion app, that's invisible.
- **Preview-branch DBs** (Neon's killer feature for teams). We're solo; one staging DB is enough.
- **Auto-scaling.** We scale vertically by resizing the VPS. Each tier is a 30-minute migration window.

### What forced my earlier wrong recommendation
Initial README draft used Neon + Upstash because that's the "enterprise default" I reached for. The user rightly pushed back: *"a VPS works even for millions of users no?"* Answer: yes. The managed-services narrative is targeted at teams with ops FTEs and enterprise SLAs; it's oversold for solo consumer apps.

### When we'd actually migrate
Not on a timeline. Only when one of these specific triggers fires:
1. **Geographic expansion** — non-EU users become majority traffic → add a second Hetzner VPS in that region (still not managed).
2. **Compliance** — SOC 2 / HIPAA audit requires documented managed services with their attestations.
3. **Ops is >10% of our time** — we'd rather pay $500/mo to Neon than spend hours/week on Postgres tuning.
4. **Physical limits hit** — AX162-R dedicated box is saturated on CPU, RAM, or disk I/O. This is a "millions of DAU" problem, not a "thousand users" problem.

Everything else (backup/restore, upgrades, replication for read scale) is solvable within VPS-land.

### Reversibility
High. Moving from self-hosted to Neon later is `pg_dump | pg_restore`. Moving in the other direction is the same. One migration maintenance window.

---

## 2. River (Postgres-backed job queue) over Asynq (Redis-backed)

### Decision
Use River for all durable async jobs (`extract_garment`, `ingest_bookmark`, `compose_outfit`, `stylist_reply`, `push_send`, `aged_message_purge`). Use raw `redis.PUBLISH` for ephemeral chat fan-out + typing indicators only.

### Alternatives considered
- **Asynq** (Redis Lists, Go-native, polished dashboard).
- **Cloudflare Queues / AWS SQS** (fully managed cloud queues).
- **Go channels + Postgres "outbox" table** (roll our own).

### Why River won
**Durability argument (verified in system-design-mcp's Message Brokers 101):**
- Redis Lists + Pub/Sub are at-most-once without Streams; only Streams give at-least-once, and even those rely on RDB persistence.
- Redis AOF `fsync always` is slow; `fsync everysec` loses up to 1 second on crash.
- Postgres WAL with `synchronous_commit = on` loses zero committed transactions on crash.
- **Rule:** the queue must be at least as durable as the data it writes. Since our source-of-truth data lives in Postgres, the queue should too.

**Transactional enqueue.** River enqueues a job in the same Postgres transaction as the DB write that triggered it. This eliminates a whole class of distributed-systems bugs: the job runs iff the transaction commits. With a Redis-backed queue, the DB write and the enqueue can diverge.

**Zero extra infra.** We're already running Postgres; River adds zero additional services.

**Slack parallel** (confirmed in system-design-mcp's Slack case study): Slack uses Kafka (durable) for message-of-record + Redis (fast) for in-flight state. Our River (Postgres) + raw Redis PUBLISH mirrors that split, at smaller scale.

### What we give up
- ~2x lower throughput ceiling (River: ~50k jobs/sec; Asynq: ~100k+). Irrelevant at our scale — we'll process maybe 10–50 jobs/sec even at 100k DAU.
- Asynq's polished dashboard UI. River's is fine.

### Reversibility
High. Jobs are pure Go functions with args; switching queue libraries is a 1-week refactor.

---

## 3. `TEXT` + `CHECK` constraints (not `VARCHAR(n)`)

### Decision
All Postgres string columns use `TEXT` with `CHECK (char_length(col) <= n)` for length constraints. Never `VARCHAR(n)`.

### Alternatives considered
- `VARCHAR(n)` with per-column lengths.
- `VARCHAR(255)` blanket default.

### Why `TEXT` + `CHECK` won
In Postgres specifically, `VARCHAR(n)`, `VARCHAR`, and `TEXT` all use the same `varlena` storage. There is **zero performance or storage difference.** The only thing `VARCHAR(n)` adds is a length cap — which a CHECK constraint provides more flexibly.

**Operational advantage:** changing a CHECK constraint is `DROP CONSTRAINT + ADD CONSTRAINT` — cheap, no table rewrite. Changing `VARCHAR(n)` to a smaller size rewrites the whole table with an exclusive lock. On a 10M+ row `messages` table this is a multi-minute production outage.

**`VARCHAR(255)` cargo-cult.** The `255` convention comes from MySQL 4.x where 256 chars crossed a byte-length-prefix boundary. That optimization has been obsolete for 20+ years and never applied to Postgres. It's a MySQL cultural hangover.

**Portability concern addressed.** Realistic migration paths from self-hosted Postgres are all Postgres-compatible (RDS/Aurora/Cockroach/Neon). Migration to a non-Postgres SQL engine would require a schema rewrite anyway; type hedging today buys nothing.

### Reversibility
Trivial — CHECK constraint is `ALTER TABLE DROP CONSTRAINT … ADD CONSTRAINT …`.

---

## 4. Per-chat `seq` integer (not timestamps) for message ordering

### Decision
Every message in a chat gets a per-chat monotonic `seq BIGINT`, assigned via `redis.INCR chat:{id}:seq`. All client-side ordering is by `seq`. `created_at` is stored but decorative.

### Alternatives considered
- **Sort by `created_at`.** Naive default.
- **Client-supplied timestamps.**
- **ULIDs / KSUIDs** (time-sortable IDs).

### Why per-chat `seq` won
Confirmed by WhatsApp breakdown and iMessage/Slack patterns:
- **Clock skew between servers.** Two Go processes with clocks off by 50ms produce out-of-order timestamps under concurrent writes.
- **Tie resolution.** Two messages with identical millisecond timestamps have no order-breaking rule.
- **Client trust.** Client clocks lie. Timestamps from clients are not authoritative.
- **Redis `INCR` is atomic and sub-millisecond.** Under 10k concurrent writes in one chat, it hands out 1, 2, 3, 4... with zero collisions and no row locks (unlike `SELECT nextval` on Postgres).

**Cold-start hardening.** On Redis restart, seed the key from `SELECT MAX(seq) FROM messages WHERE chat_id=$1` before first `INCR`. Prevents the "Redis crashed, lost keys, now `seq` restarts at 1" collision class.

**Piggyback on heartbeats.** WhatsApp's pattern: every server heartbeat carries the user's latest known `seq`. Clients detect gaps within 15s even during quiet periods. Adopted in our spec.

### Reversibility
Medium. `seq` is load-bearing for client ordering; changing requires a migration + client upgrade. But the column stays; only the assignment mechanism changes.

---

## 5. Per-`user:{id}` Redis pub/sub channels (not per-chat)

### Decision
Redis pub/sub channels keyed by `user:{id}`, not `chat:{chat_id}`. One subscription per connected user. For group chats with ≥25 participants (rare), also publish to a chat-level channel.

### Alternatives considered
- Per-`chat:{id}` channels.
- Per-user AND per-chat (redundant).

### Why per-user won
From the WhatsApp breakdown: **DripAdvisor traffic is 1:1-dominated** (user-to-friend + user-to-stylist-agent). Per-chat channels mean a Chat Server subscribes to N channels per connected user (one per chat they're in) — at 250 chats/user and 100k concurrent users = 25M subscriptions. Per-user means 1 channel per user = 100k subscriptions. 250x fewer.

The per-user approach only loses to per-chat when chats are large (>100 participants) and users are in few chats. Not our model.

### Reversibility
Easy. Channel key format is a server-side constant.

---

## 6. Body reference photos stay on-device (SwiftData + CloudKit private DB)

### Decision
Full-body reference photos (used for try-on composition) never leave the device except transiently during a try-on request. They're stored only in SwiftData + CloudKit private DB (user's iCloud). Uploaded to the Go backend during try-on, forwarded to Gemini, dropped immediately after response. Never persisted in R2 or our Postgres.

### Alternatives considered
- Store in R2 with presigned URLs.
- Store encrypted blobs in Postgres.
- Store only a hash + re-request from client on each try-on.

### Why on-device won
**Privacy.** Body photos are the most sensitive data the user gives us. "We never store your body photo on our servers" is both honest and a marketable promise (Flo cycle, Lensa avatars all lean into similar promises).

**Legal exposure.** Storing body photos at scale invites GDPR/CCPA data-subject-access complexity, EU AI Act disclosure obligations, and potential BIPA (biometric) litigation in the US. On-device storage sidesteps all of it.

**Phone-switch story.** CloudKit private DB sync = user can switch phones without re-uploading photos. CloudKit private DB means *Apple* can't read it either; our server never sees the data.

**Transient upload model** — during try-on we upload the photo, immediately forward to Gemini, drop bytes when response returns. The server holds it in memory for <10s and never writes to disk. No persistence = no subpoena risk, no leak risk, no data-retention policy to write.

### What we give up
- Multi-device (iPad + iPhone) = can use CloudKit private DB, works.
- Non-iCloud users = must re-capture photo on new phone. Acceptable friction.
- No server-side image editing pipeline possibilities in the future. If we add those, we revisit.

### Reversibility
Hard. Once we make the "we never store your body photo" promise in onboarding/marketing copy, walking it back is reputation-destroying. Design choice locks us in.

---

## 7. Gemini Nano Banana Pro exclusively (no Seedream/Flux/SDXL)

### Decision
All image generation (outfit compositing, try-on rendering) uses Gemini Nano Banana Pro (`gemini-3-pro-image-preview`) via Google's Go SDK (`google.golang.org/genai`). Nano Banana 2 (`gemini-3.1-flash-image-preview`) for low-cost ops.

### Alternatives considered
- **Seedream** (ByteDance's image model).
- **Flux** (Black Forest Labs).
- **SDXL / Stable Diffusion** variants.
- **OpenAI DALL·E 3 / gpt-image-1.**

### Why Nano Banana Pro won
- **14 reference image support** — we need to pass the body photo + top + bottom + shoes + accessories simultaneously. This is the only widely available model with this many refs.
- **Identity preservation** across reference images — Nano Banana is specifically tuned for this.
- **Pricing** — Gemini's per-image cost is competitive with Flux.
- **Go SDK** — first-class support in `google.golang.org/genai`.

### What we give up
- White-background output only (no transparent-bg from Gemini). Compensated by on-device Apple Vision background removal.
- Vendor dependency on Google Gemini pricing/availability. If Google sunsets or prices out, we switch — but the try-on prompt format is transferable.

### Reversibility
Medium. The compositing prompts are model-specific. Swapping models = re-tuning prompts + a few weeks of quality testing.

---

## 8. Apple Vision on-device background removal (not server-side)

### Decision
When the user adds a wardrobe item (screenshot or photo), background removal happens **on-device** via Apple's `VNGenerateForegroundInstanceMaskRequest` (iOS 17+). Produces transparent-bg PNG. Server receives the already-processed PNG.

### Alternatives considered
- Server-side bg removal via `rembg` / `remove.bg` API.
- Gemini-based bg removal (expensive, white-bg output).
- Skip bg removal (store original screenshots).

### Why on-device won
- **Free** (no per-image cost).
- **Private** (screenshot never uploaded before processing).
- **Fast** (~1s on modern iPhone).
- **Good enough quality** for consumer-grade clothing items.

### What we give up
- Android users would need a different pipeline (deferred to v2).
- iOS <17 users excluded (minimum deployment target is iOS 17+ for this and other modern APIs).

### Reversibility
Easy. Swap in a server-side fallback anytime.

---

## 9. 4-week closed-beta v1 cut (wardrobe + try-on + paywall only; chat/social to v1.1)

### Decision
v1 ships only the core monetization loop: wardrobe ingest → AI try-on → soft paywall. No chat, no friends, no groups, no AI stylist agent, no widgets. Everything social ships in v1.1 (weeks 5–8).

### Alternatives considered
- 8-week all-in v1 (chat + social + agent together).
- 12-week "polished" v1 with App Store review buffer.
- 2-week smoke test (just wardrobe + demo try-on, no paywall).

### Why narrow v1 won
**DoorDash menu-transcription "baseline MVP" pattern** (from system-design-mcp case study): *"The first step was to prove whether menus could be digitized at all in an automated way."* Prove the core hypothesis before layering features.

**Revenue-loop-first logic.** The entire business thesis is "women will pay for AI try-on." If that fails, no chat experience saves the company. Validate the paying customer before building the social layer. Opal, Cal AI, Lensa all launched this way.

**WhatsApp's "clarity over cleverness"** — small, focused components. Shipping chat + AI agent + groups + widgets all at once multiplies the blast radius of bugs.

**TestFlight iteration.** A 4-week cycle means we hit TestFlight closed beta at week 4, get ~50–200 real users, and have 4+ more weeks to iterate on retention data before public launch.

### What we give up
- Slower virality start (no social at launch). Mitigated by Remix deep links + watermarked share coming in v1.1.
- Competitive risk that a similar app launches first with a fuller feature set. Low probability.

### Reversibility
Easy — v1.1 is the chat layer, always planned.

---

## 10. Soft paywall with free try-on quota (not hard wall)

### Decision
Free tier gets 3 try-ons + 2 AI-stylist replies/week. Paywall shows on quota exhaustion. Trial toggle (7 days) is off by default on the paywall screen.

### Alternatives considered
- Hard paywall at onboarding end (pay before seeing any output).
- Free-forever core + Pro for advanced features.
- Trial-first (7 days free, then wall).

### Why soft-paywall-with-quota won
**Industry norm** for AI consumer apps (Lensa, Cal AI, Opal pattern). Hard-walling before the "wow" moment kills conversion — users can't evaluate whether the product is worth paying for.

**Quota-based metering** lets the user feel the magic (first successful try-on), bond with the output, *then* hit the wall. The conversion rate on "you've used 3/3 try-ons this week, unlock unlimited for $39/year" beats a pre-usage paywall by a documented 2–3x in the Lensa/Cal AI cohort.

**Lensa's discount-toggle pattern** — trial off by default means users who click Continue go straight to annual purchase. Users who hesitate toggle trial on. This gets higher revenue-per-user than trial-first funnels.

### Reversibility
Trivial. Quota limits are server-side configuration.

---

## 11. iMessage-clone chat (not simple chat)

### Decision
Chat ships as a full iMessage clone: tapbacks, typing indicators, read receipts, reply threading, streaming AI replies, stickers, voice notes, message effects. 1:1 and group. Shipped in v1.1.

### Alternatives considered
- Simple SMS-style chat (send, receive, done).
- WhatsApp-style (groups + reactions, no message effects).
- No chat at all (comments on outfits only).

### Why full iMessage clone won
- **The user's demo feature expectation.** DripAdvisor targets women who expect polished iMessage-tier UX; cheap chat feels cheap and kills retention.
- **Stylist agent needs a conversational surface.** A one-shot comment thread doesn't support back-and-forth refinement ("make it more formal" → agent re-renders).
- **Social sharing loop.** The main viral mechanic is "share outfit to group, friends react/remix" — this requires reactions + threads minimum.

### What we give up
- Significant engineering cost (weeks 5–6 of v1.1).
- Complexity in the schema (reactions, threads, edits all separately modeled).

### Reversibility
Hard. Schema commitments around `message_reactions`, `reply_to_id`, `thread-id` are durable. Backing out = major migration.

---

## 12. On-device body photos — **not** stored in R2 — was once a managed-services-for-HA argument I'd made

### Decision
(Already covered in §6.) But worth noting: I also initially recommended R2 "for scale." That was also overkill. For v1 closed beta, local disk on the Hetzner box would work. We use R2 because Cloudflare's zero egress pricing genuinely helps image serving at scale, and it's commodity behind the CDN.

### When R2 is worth it
When we expect >100 GB of image storage + high read traffic. Outfit thumbnails served to friends' feeds fits this.

### When local disk would have been fine
Pure wardrobe PNGs for a single user, no social layer.

### Current status
R2 is the right call even at v1 because outfit composites will quickly exceed 100 GB with any traction.

---

## Meta — What this writeup is NOT for

- **Implementation details.** Those live in code + comments.
- **Sprint planning.** That lives in linear / TODO tracker.
- **Tactical UI decisions.** Those live in Figma + Mobbin research folder.

This file captures **architectural "why" decisions that future-me or a future contributor might otherwise re-debate.** Add a new entry when you make a decision that's *hard to reverse* or that contradicts an "obvious default."

---

## Change log

- **2026-04-22** — Initial writeup. Documented decisions 1–12. Key change vs. earlier README: flipped the DB + Redis stack from managed (Neon + Upstash) to self-hosted on Hetzner VPS, after user challenge ("a VPS works even for millions of users no"). Evidence-backed: Pieter Levels / Stack Overflow / WhatsApp / Plenty of Fish precedents.
