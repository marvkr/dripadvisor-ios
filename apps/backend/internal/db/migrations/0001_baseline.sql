-- +goose Up
-- +goose StatementBegin

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ========================================================================
-- users
-- ========================================================================
CREATE TABLE users (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    apple_sub          TEXT UNIQUE,
    google_sub         TEXT UNIQUE,
    facebook_id        TEXT UNIQUE,
    email              TEXT UNIQUE CHECK (email IS NULL OR char_length(email) <= 320),
    phone_e164         TEXT UNIQUE CHECK (phone_e164 IS NULL OR phone_e164 ~ '^\+[1-9]\d{1,14}$'),
    phone_hash         BYTEA,
    username           TEXT UNIQUE CHECK (username IS NULL OR char_length(username) BETWEEN 3 AND 30),
    display_name       TEXT CHECK (display_name IS NULL OR char_length(display_name) <= 100),
    avatar_url         TEXT CHECK (avatar_url IS NULL OR char_length(avatar_url) <= 2048),
    account_tier       TEXT NOT NULL DEFAULT 'free' CHECK (account_tier IN ('free','pro','lifetime')),
    pro_expires_at     TIMESTAMPTZ,
    onboarded_at       TIMESTAMPTZ,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at         TIMESTAMPTZ
);
CREATE INDEX idx_users_phone_hash ON users (phone_hash) WHERE phone_hash IS NOT NULL;
CREATE INDEX idx_users_account_tier ON users (account_tier) WHERE deleted_at IS NULL;

-- ========================================================================
-- ai_agents (stylist as first-class participant)
-- ========================================================================
CREATE TABLE ai_agents (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name         TEXT NOT NULL CHECK (char_length(name) <= 60),
    avatar_url   TEXT CHECK (avatar_url IS NULL OR char_length(avatar_url) <= 2048),
    persona      TEXT NOT NULL CHECK (char_length(persona) <= 80),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed the default stylist agent.
INSERT INTO ai_agents (id, name, avatar_url, persona)
VALUES ('11111111-1111-1111-1111-111111111111', 'Drip Stylist', NULL, 'drip_stylist_v1');

-- ========================================================================
-- wardrobe_items
-- ========================================================================
CREATE TABLE wardrobe_items (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name           TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 200),
    brand          TEXT NOT NULL CHECK (char_length(brand) BETWEEN 1 AND 200),
    category       TEXT NOT NULL CHECK (category IN ('top','bottom','dress','shoes','outerwear','accessory')),
    image_url      TEXT CHECK (image_url IS NULL OR char_length(image_url) <= 2048),
    source_url     TEXT CHECK (source_url IS NULL OR char_length(source_url) <= 2048),
    tags           TEXT[] NOT NULL DEFAULT '{}',
    color_primary  TEXT CHECK (color_primary IS NULL OR color_primary ~ '^#[0-9A-Fa-f]{6}$'),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at     TIMESTAMPTZ
);
CREATE INDEX idx_wardrobe_items_user_category_created
    ON wardrobe_items (user_id, category, created_at DESC)
    WHERE deleted_at IS NULL;
CREATE INDEX idx_wardrobe_items_tags ON wardrobe_items USING GIN (tags);

