-- ============================================================
-- 021_payment.sql
-- 支付系统：支付渠道、订单管理、VIP 订阅
-- ============================================================
-- 说明：
--   - 创建支付渠道配置表，支持多种支付方式（加密货币/支付宝/微信/易支付）
--   - 创建支付订单表，管理完整的订单生命周期
--   - 创建 VIP 订阅表，支持月度/年度订阅和自动续费
--   - 支持订单状态：pending/paid/failed/refunded/expired
--   - 支持产品类型：video/episode/vip_month/vip_year
--   - 关联设备指纹和 TG 用户，支持多端支付
-- ============================================================

BEGIN;

-- -----------------------------------------------------------
-- 支付渠道配置表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS payment_channels (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    channel_name    VARCHAR(100) NOT NULL,                  -- 渠道名称
    channel_type    VARCHAR(50) NOT NULL,                   -- crypto/fiat
    config          JSONB NOT NULL DEFAULT '{}',            -- 渠道配置（API密钥等，加密）
    is_active       BOOLEAN DEFAULT TRUE,
    min_amount      DECIMAL(10,2) DEFAULT 0,               -- 最低金额
    max_amount      DECIMAL(10,2) DEFAULT 99999,           -- 最高金额
    fee_rate        DECIMAL(5,4) DEFAULT 0,                -- 手续费率
    sort_order      INT DEFAULT 0,                         -- 排序权重
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_payment_channels_name UNIQUE (channel_name)
);

COMMENT ON TABLE payment_channels IS '支付渠道配置表：管理所有可用的支付方式和渠道参数';
COMMENT ON COLUMN payment_channels.id IS 'UUID v4 主键';
COMMENT ON COLUMN payment_channels.channel_name IS '渠道名称（唯一）：crypto(加密货币)/alipay(支付宝)/wechat(微信)/epay(易支付)';
COMMENT ON COLUMN payment_channels.channel_type IS '渠道类型：crypto(加密货币)/fiat(法币)';
COMMENT ON COLUMN payment_channels.config IS '渠道配置 JSONB（API密钥、商户号等，加密存储）';
COMMENT ON COLUMN payment_channels.is_active IS '渠道是否启用';
COMMENT ON COLUMN payment_channels.min_amount IS '最低支付金额';
COMMENT ON COLUMN payment_channels.max_amount IS '最高支付金额';
COMMENT ON COLUMN payment_channels.fee_rate IS '手续费率（如 0.02 表示 2%）';
COMMENT ON COLUMN payment_channels.sort_order IS '排序权重，数字越小越靠前';

-- updated_at 触发器
CREATE TRIGGER trg_payment_channels_updated_at
    BEFORE UPDATE ON payment_channels
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- 支付订单表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS payment_orders (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_no        VARCHAR(64) NOT NULL,                  -- 订单号
    fingerprint_id  UUID REFERENCES device_fingerprints(id) ON DELETE SET NULL,
    tg_user_id      BIGINT,                                -- TG 用户 ID（可选）
    channel_id      UUID NOT NULL REFERENCES payment_channels(id),
    product_type    VARCHAR(30) NOT NULL,                  -- video/episode/vip_month/vip_year
    product_id      UUID,                                  -- 关联的视频/剧集 ID
    product_name    VARCHAR(255) NOT NULL,                 -- 商品名称
    amount          DECIMAL(10,2) NOT NULL,                -- 订单金额
    fee_amount      DECIMAL(10,2) DEFAULT 0,               -- 手续费金额
    status          VARCHAR(20) DEFAULT 'pending',         -- pending/paid/failed/refunded/expired
    payment_no      VARCHAR(128),                          -- 第三方支付单号
    paid_at         TIMESTAMPTZ,                           -- 实际支付时间
    expires_at      TIMESTAMPTZ,                           -- 订单过期时间
    refund_reason   TEXT,                                  -- 退款原因
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_payment_orders_order_no UNIQUE (order_no)
);

