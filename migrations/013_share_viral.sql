-- ============================================================
-- 013_share_viral.sql
-- 分享裂变系统：分享链接、点击追踪、奖励机制
-- ============================================================
-- 说明：
--   - 创建分享链接表，支持多种奖励类型（金币/时间）
--   - 创建分享点击记录表，追踪每次点击行为
--   - 分享码为 8 位随机码，唯一标识一个分享链接
--   - 支持最大解锁次数限制，防止滥用
-- ============================================================

BEGIN;

-- -----------------------------------------------------------
-- 枚举类型定义
-- -----------------------------------------------------------

-- 分享奖励类型枚举
CREATE TYPE share_reward_type AS ENUM (
    'coin',         -- 金币奖励
    'time'          -- 解锁时间奖励
);

COMMENT ON TYPE share_reward_type IS '分享奖励类型枚举';

-- 分享链接状态枚举
CREATE TYPE share_link_status AS ENUM (
    'active',       -- 活跃
    'expired',      -- 已过期
    'disabled',     -- 已禁用
    'completed'     -- 已达上限
);

COMMENT ON TYPE share_link_status IS '分享链接状态枚举';

-- -----------------------------------------------------------
-- 分享链接表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS share_links (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id                    UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    creator_fingerprint_id      UUID NOT NULL REFERENCES device_fingerprints(id) ON DELETE CASCADE,
    share_code                  VARCHAR(8) NOT NULL,            -- 8 位随机分享码
    click_count                 INTEGER NOT NULL DEFAULT 0,     -- 点击次数
    unlock_count                INTEGER NOT NULL DEFAULT 0,     -- 成功解锁次数
    max_unlocks                 INTEGER NOT NULL DEFAULT 5,     -- 最大解锁次数
    reward_type                 share_reward_type NOT NULL DEFAULT 'coin',  -- 奖励类型
    reward_amount               INTEGER NOT NULL DEFAULT 10,    -- 奖励数量（金币数或解锁分钟数）
    status                      share_link_status NOT NULL DEFAULT 'active',
    expires_at                  TIMESTAMPTZ,                    -- 过期时间（NULL 表示永不过期）
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_share_links_code UNIQUE (share_code)
);

COMMENT ON TABLE share_links IS '分享链接表：管理视频分享裂变链接';
COMMENT ON COLUMN share_links.id IS 'UUID v4 主键';
COMMENT ON COLUMN share_links.video_id IS '关联的视频 ID';
COMMENT ON COLUMN share_links.creator_fingerprint_id IS '创建者的设备指纹 ID';
COMMENT ON COLUMN share_links.share_code IS '8 位随机分享码（唯一），用于生成短链接';
COMMENT ON COLUMN share_links.click_count IS '点击次数';
COMMENT ON COLUMN share_links.unlock_count IS '成功解锁次数';
COMMENT ON COLUMN share_links.max_unlocks IS '最大解锁次数（默认 5），达到后自动标记为 completed';
COMMENT ON COLUMN share_links.reward_type IS '奖励类型：coin(金币)/time(解锁时间)';
COMMENT ON COLUMN share_links.reward_amount IS '奖励数量（金币数或解锁分钟数）';
COMMENT ON COLUMN share_links.status IS '状态：active/expired/disabled/completed';
COMMENT ON COLUMN share_links.expires_at IS '过期时间（NULL 表示永不过期）';

-- -----------------------------------------------------------
-- 分享点击记录表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS share_clicks (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    share_link_id   UUID NOT NULL REFERENCES share_links(id) ON DELETE CASCADE,
    fingerprint_id  UUID REFERENCES device_fingerprints(id) ON DELETE SET NULL,  -- 点击者指纹（可选）
    ip_address      INET,                                    -- 点击者 IP 地址
    user_agent      TEXT DEFAULT '',                          -- 点击者 User-Agent
    clicked_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()        -- 点击时间
);

COMMENT ON TABLE share_clicks IS '分享点击记录表：追踪分享链接的每次点击行为';
COMMENT ON COLUMN share_clicks.share_link_id IS '分享链接 ID';
COMMENT ON COLUMN share_clicks.fingerprint_id IS '点击者的设备指纹 ID（匿名用户可能为 NULL）';
COMMENT ON COLUMN share_clicks.ip_address IS '点击者 IP 地址';
COMMENT ON COLUMN share_clicks.user_agent IS '点击者 User-Agent';
COMMENT ON COLUMN share_clicks.clicked_at IS '点击时间';

