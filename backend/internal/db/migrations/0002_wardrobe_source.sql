-- +goose Up
-- +goose StatementBegin

-- Adds wishlist vs owned distinction + per-item metadata (size, material,
-- price, usage tracking). See README "v1.1 Chat Design" + "Wardrobe sources".
ALTER TABLE wardrobe_items
    ADD COLUMN source        TEXT NOT NULL DEFAULT 'owned'
        CHECK (source IN ('owned','wishlist')),
    ADD COLUMN size          TEXT CHECK (size IS NULL OR char_length(size) <= 40),
    ADD COLUMN material      TEXT CHECK (material IS NULL OR char_length(material) <= 120),
    ADD COLUMN price_paid    NUMERIC(10,2) CHECK (price_paid IS NULL OR price_paid >= 0),
    ADD COLUMN retail_price  NUMERIC(10,2) CHECK (retail_price IS NULL OR retail_price >= 0),
    ADD COLUMN currency      TEXT CHECK (currency IS NULL OR currency ~ '^[A-Z]{3}$'),
    ADD COLUMN last_worn_at  TIMESTAMPTZ,
    ADD COLUMN wear_count    INTEGER NOT NULL DEFAULT 0 CHECK (wear_count >= 0);

CREATE INDEX idx_wardrobe_items_user_source
    ON wardrobe_items (user_id, source, created_at DESC)
    WHERE deleted_at IS NULL;

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

DROP INDEX IF EXISTS idx_wardrobe_items_user_source;
ALTER TABLE wardrobe_items
    DROP COLUMN IF EXISTS wear_count,
    DROP COLUMN IF EXISTS last_worn_at,
    DROP COLUMN IF EXISTS currency,
    DROP COLUMN IF EXISTS retail_price,
    DROP COLUMN IF EXISTS price_paid,
    DROP COLUMN IF EXISTS material,
    DROP COLUMN IF EXISTS size,
    DROP COLUMN IF EXISTS source;

-- +goose StatementEnd