COMMENT ON TABLE payment_orders IS '支付订单表：管理完整的支付订单生命周期';
COMMENT ON COLUMN payment_orders.id IS 'UUID v4 主键';
COMMENT ON COLUMN payment_orders.order_no IS '订单号（唯一，用于对账和查询）';
COMMENT ON COLUMN payment_orders.fingerprint_id IS '关联的设备指纹 ID（Web 端用户）';
COMMENT ON COLUMN payment_orders.tg_user_id IS 'TG 用户 ID（Telegram 端用户）';
COMMENT ON COLUMN payment_orders.channel_id IS '支付渠道 ID';
COMMENT ON COLUMN payment_orders.product_type IS '产品类型：video(单片购买)/episode(单集购买)/vip_month(月度VIP)/vip_year(年度VIP)';
COMMENT ON COLUMN payment_orders.product_id IS '关联的视频/剧集 ID';
COMMENT ON COLUMN payment_orders.product_name IS '商品显示名称';
COMMENT ON COLUMN payment_orders.amount IS '订单金额（不含手续费）';
COMMENT ON COLUMN payment_orders.fee_amount IS '手续费金额';
COMMENT ON COLUMN payment_orders.status IS '订单状态：pending(待支付)/paid(已支付)/failed(失败)/refunded(已退款)/expired(已过期)';
COMMENT ON COLUMN payment_orders.payment_no IS '第三方支付平台返回的支付单号';
COMMENT ON COLUMN payment_orders.paid_at IS '实际支付时间';
COMMENT ON COLUMN payment_orders.expires_at IS '订单过期时间（超时自动关闭）';
COMMENT ON COLUMN payment_orders.refund_reason IS '退款原因（退款时填写）';

-- updated_at 触发器
CREATE TRIGGER trg_payment_orders_updated_at
    BEFORE UPDATE ON payment_orders
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- VIP 订阅表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS vip_subscriptions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fingerprint_id  UUID REFERENCES device_fingerprints(id) ON DELETE SET NULL,
    tg_user_id      BIGINT,                                -- TG 用户 ID
    plan_type       VARCHAR(20) NOT NULL,                  -- month/year
    start_at        TIMESTAMPTZ NOT NULL,                  -- 订阅开始时间
    expires_at      TIMESTAMPTZ NOT NULL,                  -- 订阅到期时间
    is_active       BOOLEAN DEFAULT TRUE,                  -- 是否有效
    auto_renew      BOOLEAN DEFAULT FALSE,                 -- 是否自动续费
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE vip_subscriptions IS 'VIP 订阅表：管理用户的 VIP 会员订阅';
COMMENT ON COLUMN vip_subscriptions.id IS 'UUID v4 主键';
COMMENT ON COLUMN vip_subscriptions.fingerprint_id IS '关联的设备指纹 ID（Web 端用户）';
COMMENT ON COLUMN vip_subscriptions.tg_user_id IS 'TG 用户 ID（Telegram 端用户）';
COMMENT ON COLUMN vip_subscriptions.plan_type IS '订阅计划：month(月度)/year(年度)';
COMMENT ON COLUMN vip_subscriptions.start_at IS '订阅开始时间';
COMMENT ON COLUMN vip_subscriptions.expires_at IS '订阅到期时间';
COMMENT ON COLUMN vip_subscriptions.is_active IS '订阅是否有效';
COMMENT ON COLUMN vip_subscriptions.auto_renew IS '是否开启自动续费';

-- updated_at 触发器
CREATE TRIGGER trg_vip_subscriptions_updated_at
    BEFORE UPDATE ON vip_subscriptions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- 索引
-- -----------------------------------------------------------

-- payment_orders 表索引
CREATE INDEX IF NOT EXISTS idx_payment_orders_fingerprint ON payment_orders(fingerprint_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payment_orders_status ON payment_orders(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payment_orders_no ON payment_orders(order_no);

-- vip_subscriptions 表索引
CREATE INDEX IF NOT EXISTS idx_vip_fingerprint ON vip_subscriptions(fingerprint_id, is_active) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_vip_tg ON vip_subscriptions(tg_user_id, is_active) WHERE is_active = TRUE;

-- -----------------------------------------------------------
-- 记录迁移
-- -----------------------------------------------------------
INSERT INTO schema_migrations (filename) VALUES ('021_payment.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
