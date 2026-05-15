-- ============================================================
-- 010_fingerprint_auth.sql
-- 浏览器指纹认证系统：设备识别、解锁记录、虚拟币余额
-- ============================================================
-- 说明：
--   - 基于浏览器指纹实现无注册用户识别
--   - 支持设备解锁记录（分享/金币/广告解锁）
--   - 支持虚拟币系统（赚取、消费）
--   - 指纹哈希使用 SHA256，确保唯一性和安全性
-- ============================================================

BEGIN;

-- -----------------------------------------------------------
-- 枚举类型定义
-- -----------------------------------------------------------

-- 解锁类型枚举
CREATE TYPE unlock_type AS ENUM (
    'share',        -- 分享解锁
    'coin',         -- 金币解锁
    'ad'            -- 广告解锁
);

COMMENT ON TYPE unlock_type IS '解锁类型枚举';

-- -----------------------------------------------------------
-- 设备指纹表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS device_fingerprints (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fingerprint_hash    VARCHAR(64) NOT NULL,                 -- SHA256 指纹哈希
    user_agent          TEXT DEFAULT '',                       -- 浏览器 User-Agent
    screen_resolution   VARCHAR(50) DEFAULT '',                -- 屏幕分辨率（如 1920x1080）
    language            VARCHAR(50) DEFAULT '',                -- 浏览器语言
    timezone            VARCHAR(100) DEFAULT '',               -- 时区（如 Asia/Shanghai）
    first_seen_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),    -- 首次发现时间
    last_seen_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),    -- 最后活跃时间
    is_banned           BOOLEAN NOT NULL DEFAULT FALSE,        -- 是否封禁
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_device_fingerprints_hash UNIQUE (fingerprint_hash)
);

COMMENT ON TABLE device_fingerprints IS '设备指纹表：基于浏览器指纹识别匿名用户';
COMMENT ON COLUMN device_fingerprints.id IS 'UUID v4 主键';
COMMENT ON COLUMN device_fingerprints.fingerprint_hash IS 'SHA256 指纹哈希，唯一标识一个浏览器设备';
COMMENT ON COLUMN device_fingerprints.user_agent IS '浏览器 User-Agent 字符串';
COMMENT ON COLUMN device_fingerprints.screen_resolution IS '屏幕分辨率（如 1920x1080）';
COMMENT ON COLUMN device_fingerprints.language IS '浏览器语言（如 zh-CN）';
COMMENT ON COLUMN device_fingerprints.timezone IS '时区（如 Asia/Shanghai）';
COMMENT ON COLUMN device_fingerprints.first_seen_at IS '首次发现时间';
COMMENT ON COLUMN device_fingerprints.last_seen_at IS '最后活跃时间';
COMMENT ON COLUMN device_fingerprints.is_banned IS '是否封禁（封禁后无法使用解锁功能）';

-- updated_at 触发器
CREATE TRIGGER trg_device_fingerprints_updated_at
    BEFORE UPDATE ON device_fingerprints
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- 设备解锁记录表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS device_unlock_records (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fingerprint_id  UUID NOT NULL REFERENCES device_fingerprints(id) ON DELETE CASCADE,
    video_id        UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    unlock_type     unlock_type NOT NULL,                     -- 解锁方式：share/coin/ad
    unlocked_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),       -- 解锁时间
    expires_at      TIMESTAMPTZ,                              -- 过期时间（NULL 表示永久有效）
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE device_unlock_records IS '设备解锁记录表：记录设备的视频解锁行为';
COMMENT ON COLUMN device_unlock_records.fingerprint_id IS '设备指纹 ID';
COMMENT ON COLUMN device_unlock_records.video_id IS '解锁的视频 ID';
COMMENT ON COLUMN device_unlock_records.unlock_type IS '解锁方式：share(分享)/coin(金币)/ad(广告)';
COMMENT ON COLUMN device_unlock_records.unlocked_at IS '解锁时间';
COMMENT ON COLUMN device_unlock_records.expires_at IS '过期时间（NULL 表示永久有效）';

-- -----------------------------------------------------------
-- 设备虚拟币余额表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS device_coin_balances (
    fingerprint_id  UUID PRIMARY KEY REFERENCES device_fingerprints(id) ON DELETE CASCADE,
    balance         INTEGER NOT NULL DEFAULT 0,               -- 当前余额
    total_earned    INTEGER NOT NULL DEFAULT 0,               -- 累计赚取
    total_spent     INTEGER NOT NULL DEFAULT 0,               -- 累计消费
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE device_coin_balances IS '设备虚拟币余额表：每个设备指纹对应一个虚拟币账户';
COMMENT ON COLUMN device_coin_balances.fingerprint_id IS '设备指纹 ID（主键，一对一关系）';
COMMENT ON COLUMN device_coin_balances.balance IS '当前余额（金币数）';
COMMENT ON COLUMN device_coin_balances.total_earned IS '累计赚取金币数';
COMMENT ON COLUMN device_coin_balances.total_spent IS '累计消费金币数';

-- updated_at 触发器
CREATE TRIGGER trg_device_coin_balances_updated_at
    BEFORE UPDATE ON device_coin_balances
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- 触发器：插入设备指纹时自动创建虚拟币账户
-- -----------------------------------------------------------
CREATE OR REPLACE FUNCTION create_device_coin_balance()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO device_coin_balances (fingerprint_id)
    VALUES (NEW.id)
    ON CONFLICT (fingerprint_id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION create_device_coin_balance() IS '新设备注册时自动创建虚拟币账户';

CREATE TRIGGER trg_device_fingerprints_create_balance
    AFTER INSERT ON device_fingerprints
    FOR EACH ROW EXECUTE FUNCTION create_device_coin_balance();

-- -----------------------------------------------------------
-- 索引
-- -----------------------------------------------------------

-- device_fingerprints 表索引
CREATE INDEX IF NOT EXISTS idx_device_fingerprints_hash ON device_fingerprints(fingerprint_hash);
CREATE INDEX IF NOT EXISTS idx_device_fingerprints_last_seen ON device_fingerprints(last_seen_at DESC);
CREATE INDEX IF NOT EXISTS idx_device_fingerprints_is_banned ON device_fingerprints(is_banned) WHERE is_banned = TRUE;
CREATE INDEX IF NOT EXISTS idx_device_fingerprints_first_seen ON device_fingerprints(first_seen_at DESC);

-- device_unlock_records 表索引
CREATE INDEX IF NOT EXISTS idx_device_unlock_records_fingerprint ON device_unlock_records(fingerprint_id);
CREATE INDEX IF NOT EXISTS idx_device_unlock_records_video ON device_unlock_records(video_id);
CREATE INDEX IF NOT EXISTS idx_device_unlock_records_type ON device_unlock_records(unlock_type);
CREATE INDEX IF NOT EXISTS idx_device_unlock_records_unlocked_at ON device_unlock_records(unlocked_at DESC);
-- 复合索引：查询某设备对某视频的解锁状态
CREATE INDEX IF NOT EXISTS idx_device_unlock_records_fp_video ON device_unlock_records(fingerprint_id, video_id);
-- 过期时间索引：用于清理过期记录
CREATE INDEX IF NOT EXISTS idx_device_unlock_records_expires ON device_unlock_records(expires_at) WHERE expires_at IS NOT NULL;

-- -----------------------------------------------------------
-- 记录迁移
-- -----------------------------------------------------------
INSERT INTO schema_migrations (filename) VALUES ('010_fingerprint_auth.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
