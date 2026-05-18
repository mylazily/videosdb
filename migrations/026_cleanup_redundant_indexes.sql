-- ============================================================
-- 026_cleanup_redundant_indexes.sql
-- 清理冗余索引 + 补充缺失约束和索引
-- ============================================================
-- 说明：
--   - 删除被更优索引覆盖的冗余索引
--   - 补充 user_watch_histories 的 updated_at 触发器
--   - 补充 payment_orders 的 tg_user_id 索引
--   - 补充 share_links 的 (creator_fingerprint_id, video_id) 唯一约束
--   - 补充 coin_transactions 的幂等性保护（唯一约束）
--   - 补充 vip_subscriptions 的部分唯一索引
--   - videos.score DECIMAL(3,1) 范围说明注释
-- ============================================================

BEGIN;

-- -----------------------------------------------------------
-- P2 #10: 清理冗余索引
-- -----------------------------------------------------------

-- idx_videos_category_status_updated 被 idx_videos_cover_basic 覆盖
-- idx_videos_cover_basic 包含 (category, status, updated_at DESC) 并额外 INCLUDE 了常用字段
-- 保留覆盖索引，删除冗余索引
DROP INDEX IF EXISTS idx_videos_category_status_updated;

-- idx_comments_video_id 被 idx_comments_video_status_created 覆盖
-- 后者包含 (video_id, status, created_at DESC) 且有 WHERE 条件过滤
-- 保留更精确的部分索引，删除基础索引
DROP INDEX IF EXISTS idx_comments_video_id;

-- idx_danmakus_video_id 被 idx_danmakus_video_time 覆盖
-- 后者包含 (video_id, time_pos) 是更精确的复合索引
-- 保留复合索引，删除单列索引
DROP INDEX IF EXISTS idx_danmakus_video_id;

-- idx_watch_histories_user_id 被 idx_watch_histories_user_updated 覆盖
-- 后者包含 (user_id, updated_at DESC) 提供更好的排序支持
-- 保留排序优化索引，删除基础索引
DROP INDEX IF EXISTS idx_watch_histories_user_id;

-- -----------------------------------------------------------
-- P2 #27: user_watch_histories 缺少 updated_at 触发器
-- -----------------------------------------------------------

-- user_watch_histories 表有 updated_at 字段但没有自动更新触发器
-- 创建触发器确保 updated_at 在每次更新时自动刷新
CREATE TRIGGER trg_user_watch_histories_updated_at
    BEFORE UPDATE ON user_watch_histories
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

COMMENT ON TRIGGER trg_user_watch_histories_updated_at ON user_watch_histories
    IS '自动更新 user_watch_histories.updated_at 字段';

-- -----------------------------------------------------------
-- P2 #29: payment_orders 缺少 tg_user_id 索引
-- -----------------------------------------------------------

-- 添加 tg_user_id 索引，用于 Telegram 端用户的订单查询
CREATE INDEX IF NOT EXISTS idx_payment_orders_tg_user
    ON payment_orders(tg_user_id, created_at DESC)
    WHERE tg_user_id IS NOT NULL;

COMMENT ON INDEX idx_payment_orders_tg_user IS '支付订单 TG 用户 ID 索引（Telegram 端查询）';

-- -----------------------------------------------------------
-- P2 #30: share_links 缺少唯一约束
-- -----------------------------------------------------------

-- 同一用户对同一视频只应有一个活跃的分享链接
-- 添加 (creator_fingerprint_id, video_id) 唯一约束
CREATE UNIQUE INDEX IF NOT EXISTS idx_share_links_creator_video
    ON share_links(creator_fingerprint_id, video_id);

COMMENT ON INDEX idx_share_links_creator_video IS '分享链接创建者+视频唯一约束，防止重复创建';

-- -----------------------------------------------------------
-- P2 #31: coin_transactions 缺少幂等性保护
-- -----------------------------------------------------------

-- 通过 (fingerprint_id, transaction_type, reference_id) 唯一约束
-- 防止同一笔交易被重复记录（如网络重试导致的重复入账）
CREATE UNIQUE INDEX IF NOT EXISTS idx_coin_transactions_idempotent
    ON coin_transactions(fingerprint_id, transaction_type, reference_id)
    WHERE reference_id IS NOT NULL;

COMMENT ON INDEX idx_coin_transactions_idempotent IS '金币交易幂等性保护索引，防止重复入账';

-- -----------------------------------------------------------
-- P2 #32: vip_subscriptions 缺少唯一约束
-- -----------------------------------------------------------

-- 同一用户（fingerprint_id）同时只能有一个活跃订阅
-- 使用部分唯一索引，仅对活跃订阅生效
CREATE UNIQUE INDEX IF NOT EXISTS idx_vip_subscriptions_active_fp
    ON vip_subscriptions(fingerprint_id)
    WHERE is_active = TRUE AND fingerprint_id IS NOT NULL;

COMMENT ON INDEX idx_vip_subscriptions_active_fp IS 'VIP 订阅活跃唯一约束，同一指纹同时只能有一个活跃订阅';

-- 同一 TG 用户同时只能有一个活跃订阅
CREATE UNIQUE INDEX IF NOT EXISTS idx_vip_subscriptions_active_tg
    ON vip_subscriptions(tg_user_id)
    WHERE is_active = TRUE AND tg_user_id IS NOT NULL;

COMMENT ON INDEX idx_vip_subscriptions_active_tg IS 'VIP 订阅活跃唯一约束，同一 TG 用户同时只能有一个活跃订阅';

-- -----------------------------------------------------------
-- P2 #18: videos.score DECIMAL(3,1) 范围说明
-- -----------------------------------------------------------

-- 当前 videos.score 使用 DECIMAL(3,1)，范围 0.0 ~ 9.9
-- 对于影视评分系统，此范围完全足够（通常 0~10 分制）
-- 如需支持 10.0，可改为 DECIMAL(4,1)，但 9.9 已满足绝大多数场景
COMMENT ON COLUMN videos.score IS '视频评分（0.0~9.9，DECIMAL(3,1) 范围足够影视评分使用）';

-- -----------------------------------------------------------
-- 记录迁移
-- -----------------------------------------------------------
INSERT INTO schema_migrations (filename) VALUES ('026_cleanup_redundant_indexes.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