-- -----------------------------------------------------------
-- 触发器：插入分享点击时自动更新点击计数
-- -----------------------------------------------------------
CREATE OR REPLACE FUNCTION increment_share_click_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE share_links
    SET click_count = click_count + 1
    WHERE id = NEW.share_link_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION increment_share_click_count() IS '分享链接被点击时自动递增点击计数';

CREATE TRIGGER trg_share_clicks_insert_count
    AFTER INSERT ON share_clicks
    FOR EACH ROW EXECUTE FUNCTION increment_share_click_count();

-- -----------------------------------------------------------
-- 触发器：分享链接达到最大解锁次数时自动标记为 completed
-- -----------------------------------------------------------
CREATE OR REPLACE FUNCTION check_share_link_completion()
RETURNS TRIGGER AS $$
BEGIN
    -- 仅在 unlock_count 变化时检查
    IF NEW.unlock_count >= NEW.max_unlocks AND NEW.status = 'active' THEN
        NEW.status := 'completed';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION check_share_link_completion() IS '分享链接达到最大解锁次数时自动标记为 completed';

CREATE TRIGGER trg_share_links_check_completion
    BEFORE UPDATE OF unlock_count, status ON share_links
    FOR EACH ROW EXECUTE FUNCTION check_share_link_completion();

-- -----------------------------------------------------------
-- 函数：生成 8 位随机分享码
-- -----------------------------------------------------------
CREATE OR REPLACE FUNCTION generate_share_code()
RETURNS VARCHAR(8) AS $$
DECLARE
    chars TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
    result VARCHAR(8) := '';
    i INTEGER;
    code VARCHAR(8);
    attempts INTEGER := 0;
BEGIN
    -- 循环生成直到唯一（防止碰撞）
    LOOP
        result := '';
        FOR i IN 1..8 LOOP
            result := result || SUBSTRING(chars FROM 1 + floor(random() * length(chars))::INTEGER FOR 1);
        END LOOP;

        -- 检查唯一性
        IF NOT EXISTS (SELECT 1 FROM share_links WHERE share_code = result) THEN
            RETURN result;
        END IF;

        attempts := attempts + 1;
        IF attempts > 100 THEN
            RAISE EXCEPTION '无法生成唯一的分享码，已尝试 100 次';
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql VOLATILE;

COMMENT ON FUNCTION generate_share_code() IS '生成 8 位随机分享码（排除易混淆字符 0OIl1）';

-- -----------------------------------------------------------
-- 索引
-- -----------------------------------------------------------

-- share_links 表索引
CREATE INDEX IF NOT EXISTS idx_share_links_share_code ON share_links(share_code);
CREATE INDEX IF NOT EXISTS idx_share_links_video_id ON share_links(video_id);
CREATE INDEX IF NOT EXISTS idx_share_links_creator ON share_links(creator_fingerprint_id);
CREATE INDEX IF NOT EXISTS idx_share_links_status ON share_links(status);
CREATE INDEX IF NOT EXISTS idx_share_links_created_at ON share_links(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_share_links_expires ON share_links(expires_at) WHERE expires_at IS NOT NULL;
-- 活跃分享链接部分索引
CREATE INDEX IF NOT EXISTS idx_share_links_active
    ON share_links (created_at DESC)
    WHERE status = 'active';

-- share_clicks 表索引
CREATE INDEX IF NOT EXISTS idx_share_clicks_link_id ON share_clicks(share_link_id);
CREATE INDEX IF NOT EXISTS idx_share_clicks_fingerprint ON share_clicks(fingerprint_id) WHERE fingerprint_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_share_clicks_clicked_at ON share_clicks(clicked_at DESC);
-- 防止同一设备重复点击（复合索引）
CREATE INDEX IF NOT EXISTS idx_share_clicks_link_fp ON share_clicks(share_link_id, fingerprint_id);

-- -----------------------------------------------------------
-- 记录迁移
-- -----------------------------------------------------------
INSERT INTO schema_migrations (filename) VALUES ('013_share_viral.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
