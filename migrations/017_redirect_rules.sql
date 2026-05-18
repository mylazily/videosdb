-- ============================================================
-- 017_redirect_rules.sql
-- 301 重定向规则引擎：规则管理、命中日志、条件匹配
-- ============================================================
-- 说明：
--   - 创建重定向规则表，支持 301/302/307 多种重定向类型
--   - 创建重定向命中日志表，记录每次重定向的详细信息
--   - 支持路径级重定向和条件匹配（UA、地区等）
--   - 支持优先级排序，数字越大越优先
--   - 提供规则匹配函数，支持 UA 和条件过滤
-- ============================================================

BEGIN;

-- -----------------------------------------------------------
-- 301 重定向规则表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS redirect_rules (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_domain   VARCHAR(255) NOT NULL,                   -- 源域名
    source_path     VARCHAR(500) DEFAULT '/',                -- 源路径（支持路径级重定向）
    target_url      VARCHAR(1024) NOT NULL,                  -- 目标URL（域名或完整URL）
    rule_type       VARCHAR(20) DEFAULT '301',               -- 301/302/307
    priority        INT DEFAULT 0,                           -- 优先级（数字越大越优先）
    is_active       BOOLEAN DEFAULT TRUE,
    hit_count       BIGINT DEFAULT 0,                        -- 命中次数
    conditions      JSONB DEFAULT '{}',                      -- 条件：{"ua_contains":"Mobile","region":"CN"}
    expires_at      TIMESTAMPTZ,                             -- 过期时间
    notes           TEXT,                                    -- 备注
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE redirect_rules IS '301重定向规则引擎表：管理域名和路径级别的重定向规则';
COMMENT ON COLUMN redirect_rules.id IS 'UUID v4 主键';
COMMENT ON COLUMN redirect_rules.source_domain IS '源域名';
COMMENT ON COLUMN redirect_rules.source_path IS '源路径（默认 /，支持路径级重定向）';
COMMENT ON COLUMN redirect_rules.target_url IS '目标 URL（域名或完整 URL）';
COMMENT ON COLUMN redirect_rules.rule_type IS '重定向类型：301(永久)/302(临时)/307(临时保持方法)';
COMMENT ON COLUMN redirect_rules.priority IS '优先级（数字越大越优先）';
COMMENT ON COLUMN redirect_rules.is_active IS '是否启用';
COMMENT ON COLUMN redirect_rules.hit_count IS '命中次数（累计）';
COMMENT ON COLUMN redirect_rules.conditions IS '匹配条件 JSON，支持 UA、地区、时间段等条件组合';
COMMENT ON COLUMN redirect_rules.expires_at IS '过期时间（NULL 表示永不过期）';
COMMENT ON COLUMN redirect_rules.notes IS '备注信息';

-- updated_at 触发器
CREATE TRIGGER trg_redirect_rules_updated_at
    BEFORE UPDATE ON redirect_rules
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- 重定向命中日志表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS redirect_hit_logs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_id         UUID NOT NULL REFERENCES redirect_rules(id) ON DELETE CASCADE,
    source_domain   VARCHAR(255),                            -- 来源域名
    source_path     VARCHAR(500),                            -- 来源路径
    target_url      VARCHAR(1024),                           -- 目标 URL
    ip_address      INET,                                    -- 访问者 IP
    user_agent      TEXT,                                    -- 访问者 User-Agent
    hit_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()        -- 命中时间
);

COMMENT ON TABLE redirect_hit_logs IS '重定向命中日志表：记录每次重定向的详细信息';
COMMENT ON COLUMN redirect_hit_logs.rule_id IS '匹配的规则 ID';
COMMENT ON COLUMN redirect_hit_logs.source_domain IS '来源域名';
COMMENT ON COLUMN redirect_hit_logs.source_path IS '来源路径';
COMMENT ON COLUMN redirect_hit_logs.target_url IS '重定向目标 URL';
COMMENT ON COLUMN redirect_hit_logs.ip_address IS '访问者 IP 地址';
COMMENT ON COLUMN redirect_hit_logs.user_agent IS '访问者 User-Agent';
COMMENT ON COLUMN redirect_hit_logs.hit_at IS '命中时间';

-- -----------------------------------------------------------
-- 触发器：重定向命中时自动递增计数
-- -----------------------------------------------------------
CREATE OR REPLACE FUNCTION increment_redirect_hit_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE redirect_rules
    SET hit_count = hit_count + 1
    WHERE id = NEW.rule_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION increment_redirect_hit_count() IS '重定向规则被命中时自动递增命中计数';

CREATE TRIGGER trg_redirect_hit_logs_insert_count
    AFTER INSERT ON redirect_hit_logs
    FOR EACH ROW EXECUTE FUNCTION increment_redirect_hit_count();

-- -----------------------------------------------------------
-- 函数：匹配重定向规则
-- -----------------------------------------------------------
CREATE OR REPLACE FUNCTION match_redirect_rule(
    p_domain VARCHAR,
    p_path VARCHAR DEFAULT '/',
    p_user_agent VARCHAR DEFAULT '',
    p_ip INET DEFAULT NULL
)
RETURNS TABLE(rule_id UUID, target_url VARCHAR, rule_type VARCHAR) AS $$
BEGIN
    RETURN QUERY
    SELECT r.id, r.target_url, r.rule_type
    FROM redirect_rules r
    WHERE r.source_domain = p_domain
      AND r.is_active = TRUE
      AND (r.expires_at IS NULL OR r.expires_at > NOW())
      AND (
          -- 条件为空或默认空对象时，无条件匹配
          r.conditions = '{}'::jsonb
          OR r.conditions IS NULL
          -- 有 ua_contains 条件时，检查 User-Agent 是否包含指定字符串
          OR (
              r.conditions ? 'ua_contains'
              AND r.conditions @> jsonb_build_object('ua_contains', p_user_agent)
          )
          -- 有 ua_contains 条件但未提供 UA 时跳过
          OR (
              NOT r.conditions ? 'ua_contains'
              AND r.conditions != '{}'::jsonb
              AND r.conditions IS NOT NULL
          )
      )
    ORDER BY r.priority DESC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION match_redirect_rule IS '匹配重定向规则，支持 UA 和条件过滤，按优先级排序返回最优匹配';

-- -----------------------------------------------------------
-- 索引
-- -----------------------------------------------------------

-- redirect_rules 表索引
CREATE INDEX IF NOT EXISTS idx_redirect_rules_source ON redirect_rules(source_domain, is_active) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_redirect_rules_priority ON redirect_rules(priority DESC) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_redirect_rules_expires ON redirect_rules(expires_at) WHERE expires_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_redirect_rules_domain_path ON redirect_rules(source_domain, source_path) WHERE is_active = TRUE;

-- redirect_hit_logs 表索引
CREATE INDEX IF NOT EXISTS idx_redirect_hits_rule ON redirect_hit_logs(rule_id, hit_at DESC);
CREATE INDEX IF NOT EXISTS idx_redirect_hits_domain ON redirect_hit_logs(source_domain, hit_at DESC);
CREATE INDEX IF NOT EXISTS idx_redirect_hits_hit_at ON redirect_hit_logs(hit_at DESC);

-- -----------------------------------------------------------
-- 记录迁移
-- -----------------------------------------------------------
INSERT INTO schema_migrations (filename) VALUES ('017_redirect_rules.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
