-- ============================================================
-- 014_site_cluster.sql
-- 站群管理系统：域名管理、健康检查、交叉链接审计
-- ============================================================
-- 说明：
--   - 创建站群域名表，支持 A/B 队分类（优质SEO / 引流）
--   - 创建健康检查日志表，记录域名可用性监控
--   - 创建域名交叉链接审计表，确保 A/B 队域名不互相链接
--   - 支持域名角色划分：frontend/backend/api/cdn
--   - 支持 301 重定向配置（B队流量成熟后吸星大法）
-- ============================================================

BEGIN;

-- -----------------------------------------------------------
-- 站群域名表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS site_domains (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    domain              VARCHAR(255) NOT NULL,                  -- 域名
    cluster             CHAR(1) NOT NULL DEFAULT 'A' CHECK (cluster IN ('A', 'B')),  -- A队(优质SEO) / B队(引流)
    role                VARCHAR(50) NOT NULL DEFAULT 'frontend',  -- frontend/backend/api/cdn
    cloudflare_zone_id  VARCHAR(100),                           -- CF Zone ID
    ssl_status          VARCHAR(20) DEFAULT 'pending',         -- pending/active/expired
    is_active           BOOLEAN DEFAULT TRUE,
    health_status       VARCHAR(20) DEFAULT 'unknown',         -- unknown/healthy/degraded/down
    last_health_check   TIMESTAMPTZ,
    google_rank         INT DEFAULT 0,                         -- Google 排名估算
    daily_traffic       BIGINT DEFAULT 0,                      -- 日流量
    monthly_traffic     BIGINT DEFAULT 0,
    redirect_target     VARCHAR(255),                          -- 301 重定向目标
    redirect_enabled    BOOLEAN DEFAULT FALSE,
    seo_score           INT DEFAULT 0,                         -- SEO 评分 0-100
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_site_domains_domain UNIQUE (domain)
);

COMMENT ON TABLE site_domains IS '站群域名管理表';
COMMENT ON COLUMN site_domains.id IS 'UUID v4 主键';
COMMENT ON COLUMN site_domains.domain IS '域名（唯一）';
COMMENT ON COLUMN site_domains.cluster IS 'A队: 20个优质域名做正规SEO; B队: 80个引流域名';
COMMENT ON COLUMN site_domains.role IS '域名角色：frontend(前端)/backend(后端)/api(接口)/cdn(加速)';
COMMENT ON COLUMN site_domains.cloudflare_zone_id IS 'Cloudflare Zone ID，用于 DNS 和 CDN 管理';
COMMENT ON COLUMN site_domains.ssl_status IS 'SSL 证书状态：pending(待签发)/active(有效)/expired(已过期)';
COMMENT ON COLUMN site_domains.health_status IS '健康状态：unknown(未知)/healthy(正常)/degraded(降级)/down(宕机)';
COMMENT ON COLUMN site_domains.last_health_check IS '最后健康检查时间';
COMMENT ON COLUMN site_domains.google_rank IS 'Google 排名估算值';
COMMENT ON COLUMN site_domains.daily_traffic IS '日访问流量';
COMMENT ON COLUMN site_domains.monthly_traffic IS '月访问流量';
COMMENT ON COLUMN site_domains.redirect_target IS '301重定向目标域名，B队流量成熟后吸星大法';
COMMENT ON COLUMN site_domains.redirect_enabled IS '是否启用 301 重定向';
COMMENT ON COLUMN site_domains.seo_score IS 'SEO 评分（0-100）';

-- updated_at 触发器
CREATE TRIGGER trg_site_domains_updated_at
    BEFORE UPDATE ON site_domains
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- 站群健康检查日志
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS site_health_logs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    domain_id       UUID NOT NULL REFERENCES site_domains(id) ON DELETE CASCADE,
    status_code     INT,                                     -- HTTP 状态码
    response_time_ms INT,                                    -- 响应时间（毫秒）
    is_ssl_valid    BOOLEAN,                                 -- SSL 证书是否有效
    error_message   TEXT,                                    -- 错误信息
    checked_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()        -- 检查时间
);

COMMENT ON TABLE site_health_logs IS '站群健康检查日志表：记录每次域名健康检查的结果';
COMMENT ON COLUMN site_health_logs.domain_id IS '关联的域名 ID';
COMMENT ON COLUMN site_health_logs.status_code IS 'HTTP 响应状态码';
COMMENT ON COLUMN site_health_logs.response_time_ms IS '响应时间（毫秒）';
COMMENT ON COLUMN site_health_logs.is_ssl_valid IS 'SSL 证书是否有效';
COMMENT ON COLUMN site_health_logs.error_message IS '错误信息（检查失败时记录）';
COMMENT ON COLUMN site_health_logs.checked_at IS '检查时间';

-- -----------------------------------------------------------
-- 域名交叉链接检测（安全：确保A/B队域名不互相链接）
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS domain_link_audit (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_domain   VARCHAR(255) NOT NULL,                   -- 来源域名
    target_domain   VARCHAR(255) NOT NULL,                   -- 目标域名
    link_type       VARCHAR(20) DEFAULT 'external',          -- external/cross_cluster
    detected_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),      -- 检测时间
    is_resolved     BOOLEAN DEFAULT FALSE                     -- 是否已处理
);

COMMENT ON TABLE domain_link_audit IS '域名交叉链接审计表：检测 A/B 队域名之间的互相链接';
COMMENT ON COLUMN domain_link_audit.source_domain IS '来源域名';
COMMENT ON COLUMN domain_link_audit.target_domain IS '目标域名';
COMMENT ON COLUMN domain_link_audit.link_type IS '链接类型：external(外部链接)/cross_cluster(跨队链接)';
COMMENT ON COLUMN domain_link_audit.detected_at IS '检测时间';
COMMENT ON COLUMN domain_link_audit.is_resolved IS '是否已处理';

-- -----------------------------------------------------------
-- 索引
-- -----------------------------------------------------------

-- site_domains 表索引
CREATE INDEX IF NOT EXISTS idx_site_domains_cluster ON site_domains(cluster);
CREATE INDEX IF NOT EXISTS idx_site_domains_role ON site_domains(role);
CREATE INDEX IF NOT EXISTS idx_site_domains_is_active ON site_domains(is_active) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_site_domains_health_status ON site_domains(health_status);
CREATE INDEX IF NOT EXISTS idx_site_domains_seo_score ON site_domains(seo_score DESC);

-- site_health_logs 表索引
CREATE INDEX IF NOT EXISTS idx_site_health_logs_domain ON site_health_logs(domain_id, checked_at DESC);
CREATE INDEX IF NOT EXISTS idx_site_health_logs_checked_at ON site_health_logs(checked_at DESC);

-- domain_link_audit 表索引
CREATE INDEX IF NOT EXISTS idx_domain_link_audit_source ON domain_link_audit(source_domain, detected_at DESC);
CREATE INDEX IF NOT EXISTS idx_domain_link_audit_resolved ON domain_link_audit(is_resolved) WHERE is_resolved = FALSE;

-- -----------------------------------------------------------
-- 记录迁移
-- -----------------------------------------------------------
INSERT INTO schema_migrations (filename) VALUES ('014_site_cluster.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
