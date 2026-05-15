-- ============================================================
-- 018_sitemap_auto_submit.sql
-- Sitemap 自动提交：提交日志、GSC 凭证管理
-- ============================================================
-- 说明：
--   - 创建 Sitemap 提交记录表，管理向搜索引擎的提交日志
--   - 创建 Google Search Console API 凭证表，加密存储服务账户密钥
--   - 支持多种搜索引擎：Google/Bing/Baidu
--   - 支持多种提交方式：API/Ping
--   - 支持多种 Sitemap 类型：video/tag/actor/short
-- ============================================================

BEGIN;

-- -----------------------------------------------------------
-- Sitemap 提交记录表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS sitemap_submit_logs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    domain_id       UUID REFERENCES site_domains(id) ON DELETE SET NULL,
    sitemap_type    VARCHAR(50) NOT NULL,                    -- video/tag/actor/short
    sitemap_url     VARCHAR(1024) NOT NULL,                  -- Sitemap URL
    search_engine   VARCHAR(20) NOT NULL DEFAULT 'google',   -- google/bing/baidu
    submit_method   VARCHAR(20) DEFAULT 'api',               -- api/ping
    status_code     INT,                                     -- 响应状态码
    response_body   TEXT,                                    -- 响应内容
    status          VARCHAR(20) DEFAULT 'pending',           -- pending/success/failed
    submitted_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()        -- 提交时间
);

COMMENT ON TABLE sitemap_submit_logs IS 'Sitemap 提交记录表：管理向搜索引擎提交 Sitemap 的日志';
COMMENT ON COLUMN sitemap_submit_logs.id IS 'UUID v4 主键';
COMMENT ON COLUMN sitemap_submit_logs.domain_id IS '关联的域名 ID';
COMMENT ON COLUMN sitemap_submit_logs.sitemap_type IS 'Sitemap 类型：video(视频)/tag(标签)/actor(演员)/short(短视频)';
COMMENT ON COLUMN sitemap_submit_logs.sitemap_url IS 'Sitemap 文件 URL';
COMMENT ON COLUMN sitemap_submit_logs.search_engine IS '搜索引擎：google/bing/baidu';
COMMENT ON COLUMN sitemap_submit_logs.submit_method IS '提交方式：api(接口提交)/ping(Ping提交)';
COMMENT ON COLUMN sitemap_submit_logs.status_code IS '搜索引擎返回的 HTTP 状态码';
COMMENT ON COLUMN sitemap_submit_logs.response_body IS '搜索引擎返回的响应内容';
COMMENT ON COLUMN sitemap_submit_logs.status IS '提交状态：pending(待提交)/success(成功)/failed(失败)';
COMMENT ON COLUMN sitemap_submit_logs.submitted_at IS '提交时间';

-- -----------------------------------------------------------
-- Google Search Console API 凭证表（加密存储）
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS gsc_credentials (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    domain_id               UUID NOT NULL REFERENCES site_domains(id) ON DELETE CASCADE,
    service_account_email   VARCHAR(255) NOT NULL,           -- GCP 服务账户邮箱
    private_key_encrypted   TEXT NOT NULL,                   -- AES 加密的私钥
    site_url                VARCHAR(500) NOT NULL,           -- GSC 中注册的站点URL
    is_active               BOOLEAN DEFAULT TRUE,
    last_submit_at          TIMESTAMPTZ,                     -- 最后提交时间
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_gsc_credentials_domain UNIQUE (domain_id)
);

COMMENT ON TABLE gsc_credentials IS 'Google Search Console API 凭证表：加密存储 GCP 服务账户密钥';
COMMENT ON COLUMN gsc_credentials.id IS 'UUID v4 主键';
COMMENT ON COLUMN gsc_credentials.domain_id IS '关联的域名 ID（唯一，每个域名一个凭证）';
COMMENT ON COLUMN gsc_credentials.service_account_email IS 'GCP 服务账户邮箱地址';
COMMENT ON COLUMN gsc_credentials.private_key_encrypted IS 'AES 加密的私钥（切勿明文存储）';
COMMENT ON COLUMN gsc_credentials.site_url IS '在 Google Search Console 中注册的站点 URL';
COMMENT ON COLUMN gsc_credentials.is_active IS '凭证是否可用';
COMMENT ON COLUMN gsc_credentials.last_submit_at IS '最后一次使用此凭证提交的时间';

-- updated_at 触发器
CREATE TRIGGER trg_gsc_credentials_updated_at
    BEFORE UPDATE ON gsc_credentials
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- 索引
-- -----------------------------------------------------------

-- sitemap_submit_logs 表索引
CREATE INDEX IF NOT EXISTS idx_sitemap_submit_domain ON sitemap_submit_logs(domain_id, submitted_at DESC) WHERE domain_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sitemap_submit_status ON sitemap_submit_logs(status, submitted_at DESC);
CREATE INDEX IF NOT EXISTS idx_sitemap_submit_engine ON sitemap_submit_logs(search_engine, submitted_at DESC);
CREATE INDEX IF NOT EXISTS idx_sitemap_submit_type ON sitemap_submit_logs(sitemap_type, submitted_at DESC);
CREATE INDEX IF NOT EXISTS idx_sitemap_submit_submitted_at ON sitemap_submit_logs(submitted_at DESC);

-- gsc_credentials 表索引
CREATE INDEX IF NOT EXISTS idx_gsc_credentials_is_active ON gsc_credentials(is_active) WHERE is_active = TRUE;

-- -----------------------------------------------------------
-- 记录迁移
-- -----------------------------------------------------------
INSERT INTO schema_migrations (filename) VALUES ('018_sitemap_auto_submit.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
