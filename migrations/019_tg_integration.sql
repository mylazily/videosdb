-- ============================================================
-- 019_tg_integration.sql
-- Telegram 深度融合：Bot 配置、频道管理、推送日志、Mini App 会话
-- ============================================================
-- 说明：
--   - 创建 TG Bot 配置表，管理 Bot Token 和 Webhook
--   - 创建 TG 频道/群组列表，支持多频道推送
--   - 创建 TG 推送记录表，追踪视频/短视频/小说的推送状态
--   - 创建 TG Mini App 用户会话表，关联设备指纹实现跨平台追踪
--   - 支持推送类型：video/short/novel/update
--   - 支持推送状态追踪：pending/sent/failed/deleted
-- ============================================================

BEGIN;

-- -----------------------------------------------------------
-- TG Bot 配置表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS tg_bot_config (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bot_token       TEXT NOT NULL,                          -- TG Bot Token（加密存储）
    bot_username    VARCHAR(100),                           -- @bot_username
    webhook_url     VARCHAR(500),                           -- Webhook URL
    is_active       BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE tg_bot_config IS 'TG Bot 配置表：管理 Telegram Bot 的连接参数和 Webhook 设置';
COMMENT ON COLUMN tg_bot_config.id IS 'UUID v4 主键';
COMMENT ON COLUMN tg_bot_config.bot_token IS 'TG Bot Token（加密存储，切勿明文）';
COMMENT ON COLUMN tg_bot_config.bot_username IS 'Bot 用户名（如 @my_video_bot）';
COMMENT ON COLUMN tg_bot_config.webhook_url IS 'Webhook 回调 URL，用于接收 TG 事件';
COMMENT ON COLUMN tg_bot_config.is_active IS 'Bot 是否启用';
COMMENT ON COLUMN tg_bot_config.created_at IS '创建时间';
COMMENT ON COLUMN tg_bot_config.updated_at IS '更新时间';

-- updated_at 触发器
CREATE TRIGGER trg_tg_bot_config_updated_at
    BEFORE UPDATE ON tg_bot_config
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- TG 频道/群组列表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS tg_channels (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    channel_id          BIGINT NOT NULL,                    -- TG Channel ID（负数）
    channel_title       VARCHAR(255) NOT NULL,              -- 频道/群组名称
    channel_type        VARCHAR(20) NOT NULL DEFAULT 'channel',  -- channel/group/supergroup
    subscriber_count    INT DEFAULT 0,                      -- 订阅者数量
    is_active           BOOLEAN DEFAULT TRUE,
    last_post_at        TIMESTAMPTZ,                       -- 最后推送时间
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_tg_channels_channel_id UNIQUE (channel_id)
);

COMMENT ON TABLE tg_channels IS 'TG 频道/群组列表：管理所有关联的 Telegram 频道和群组';
COMMENT ON COLUMN tg_channels.id IS 'UUID v4 主键';
COMMENT ON COLUMN tg_channels.channel_id IS 'TG Channel ID（频道为负数，群组为正数）';
COMMENT ON COLUMN tg_channels.channel_title IS '频道/群组显示名称';
COMMENT ON COLUMN tg_channels.channel_type IS '类型：channel(频道)/group(群组)/supergroup(超级群组)';
COMMENT ON COLUMN tg_channels.subscriber_count IS '订阅者/成员数量';
COMMENT ON COLUMN tg_channels.is_active IS '频道是否启用推送';
COMMENT ON COLUMN tg_channels.last_post_at IS '最后一次推送时间';

-- updated_at 触发器
CREATE TRIGGER trg_tg_channels_updated_at
    BEFORE UPDATE ON tg_channels
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- TG 推送记录表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS tg_broadcast_logs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    channel_id      UUID NOT NULL REFERENCES tg_channels(id) ON DELETE CASCADE,
    video_id        UUID REFERENCES videos(id) ON DELETE SET NULL,
    message_id      BIGINT,                                 -- TG 消息 ID
    message_text    TEXT,                                   -- 推送消息内容
    media_url       VARCHAR(1024),                          -- 封面图 URL
    link_url        VARCHAR(1024),                          -- 推广链接
    post_type       VARCHAR(20) DEFAULT 'video',            -- video/short/novel/update
    status          VARCHAR(20) DEFAULT 'pending',          -- pending/sent/failed/deleted
    error_message   TEXT,                                   -- 失败原因
    sent_at         TIMESTAMPTZ,                            -- 实际发送时间
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE tg_broadcast_logs IS 'TG 推送记录表：追踪向 Telegram 频道推送内容的完整生命周期';
COMMENT ON COLUMN tg_broadcast_logs.id IS 'UUID v4 主键';
COMMENT ON COLUMN tg_broadcast_logs.channel_id IS '推送目标频道 ID';
COMMENT ON COLUMN tg_broadcast_logs.video_id IS '关联的视频 ID（可选）';
COMMENT ON COLUMN tg_broadcast_logs.message_id IS 'TG 服务端返回的消息 ID';
COMMENT ON COLUMN tg_broadcast_logs.message_text IS '推送的消息文本内容';
COMMENT ON COLUMN tg_broadcast_logs.media_url IS '推送的封面图/媒体文件 URL';
COMMENT ON COLUMN tg_broadcast_logs.link_url IS '推广链接（视频详情页等）';
COMMENT ON COLUMN tg_broadcast_logs.post_type IS '推送类型：video(视频)/short(短视频)/novel(小说)/update(更新通知)';
COMMENT ON COLUMN tg_broadcast_logs.status IS '推送状态：pending(待发送)/sent(已发送)/failed(失败)/deleted(已删除)';
COMMENT ON COLUMN tg_broadcast_logs.error_message IS '推送失败时的错误信息';
COMMENT ON COLUMN tg_broadcast_logs.sent_at IS '实际发送时间';

-- -----------------------------------------------------------
-- TG Mini App 用户会话表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS tg_miniapp_sessions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tg_user_id          BIGINT NOT NULL,                    -- TG 用户 ID
    tg_username         VARCHAR(100),                       -- TG 用户名
    tg_language         VARCHAR(10),                        -- TG 用户语言设置
    fingerprint_id      UUID REFERENCES device_fingerprints(id) ON DELETE SET NULL,
    session_data        JSONB DEFAULT '{}',                 -- 会话扩展数据
    first_open_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(), -- 首次打开 Mini App 时间
    last_open_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(), -- 最后活跃时间
    total_opens         INT DEFAULT 1,                     -- 累计打开次数
    total_watch_time    INT DEFAULT 0,                      -- 总观看时长（秒）
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE tg_miniapp_sessions IS 'TG Mini App 用户会话表：追踪用户在 Telegram Mini App 中的行为数据';
COMMENT ON COLUMN tg_miniapp_sessions.id IS 'UUID v4 主键';
COMMENT ON COLUMN tg_miniapp_sessions.tg_user_id IS 'Telegram 用户 ID';
COMMENT ON COLUMN tg_miniapp_sessions.tg_username IS 'Telegram 用户名';
COMMENT ON COLUMN tg_miniapp_sessions.tg_language IS '用户语言设置（如 zh-hans、en）';
COMMENT ON COLUMN tg_miniapp_sessions.fingerprint_id IS '关联的设备指纹 ID（跨平台用户识别）';
COMMENT ON COLUMN tg_miniapp_sessions.session_data IS '会话扩展数据 JSONB';
COMMENT ON COLUMN tg_miniapp_sessions.first_open_at IS '首次打开 Mini App 时间';
COMMENT ON COLUMN tg_miniapp_sessions.last_open_at IS '最后活跃时间';
COMMENT ON COLUMN tg_miniapp_sessions.total_opens IS '累计打开 Mini App 次数';
COMMENT ON COLUMN tg_miniapp_sessions.total_watch_time IS '累计观看视频时长（秒）';

-- updated_at 触发器
CREATE TRIGGER trg_tg_miniapp_sessions_updated_at
    BEFORE UPDATE ON tg_miniapp_sessions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- 索引
-- -----------------------------------------------------------

-- tg_broadcast_logs 表索引
CREATE INDEX IF NOT EXISTS idx_tg_broadcasts_channel ON tg_broadcast_logs(channel_id, sent_at DESC);
CREATE INDEX IF NOT EXISTS idx_tg_broadcasts_status ON tg_broadcast_logs(status, created_at DESC);

-- tg_miniapp_sessions 表索引
CREATE INDEX IF NOT EXISTS idx_tg_miniapp_user ON tg_miniapp_sessions(tg_user_id, last_open_at DESC);
CREATE INDEX IF NOT EXISTS idx_tg_miniapp_fingerprint ON tg_miniapp_sessions(fingerprint_id);

-- -----------------------------------------------------------
-- 记录迁移
-- -----------------------------------------------------------
INSERT INTO schema_migrations (filename) VALUES ('019_tg_integration.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
