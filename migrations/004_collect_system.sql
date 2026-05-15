-- ============================================================
-- 004_collect_system.sql
-- MacCMS 采集源管理
-- ============================================================

BEGIN;

-- -----------------------------------------------------------
-- 枚举类型
-- -----------------------------------------------------------
CREATE TYPE collect_source_type AS ENUM (
    'maccms',       -- 苹果CMS
    'cms',          -- 海洋CMS
    'api',          -- 自定义API
    'rss',          -- RSS 订阅
    'spider'        -- 爬虫
);

CREATE TYPE collect_status AS ENUM (
    'idle',         -- 空闲
    'running',      -- 运行中
    'success',      -- 成功
    'failed',       -- 失败
    'paused'        -- 已暂停
);

CREATE TYPE collect_category AS ENUM (
    'movie',        -- 电影
    'tv',           -- 电视剧
    'anime',        -- 动漫
    'variety',      -- 综艺
    'documentary'   -- 纪录片
);

-- -----------------------------------------------------------
-- 采集源表
-- -----------------------------------------------------------
CREATE TABLE collect_sources (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(200) NOT NULL,
    api_url         VARCHAR(2048) NOT NULL,                    -- 采集 API 地址
    source_type     collect_source_type NOT NULL DEFAULT 'maccms',
    category        collect_category DEFAULT 'movie',
    api_key         VARCHAR(500) DEFAULT '',                   -- API 密钥
    api_param       JSONB DEFAULT '{}',                        -- API 请求参数
    headers         JSONB DEFAULT '{}',                        -- 自定义请求头
    interval        INTEGER NOT NULL DEFAULT 3600,             -- 采集间隔（秒）
    max_pages       INTEGER NOT NULL DEFAULT 10,               -- 最大采集页数
    timeout         INTEGER NOT NULL DEFAULT 30,               -- 请求超时（秒）
    retry_count     INTEGER NOT NULL DEFAULT 3,                -- 失败重试次数
    status          collect_status NOT NULL DEFAULT 'idle',
    last_sync       TIMESTAMPTZ,                               -- 上次同步时间
    last_error      TEXT,                                      -- 上次错误信息
    total_collected INTEGER DEFAULT 0,                         -- 累计采集数
    total_new       INTEGER DEFAULT 0,                         -- 累计新增数
    extra_info      JSONB DEFAULT '{}',
    deleted_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (name)
);

COMMENT ON TABLE collect_sources IS '采集源表';
COMMENT ON COLUMN collect_sources.api_url IS '采集 API 地址';
COMMENT ON COLUMN collect_sources.source_type IS '采集源类型：maccms/cms/api/rss/spider';
COMMENT ON COLUMN collect_sources.interval IS '采集间隔（秒）';
COMMENT ON COLUMN collect_sources.max_pages IS '最大采集页数';
COMMENT ON COLUMN collect_sources.last_sync IS '上次同步时间';
COMMENT ON COLUMN collect_sources.total_collected IS '累计采集数';

-- updated_at 触发器
CREATE TRIGGER trg_collect_sources_updated_at
    BEFORE UPDATE ON collect_sources
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- 采集日志表
-- -----------------------------------------------------------
CREATE TABLE collect_logs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    collect_source_id   UUID NOT NULL REFERENCES collect_sources(id) ON DELETE CASCADE,
    status              collect_status NOT NULL DEFAULT 'running',
    total_collected     INTEGER NOT NULL DEFAULT 0,            -- 本次采集总数
    total_new           INTEGER NOT NULL DEFAULT 0,            -- 本次新增数
    total_updated       INTEGER NOT NULL DEFAULT 0,            -- 本次更新数
    total_failed        INTEGER NOT NULL DEFAULT 0,            -- 本次失败数
    error_message       TEXT,                                   -- 错误信息
    started_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    finished_at         TIMESTAMPTZ,
    duration_seconds    INTEGER,                                -- 耗时（秒）
    extra_info          JSONB DEFAULT '{}',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE collect_logs IS '采集日志表';
COMMENT ON COLUMN collect_logs.total_collected IS '本次采集总数';
COMMENT ON COLUMN collect_logs.total_new IS '本次新增数';
COMMENT ON COLUMN collect_logs.total_updated IS '本次更新数';
COMMENT ON COLUMN collect_logs.duration_seconds IS '采集耗时（秒）';

-- -----------------------------------------------------------
-- 采集任务队列（可选扩展）
-- -----------------------------------------------------------
CREATE TABLE collect_tasks (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    collect_source_id   UUID NOT NULL REFERENCES collect_sources(id) ON DELETE CASCADE,
    task_type           VARCHAR(50) NOT NULL DEFAULT 'full',   -- full/incremental/single
    target_url          VARCHAR(2048),                          -- 单个采集目标URL
    priority            INTEGER NOT NULL DEFAULT 0,             -- 优先级，数字越大越优先
    status              collect_status NOT NULL DEFAULT 'idle',
    retry_count         INTEGER NOT NULL DEFAULT 0,
    max_retries         INTEGER NOT NULL DEFAULT 3,
    scheduled_at        TIMESTAMPTZ,                            -- 计划执行时间
    started_at          TIMESTAMPTZ,
    finished_at         TIMESTAMPTZ,
    error_message       TEXT,
    result_info         JSONB DEFAULT '{}',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE collect_tasks IS '采集任务队列表';
COMMENT ON COLUMN collect_tasks.task_type IS '任务类型：full(全量)/incremental(增量)/single(单个)';
COMMENT ON COLUMN collect_tasks.priority IS '优先级，数字越大越优先';

CREATE TRIGGER trg_collect_tasks_updated_at
    BEFORE UPDATE ON collect_tasks
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- 索引
-- -----------------------------------------------------------
CREATE INDEX idx_collect_sources_type ON collect_sources(source_type);
CREATE INDEX idx_collect_sources_status ON collect_sources(status);
CREATE INDEX idx_collect_sources_last_sync ON collect_sources(last_sync DESC);
CREATE INDEX idx_collect_sources_deleted_at ON collect_sources(deleted_at) WHERE deleted_at IS NOT NULL;

CREATE INDEX idx_collect_logs_source_id ON collect_logs(collect_source_id);
CREATE INDEX idx_collect_logs_status ON collect_logs(status);
CREATE INDEX idx_collect_logs_started_at ON collect_logs(started_at DESC);

CREATE INDEX idx_collect_tasks_source_id ON collect_tasks(collect_source_id);
CREATE INDEX idx_collect_tasks_status ON collect_tasks(status);
CREATE INDEX idx_collect_tasks_priority ON collect_tasks(priority DESC, status);
CREATE INDEX idx_collect_tasks_scheduled_at ON collect_tasks(scheduled_at) WHERE status = 'idle';

-- -----------------------------------------------------------
-- 记录迁移
-- -----------------------------------------------------------
INSERT INTO schema_migrations (filename) VALUES ('004_collect_system.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
