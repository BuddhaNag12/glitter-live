-- D1 (SQLite) schema ported from supabase/migrations/0001..0005.

CREATE TABLE IF NOT EXISTS wallpapers (
    id TEXT PRIMARY KEY,
    kind TEXT NOT NULL DEFAULT 'live' CHECK (kind IN ('live', 'still')),
    title TEXT NOT NULL CHECK (length(trim(title)) BETWEEN 1 AND 80),
    category TEXT NOT NULL CHECK (length(trim(category)) > 0),
    video_path TEXT,
    image_path TEXT,
    thumbnail_path TEXT NOT NULL CHECK (thumbnail_path LIKE 'thumbnails/%'),
    duration_seconds REAL CHECK (duration_seconds IS NULL OR (duration_seconds > 0 AND duration_seconds <= 5)),
    width INTEGER NOT NULL CHECK (width > 0),
    height INTEGER NOT NULL CHECK (height > 0),
    creator_name TEXT,
    creator_url TEXT,
    is_published INTEGER NOT NULL DEFAULT 1 CHECK (is_published IN (0, 1)),
    is_featured INTEGER NOT NULL DEFAULT 0 CHECK (is_featured IN (0, 1)),
    is_category_cover INTEGER NOT NULL DEFAULT 0 CHECK (is_category_cover IN (0, 1)),
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    CHECK (
        (kind = 'live' AND video_path LIKE 'videos/%' AND duration_seconds IS NOT NULL AND image_path IS NULL)
        OR (kind = 'still' AND image_path LIKE 'images/%' AND video_path IS NULL AND duration_seconds IS NULL)
    )
);

CREATE INDEX IF NOT EXISTS wallpapers_category_sort_idx
    ON wallpapers (category, sort_order, created_at DESC);

CREATE INDEX IF NOT EXISTS wallpapers_published_sort_idx
    ON wallpapers (is_published, sort_order, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS wallpapers_one_cover_per_category
    ON wallpapers (category) WHERE is_category_cover = 1;

CREATE TABLE IF NOT EXISTS category_covers (
    category TEXT PRIMARY KEY CHECK (length(trim(category)) > 0),
    image_path TEXT NOT NULL CHECK (image_path LIKE 'covers/%'),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE IF NOT EXISTS ad_rewards (
    transaction_id TEXT PRIMARY KEY,
    install_id TEXT NOT NULL,
    nonce TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    redeemed_at TEXT
);

CREATE INDEX IF NOT EXISTS ad_rewards_nonce ON ad_rewards (nonce, install_id);
CREATE INDEX IF NOT EXISTS ad_rewards_redeemed ON ad_rewards (redeemed_at) WHERE redeemed_at IS NOT NULL;

CREATE TABLE IF NOT EXISTS generation_reports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    install_id TEXT NOT NULL CHECK (length(install_id) <= 64),
    prompt TEXT NOT NULL CHECK (length(prompt) <= 600),
    reason TEXT NOT NULL CHECK (reason IN ('sexual', 'violent', 'hateful', 'other')),
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
