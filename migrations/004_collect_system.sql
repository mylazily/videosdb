-- ============================================================
-- 004_collect_system.sql
-- MacCMS 采集源管理
-- ============================================================
-- 说明：
--   - 创建采集源管理相关表
--   - 支持多种采集源类型（MacCMS、API、RSS等）
--   - 支持采集任务队列和日志记录
-- ============================================================

BEGIN;

-- -----------------------------------------------------------
-- 枚举类型定义
-- -----------------------------------------------------------

-- 采集源类型枚举
CREATE TYPE collect_source_type AS ENUM (
    'maccms',       -- 苹果CMS
    'cms',          -- 海洋CMS
    'api',          -- 自定义API
    'rss',          -- RSS 订阅
    'spider'        -- 爬虫
);

COMMENT ON TYPE collect_source_type IS '采集源类型枚举';

-- 采集状态枚举
CREATE TYPE collect_status AS ENUM (
    'idle',         -- 空闲
    'running',      -- 运行中
    'success',      -- 成功
    'failed',       -- 失败
    'paused'        -- 已暂停
);

COMMENT ON TYPE collect_status IS '采集状态枚举';

-- 采集分类枚举
CREATE TYPE collect_category AS ENUM (
    'movie',        -- 电影
    'tv',           -- 电视剧
    'anime',        -- 动漫
    'variety',      -- 综艺
    'documentary'   -- 纪录片
);

COMMENT ON TYPE collect_category IS '采集分类枚举';

-- -----------------------------------------------------------
-- 采集源表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS collect_sources (
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

COMMENT ON TABLE collect_sources IS '采集源表：管理视频采集来源';
COMMENT ON COLUMN collect_sources.name IS '采集源名称';
COMMENT ON COLUMN collect_sources.api_url IS '采集 API 地址';
COMMENT ON COLUMN collect_sources.source_type IS '采集源类型：maccms/cms/api/rss/spider';
COMMENT ON COLUMN collect_sources.category IS '采集分类：movie/tv/anime/variety/documentary';
COMMENT ON COLUMN collect_sources.api_key IS 'API 密钥';
COMMENT ON COLUMN collect_sources.api_param IS 'API 请求参数 JSONB';
COMMENT ON COLUMN collect_sources.headers IS '自定义请求头 JSONB';
COMMENT ON COLUMN collect_sources.interval IS '采集间隔（秒）';
COMMENT ON COLUMN collect_sources.max_pages IS '最大采集页数';
COMMENT ON COLUMN collect_sources.timeout IS '请求超时（秒）';
COMMENT ON COLUMN collect_sources.retry_count IS '失败重试次数';
COMMENT ON COLUMN collect_sources.status IS '状态：idle/running/success/failed/paused';
COMMENT ON COLUMN collect_sources.last_sync IS '上次同步时间';
COMMENT ON COLUMN collect_sources.last_error IS '上次错误信息';
COMMENT ON COLUMN collect_sources.total_collected IS '累计采集数';
COMMENT ON COLUMN collect_sources.total_new IS '累计新增数';
COMMENT ON COLUMN collect_sources.extra_info IS '扩展信息 JSONB';
COMMENT ON COLUMN collect_sources.deleted_at IS '软删除时间戳';

-- updated_at 触发器
CREATE TRIGGER trg_collect_sources_updated_at
    BEFORE UPDATE ON collect_sources
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- 采集日志表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS collect_logs (
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

COMMENT ON TABLE collect_logs IS '采集日志表：记录每次采集的详细日志';
COMMENT ON COLUMN collect_logs.collect_source_id IS '采集源 ID';
COMMENT ON COLUMN collect_logs.status IS '采集状态';
COMMENT ON COLUMN collect_logs.total_collected IS '本次采集总数';
COMMENT ON COLUMN collect_logs.total_new IS '本次新增数';
COMMENT ON COLUMN collect_logs.total_updated IS '本次更新数';
COMMENT ON COLUMN collect_logs.total_failed IS '本次失败数';
COMMENT ON COLUMN collect_logs.error_message IS '错误信息';
COMMENT ON COLUMN collect_logs.started_at IS '开始时间';
COMMENT ON COLUMN collect_logs.finished_at IS '结束时间';
COMMENT ON COLUMN collect_logs.duration_seconds IS '采集耗时（秒）';
COMMENT ON COLUMN collect_logs.extra_info IS '扩展信息 JSONB';

-- -----------------------------------------------------------
-- 采集任务队列表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS collect_tasks (
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

COMMENT ON TABLE collect_tasks IS '采集任务队列表：管理待执行的采集任务';
COMMENT ON COLUMN collect_tasks.collect_source_id IS '采集源 ID';
COMMENT ON COLUMN collect_tasks.task_type IS '任务类型：full(全量)/incremental(增量)/single(单个)';
COMMENT ON COLUMN collect_tasks.target_url IS '单个采集目标URL';
COMMENT ON COLUMN collect_tasks.priority IS '优先级，数字越大越优先';
COMMENT ON COLUMN collect_tasks.status IS '任务状态';
COMMENT ON COLUMN collect_tasks.retry_count IS '已重试次数';
COMMENT ON COLUMN collect_tasks.max_retries IS '最大重试次数';
COMMENT ON COLUMN collect_tasks.scheduled_at IS '计划执行时间';
COMMENT ON COLUMN collect_tasks.started_at IS '开始时间';
COMMENT ON COLUMN collect_tasks.finished_at IS '结束时间';
COMMENT ON COLUMN collect_tasks.error_message IS '错误信息';
COMMENT ON COLUMN collect_tasks.result_info IS '执行结果 JSONB';

CREATE TRIGGER trg_collect_tasks_updated_at
    BEFORE UPDATE ON collect_tasks
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- 索引
-- -----------------------------------------------------------

-- collect_sources 表索引
CREATE INDEX IF NOT EXISTS idx_collect_sources_type ON collect_sources(source_type);
CREATE INDEX IF NOT EXISTS idx_collect_sources_status ON collect_sources(status);
CREATE INDEX IF NOT EXISTS idx_collect_sources_last_sync ON collect_sources(last_sync DESC);
CREATE INDEX IF NOT EXISTS idx_collect_sources_deleted_at ON collect_sources(deleted_at) WHERE deleted_at IS NOT NULL;

-- collect_logs 表索引
CREATE INDEX IF NOT EXISTS idx_collect_logs_source_id ON collect_logs(collect_source_id);
CREATE INDEX IF NOT EXISTS idx_collect_logs_status ON collect_logs(status);
CREATE INDEX IF NOT EXISTS idx_collect_logs_started_at ON collect_logs(started_at DESC);

-- collect_tasks 表索引
CREATE INDEX IF NOT EXISTS idx_collect_tasks_source_id ON collect_tasks(collect_source_id);
CREATE INDEX IF NOT EXISTS idx_collect_tasks_status ON collect_tasks(status);
CREATE INDEX IF NOT EXISTS idx_collect_tasks_priority ON collect_tasks(priority DESC, status);
CREATE INDEX IF NOT EXISTS idx_collect_tasks_scheduled_at ON collect_tasks(scheduled_at) WHERE status = 'idle';

-- -----------------------------------------------------------
-- 记录迁移
-- -----------------------------------------------------------
INSERT INTO schema_migrations (filename) VALUES ('004_collect_system.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
