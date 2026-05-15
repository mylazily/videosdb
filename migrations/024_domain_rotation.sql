-- ============================================================
-- 024_domain_rotation.sql
-- 域名轮询引擎：可用性监控、切换事件、活跃域名管理
-- ============================================================
-- 说明：
--   - 创建域名可用性状态表，按区域记录域名的实时可访问性
--   - 创建域名切换事件日志表，记录域名切换的完整历史
--   - 创建当前活跃域名表，用于前端快速查询当前可用域名
--   - 支持区域划分：cn/us/eu/asia/global
--   - 支持错误类型分类：dns/tcp/tls/timeout/blocked
--   - 关联 site_domains 表（014 迁移），复用站群域名数据
-- ============================================================

BEGIN;

-- -----------------------------------------------------------
-- 域名可用性实时状态表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS domain_availability (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    domain_id       UUID NOT NULL REFERENCES site_domains(id) ON DELETE CASCADE,
    region          VARCHAR(50) NOT NULL DEFAULT 'global',   -- cn/us/eu/asia/global
    is_accessible   BOOLEAN DEFAULT TRUE,                    -- 是否可访问
    response_time_ms INT DEFAULT 0,                          -- 响应时间（毫秒）
    error_type      VARCHAR(50),                             -- dns/tcp/tls/timeout/blocked
    checked_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),      -- 检查时间

    CONSTRAINT uq_domain_availability UNIQUE (domain_id, region)
);

COMMENT ON TABLE domain_availability IS '域名可用性实时状态表：按区域记录域名的可访问性和响应性能';
COMMENT ON COLUMN domain_availability.id IS 'UUID v4 主键';
COMMENT ON COLUMN domain_availability.domain_id IS '关联的站群域名 ID（site_domains 表）';
COMMENT ON COLUMN domain_availability.region IS '区域：cn(中国大陆)/us(美国)/eu(欧洲)/asia(亚太)/global(全球)';
COMMENT ON COLUMN domain_availability.is_accessible IS '域名在该区域是否可访问';
COMMENT ON COLUMN domain_availability.response_time_ms IS '最近一次检查的响应时间（毫秒）';
COMMENT ON COLUMN domain_availability.error_type IS '错误类型：dns(DNS解析失败)/tcp(TCP连接失败)/tls(SSL/TLS错误)/timeout(超时)/blocked(被封锁)';
COMMENT ON COLUMN domain_availability.checked_at IS '最近一次检查时间';

-- -----------------------------------------------------------
-- 域名切换事件日志表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS domain_switch_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    from_domain     VARCHAR(255) NOT NULL,                  -- 切换前域名
    to_domain       VARCHAR(255) NOT NULL,                  -- 切换后域名
    switch_reason   VARCHAR(50) NOT NULL,                   -- blocked/slow/ssl_error/manual
    affected_users  INT DEFAULT 0,                          -- 受影响用户数估算
    switched_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()      -- 切换时间
);

COMMENT ON TABLE domain_switch_events IS '域名切换事件日志表：记录域名切换的完整历史，用于审计和分析';
COMMENT ON COLUMN domain_switch_events.id IS 'UUID v4 主键';
COMMENT ON COLUMN domain_switch_events.from_domain IS '切换前的域名';
COMMENT ON COLUMN domain_switch_events.to_domain IS '切换后的域名';
COMMENT ON COLUMN domain_switch_events.switch_reason IS '切换原因：blocked(被封锁)/slow(响应过慢)/ssl_error(SSL错误)/manual(手动切换)';
COMMENT ON COLUMN domain_switch_events.affected_users IS '受影响用户数估算';
COMMENT ON COLUMN domain_switch_events.switched_at IS '切换发生时间';

-- -----------------------------------------------------------
-- 当前活跃域名表（全局唯一，前端快速查询）
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS active_domain (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    domain          VARCHAR(255) NOT NULL,                  -- 当前活跃域名
    region          VARCHAR(50) NOT NULL DEFAULT 'global',   -- cn/us/eu/asia/global
    activated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),      -- 激活时间
    activated_by    VARCHAR(50) DEFAULT 'auto',               -- auto/manual

    CONSTRAINT uq_active_domain UNIQUE (domain)
);

COMMENT ON TABLE active_domain IS '当前活跃域名表：记录各区域当前使用的活跃域名，前端可快速查询';
COMMENT ON COLUMN active_domain.id IS 'UUID v4 主键';
COMMENT ON COLUMN active_domain.domain IS '当前活跃域名（唯一）';
COMMENT ON COLUMN active_domain.region IS '区域：cn(中国大陆)/us(美国)/eu(欧洲)/asia(亚太)/global(全球)';
COMMENT ON COLUMN active_domain.activated_at IS '域名激活时间';
COMMENT ON COLUMN active_domain.activated_by IS '激活方式：auto(自动切换)/manual(手动设置)';

-- -----------------------------------------------------------
-- 索引
-- -----------------------------------------------------------

-- domain_availability 表索引
CREATE INDEX IF NOT EXISTS idx_domain_avail_domain ON domain_availability(domain_id, region);
CREATE INDEX IF NOT EXISTS idx_domain_avail_accessible ON domain_availability(region, is_accessible) WHERE is_accessible = TRUE;

-- domain_switch_events 表索引
CREATE INDEX IF NOT EXISTS idx_domain_switch_time ON domain_switch_events(switched_at DESC);

-- -----------------------------------------------------------
-- 记录迁移
-- -----------------------------------------------------------
INSERT INTO schema_migrations (filename) VALUES ('024_domain_rotation.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
