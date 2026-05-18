-- ============================================================
-- 026_drop_duplicate_indexes.sql
-- 删除与约束重复的冗余索引
-- ============================================================
-- 说明：
--   - UNIQUE 约束和 PRIMARY KEY 会自动创建索引
--   - 以下索引与约束创建的索引完全重复，需要删除以节省空间
-- ============================================================

BEGIN;

-- 005: idx_episodes_number — 与 episodes 表的 UNIQUE (video_id, number) 约束重复
DROP INDEX IF EXISTS idx_episodes_number;

-- 002: idx_user_oauth_provider — 与 user_oauth 表的 UNIQUE (provider, provider_account_id) 约束重复
DROP INDEX IF EXISTS idx_user_oauth_provider;

-- 005: idx_user_favorites_user_video — 与 user_favorites 表的 PRIMARY KEY (user_id, video_id) 重复
DROP INDEX IF EXISTS idx_user_favorites_user_video;

-- 002: idx_users_username — 与 users 表的 UNIQUE (username) 约束重复
DROP INDEX IF EXISTS idx_users_username;

-- 003: idx_ranks_video_id — 与 ranks 表的 UNIQUE (video_id, type, period_date) 约束前缀重复
DROP INDEX IF EXISTS idx_ranks_video_id;

-- 008: idx_tags_name — 与 tags 表的 UNIQUE (name) 约束重复
DROP INDEX IF EXISTS idx_tags_name;

-- 008: idx_tags_slug — 与 tags 表的 UNIQUE (slug) 约束重复
DROP INDEX IF EXISTS idx_tags_slug;

-- 008: idx_video_tags_video_id — 与 video_tags 表的 PRIMARY KEY (video_id, tag_id) 前缀重复
DROP INDEX IF EXISTS idx_video_tags_video_id;

-- 010: idx_device_fingerprints_hash — 与 device_fingerprints 表的 UNIQUE (fingerprint_hash) 约束重复
DROP INDEX IF EXISTS idx_device_fingerprints_hash;

-- 021: idx_payment_orders_no — 与 payment_orders 表的 UNIQUE (order_no) 约束重复
DROP INDEX IF EXISTS idx_payment_orders_no;

-- 003: idx_watch_histories_user_id — 与 user_watch_histories 表的 PRIMARY KEY (user_id, video_id) 前缀重复
DROP INDEX IF EXISTS idx_watch_histories_user_id;

-- -----------------------------------------------------------
-- 记录迁移
-- -----------------------------------------------------------
INSERT INTO schema_migrations (filename) VALUES ('026_drop_duplicate_indexes.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