-- ========================================================================
-- wardrobe_ingestions (decoupled upload/extraction pipeline)
-- ========================================================================
CREATE TABLE wardrobe_ingestions (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    source_url     TEXT CHECK (source_url IS NULL OR char_length(source_url) <= 2048),
    raw_image_key  TEXT CHECK (raw_image_key IS NULL OR char_length(raw_image_key) <= 512),
    source_hash    TEXT NOT NULL CHECK (char_length(source_hash) = 64),
    status         TEXT NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending','extracting','done','failed')),
    retry_count    INT NOT NULL DEFAULT 0 CHECK (retry_count >= 0),
    item_id        UUID REFERENCES wardrobe_items(id) ON DELETE SET NULL,
    error_message  TEXT CHECK (error_message IS NULL OR char_length(error_message) <= 1000),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_wardrobe_ingestions_user_hash ON wardrobe_ingestions (user_id, source_hash);
CREATE INDEX idx_wardrobe_ingestions_status ON wardrobe_ingestions (status) WHERE status IN ('pending','extracting');

-- ========================================================================
-- outfits
-- ========================================================================
CREATE TABLE outfits (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id               UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    composite_image_url   TEXT CHECK (composite_image_url IS NULL OR char_length(composite_image_url) <= 2048),
    thumbnail_url         TEXT CHECK (thumbnail_url IS NULL OR char_length(thumbnail_url) <= 2048),
    occasion              TEXT CHECK (occasion IS NULL OR char_length(occasion) <= 40),
    tags                  TEXT[] NOT NULL DEFAULT '{}',
    visibility            TEXT NOT NULL DEFAULT 'friends' CHECK (visibility IN ('private','friends','public')),
    source                TEXT NOT NULL DEFAULT 'manual' CHECK (source IN ('manual','ai-stylist','shared-remix')),
    remix_of              UUID REFERENCES outfits(id) ON DELETE SET NULL,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at            TIMESTAMPTZ
);
CREATE INDEX idx_outfits_user_created ON outfits (user_id, created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_outfits_tags ON outfits USING GIN (tags);
CREATE INDEX idx_outfits_remix_of ON outfits (remix_of) WHERE remix_of IS NOT NULL;

-- ========================================================================
-- outfit_items (which wardrobe items fill which slot)
-- ========================================================================
CREATE TABLE outfit_items (
    outfit_id    UUID NOT NULL REFERENCES outfits(id) ON DELETE CASCADE,
    item_id      UUID NOT NULL REFERENCES wardrobe_items(id) ON DELETE CASCADE,
    slot         TEXT NOT NULL CHECK (slot IN ('top','bottom','dress','shoes','outerwear','accessory')),
    PRIMARY KEY (outfit_id, slot)
);
CREATE INDEX idx_outfit_items_item ON outfit_items (item_id);

-- ========================================================================
-- chats + participants
-- ========================================================================
CREATE TABLE chats (
    id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type                      TEXT NOT NULL CHECK (type IN ('direct','group')),
    name                      TEXT CHECK (name IS NULL OR char_length(name) <= 80),
    icon_url                  TEXT CHECK (icon_url IS NULL OR char_length(icon_url) <= 2048),
    created_by                UUID REFERENCES users(id) ON DELETE SET NULL,
    last_message_at           TIMESTAMPTZ,
    last_message_preview      TEXT CHECK (last_message_preview IS NULL OR char_length(last_message_preview) <= 200),
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_chats_last_message_at ON chats (last_message_at DESC NULLS LAST);

CREATE TABLE chat_participants (
    chat_id                 UUID NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    user_id                 UUID REFERENCES users(id) ON DELETE CASCADE,
    agent_id                UUID REFERENCES ai_agents(id) ON DELETE CASCADE,
    role                    TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('member','admin')),
    joined_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_read_seq           BIGINT NOT NULL DEFAULT 0,
    notifications_enabled   BOOLEAN NOT NULL DEFAULT TRUE,
    shares_wardrobe         BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT one_participant_kind CHECK (
        (user_id IS NOT NULL AND agent_id IS NULL)
        OR (user_id IS NULL AND agent_id IS NOT NULL)
    )
);
CREATE UNIQUE INDEX uq_chat_participants_user ON chat_participants (chat_id, user_id) WHERE user_id IS NOT NULL;
CREATE UNIQUE INDEX uq_chat_participants_agent ON chat_participants (chat_id, agent_id) WHERE agent_id IS NOT NULL;
CREATE INDEX idx_chat_participants_user ON chat_participants (user_id) WHERE user_id IS NOT NULL;

-- ========================================================================
-- messages (hot table, ordering by per-chat seq)
-- ========================================================================
CREATE TABLE messages (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id            UUID NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    sender_user_id     UUID REFERENCES users(id) ON DELETE SET NULL,
    sender_agent_id    UUID REFERENCES ai_agents(id) ON DELETE SET NULL,
    seq                BIGINT NOT NULL,
    body               TEXT CHECK (body IS NULL OR char_length(body) <= 4000),
    attachment_type    TEXT CHECK (attachment_type IS NULL OR attachment_type IN ('outfit','item','image','link')),
    attachment_id      UUID,
    reply_to_id        UUID REFERENCES messages(id) ON DELETE SET NULL,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    edited_at          TIMESTAMPTZ,
    deleted_at         TIMESTAMPTZ,
    CONSTRAINT one_sender_kind CHECK (
        (sender_user_id IS NOT NULL AND sender_agent_id IS NULL)
        OR (sender_user_id IS NULL AND sender_agent_id IS NOT NULL)
    ),
    CONSTRAINT has_body_or_attachment CHECK (
        body IS NOT NULL OR attachment_type IS NOT NULL
    )
);
CREATE UNIQUE INDEX uq_messages_chat_seq ON messages (chat_id, seq);
CREATE INDEX idx_messages_chat_created ON messages (chat_id, created_at DESC);
CREATE INDEX idx_messages_reply_to ON messages (reply_to_id) WHERE reply_to_id IS NOT NULL;

-- ========================================================================
-- message_reactions (tapbacks)
-- ========================================================================
CREATE TABLE message_reactions (
    message_id   UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    emoji        TEXT NOT NULL CHECK (char_length(emoji) BETWEEN 1 AND 16),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (message_id, user_id, emoji)
);
CREATE INDEX idx_message_reactions_message ON message_reactions (message_id);

-- ========================================================================
-- inbox (precomputed per-user-per-chat state)
-- ========================================================================
CREATE TABLE inbox (
    user_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    chat_id        UUID NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    last_read_seq  BIGINT NOT NULL DEFAULT 0,
    unread_count   INT NOT NULL DEFAULT 0 CHECK (unread_count >= 0),
    pinned         BOOLEAN NOT NULL DEFAULT FALSE,
    muted_until    TIMESTAMPTZ,
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, chat_id)
);
CREATE INDEX idx_inbox_user_pinned_updated ON inbox (user_id, pinned DESC, updated_at DESC);

-- ========================================================================
-- friendships
-- ========================================================================
CREATE TABLE friendships (
    user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    friend_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status       TEXT NOT NULL CHECK (status IN ('pending','accepted','blocked')),
    source       TEXT NOT NULL CHECK (source IN ('contacts','invite_link','search')),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, friend_id),
    CHECK (user_id <> friend_id)
);
CREATE INDEX idx_friendships_friend ON friendships (friend_id, status);

-- ========================================================================
-- devices (APNs tokens)
-- ========================================================================
CREATE TABLE devices (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    apns_token       TEXT CHECK (apns_token IS NULL OR char_length(apns_token) <= 512),
    platform         TEXT NOT NULL CHECK (platform IN ('ios','android')),
    last_active_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_devices_apns_token ON devices (apns_token) WHERE apns_token IS NOT NULL;
CREATE INDEX idx_devices_user ON devices (user_id);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP TABLE IF EXISTS devices;
DROP TABLE IF EXISTS friendships;
DROP TABLE IF EXISTS inbox;
DROP TABLE IF EXISTS message_reactions;
DROP TABLE IF EXISTS messages;
DROP TABLE IF EXISTS chat_participants;
DROP TABLE IF EXISTS chats;
DROP TABLE IF EXISTS outfit_items;
DROP TABLE IF EXISTS outfits;
DROP TABLE IF EXISTS wardrobe_ingestions;
DROP TABLE IF EXISTS wardrobe_items;
DROP TABLE IF EXISTS ai_agents;
DROP TABLE IF EXISTS users;
-- +goose StatementEnd
