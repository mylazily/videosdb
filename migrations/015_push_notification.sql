-- ============================================================
-- 015_push_notification.sql
-- 推送通知系统：Web Push 订阅、通知发送、点击追踪
-- ============================================================
-- 说明：
--   - 创建 Push 订阅表，管理浏览器推送订阅（endpoint + 密钥）
--   - 创建推送通知记录表，管理通知内容和发送状态
--   - 创建推送点击日志表，追踪用户对通知的点击行为
--   - 支持按目标类型推送：全部/新视频/热门更新
--   - 支持通知标签（tag），相同 tag 会替换旧通知
-- ============================================================

BEGIN;

-- -----------------------------------------------------------
-- Push 订阅表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS push_subscriptions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fingerprint_id  UUID REFERENCES device_fingerprints(id) ON DELETE SET NULL,
    endpoint        VARCHAR(1024) NOT NULL,                  -- Push endpoint URL
    p256dh_key      VARCHAR(255) NOT NULL,                   -- 加密公钥
    auth_key        VARCHAR(255) NOT NULL,                   -- 认证密钥
    user_agent      TEXT,                                    -- 浏览器 User-Agent
    is_active       BOOLEAN DEFAULT TRUE,
    last_sent_at    TIMESTAMPTZ,                             -- 最后推送时间
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_push_subscriptions_endpoint UNIQUE (endpoint)
);

COMMENT ON TABLE push_subscriptions IS 'Web Push 订阅表：管理浏览器推送订阅';
COMMENT ON COLUMN push_subscriptions.id IS 'UUID v4 主键';
COMMENT ON COLUMN push_subscriptions.fingerprint_id IS '关联的设备指纹 ID（匿名用户可能为 NULL）';
COMMENT ON COLUMN push_subscriptions.endpoint IS 'Push endpoint URL（唯一），由浏览器生成';
COMMENT ON COLUMN push_subscriptions.p256dh_key IS 'P-256 ECDH 加密公钥';
COMMENT ON COLUMN push_subscriptions.auth_key IS '认证密钥';
COMMENT ON COLUMN push_subscriptions.user_agent IS '浏览器 User-Agent';
COMMENT ON COLUMN push_subscriptions.is_active IS '订阅是否活跃';
COMMENT ON COLUMN push_subscriptions.last_sent_at IS '最后推送时间';

-- updated_at 触发器
CREATE TRIGGER trg_push_subscriptions_updated_at
    BEFORE UPDATE ON push_subscriptions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- 推送通知记录表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS push_notifications (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title           VARCHAR(255) NOT NULL,                   -- 通知标题
    body            TEXT NOT NULL,                            -- 通知正文
    icon            VARCHAR(1024),                            -- 通知图标 URL
    link            VARCHAR(1024),                            -- 点击跳转链接
    tag             VARCHAR(100),                             -- 通知标签（相同tag会替换）
    target_type     VARCHAR(20) DEFAULT 'all',               -- all/new_video/hot_update
    target_video_id UUID,                                    -- 目标视频 ID（可选）
    total_sent      INT DEFAULT 0,                           -- 总发送数
    total_clicked   INT DEFAULT 0,                           -- 总点击数
    status          VARCHAR(20) DEFAULT 'pending',           -- pending/sending/completed/failed
    sent_at         TIMESTAMPTZ,                             -- 发送时间
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE push_notifications IS '推送通知记录表：管理推送通知的内容和发送状态';
COMMENT ON COLUMN push_notifications.id IS 'UUID v4 主键';
COMMENT ON COLUMN push_notifications.title IS '通知标题';
COMMENT ON COLUMN push_notifications.body IS '通知正文';
COMMENT ON COLUMN push_notifications.icon IS '通知图标 URL';
COMMENT ON COLUMN push_notifications.link IS '点击通知后跳转的链接';
COMMENT ON COLUMN push_notifications.tag IS '通知标签（相同 tag 的通知会替换旧通知）';
COMMENT ON COLUMN push_notifications.target_type IS '推送目标类型：all(全部)/new_video(新视频)/hot_update(热门更新)';
COMMENT ON COLUMN push_notifications.target_video_id IS '目标视频 ID（当 target_type 为 new_video 时使用）';
COMMENT ON COLUMN push_notifications.total_sent IS '总发送数';
COMMENT ON COLUMN push_notifications.total_clicked IS '总点击数';
COMMENT ON COLUMN push_notifications.status IS '状态：pending(待发送)/sending(发送中)/completed(已完成)/failed(失败)';
COMMENT ON COLUMN push_notifications.sent_at IS '实际发送时间';

-- -----------------------------------------------------------
-- 推送点击日志表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS push_click_logs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    notification_id UUID NOT NULL REFERENCES push_notifications(id) ON DELETE CASCADE,
    subscription_id UUID NOT NULL REFERENCES push_subscriptions(id) ON DELETE CASCADE,
    clicked_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()        -- 点击时间
);

COMMENT ON TABLE push_click_logs IS '推送点击日志表：追踪用户对推送通知的点击行为';
COMMENT ON COLUMN push_click_logs.notification_id IS '关联的通知 ID';
COMMENT ON COLUMN push_click_logs.subscription_id IS '关联的订阅 ID';
COMMENT ON COLUMN push_click_logs.clicked_at IS '点击时间';

-- -----------------------------------------------------------
-- 索引
-- -----------------------------------------------------------

-- push_subscriptions 表索引
CREATE INDEX IF NOT EXISTS idx_push_subscriptions_fingerprint ON push_subscriptions(fingerprint_id) WHERE fingerprint_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_push_subscriptions_active ON push_subscriptions(is_active) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_push_subscriptions_created_at ON push_subscriptions(created_at DESC);

-- push_notifications 表索引
CREATE INDEX IF NOT EXISTS idx_push_notifications_status ON push_notifications(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_push_notifications_target_type ON push_notifications(target_type);
CREATE INDEX IF NOT EXISTS idx_push_notifications_created_at ON push_notifications(created_at DESC);

-- push_click_logs 表索引
CREATE INDEX IF NOT EXISTS idx_push_clicks_notification ON push_click_logs(notification_id);
CREATE INDEX IF NOT EXISTS idx_push_clicks_subscription ON push_click_logs(subscription_id);
CREATE INDEX IF NOT EXISTS idx_push_clicks_clicked_at ON push_click_logs(clicked_at DESC);

-- -----------------------------------------------------------
-- 记录迁移
-- -----------------------------------------------------------
INSERT INTO schema_migrations (filename) VALUES ('015_push_notification.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
