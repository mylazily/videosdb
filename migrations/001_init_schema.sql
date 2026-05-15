-- ============================================================
-- 001_init_schema.sql
-- 核心表结构：视频、剧集、播放源
-- ============================================================
-- 说明：
--   - 此迁移创建 videosdb 的核心数据表
--   - 使用 UUID 作为主键，gen_random_uuid() 来自 pgcrypto 扩展
--   - 所有表支持软删除（deleted_at）和自动时间戳
-- ============================================================

BEGIN;

-- -----------------------------------------------------------
-- 启用必要扩展
-- -----------------------------------------------------------
-- pgcrypto: 提供 gen_random_uuid() 函数用于生成 UUID v4
-- 注意：uuid-ossp 扩展已弃用，统一使用 pgcrypto 的函数
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

COMMENT ON EXTENSION "pgcrypto" IS '提供加密函数和 UUID 生成函数';

-- -----------------------------------------------------------
-- 枚举类型定义
-- -----------------------------------------------------------

-- 视频状态枚举
CREATE TYPE video_status AS ENUM (
    'pending',      -- 待审核
    'published',    -- 已发布
    'hidden',       -- 已隐藏
    'banned'        -- 已封禁
);

COMMENT ON TYPE video_status IS '视频状态枚举';

-- 视频格式枚举
CREATE TYPE video_format AS ENUM (
    'hls',          -- HLS (m3u8) 流媒体格式
    'mp4',          -- MP4 标准视频格式
    'flv',          -- FLV Flash 视频格式
    'dash'          -- DASH 自适应流媒体格式
);

COMMENT ON TYPE video_format IS '视频播放格式枚举';

-- 剧集状态枚举
CREATE TYPE episode_status AS ENUM (
    'pending',      -- 待发布
    'published',    -- 已发布
    'error'         -- 资源错误
);

COMMENT ON TYPE episode_status IS '剧集状态枚举';

-- -----------------------------------------------------------
-- 视频主表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS videos (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title               VARCHAR(500) NOT NULL,
    sub_title           VARCHAR(500),
    description         TEXT,
    cover_url           VARCHAR(1024),
    cover_vertical      VARCHAR(1024),                      -- 竖版封面（移动端使用）
    category            VARCHAR(100) NOT NULL DEFAULT '',   -- 分类：电影/电视剧/动漫/综艺/纪录片
    tags                VARCHAR(500) DEFAULT '',            -- 标签，逗号分隔
    year                SMALLINT,                           -- 年份
    area                VARCHAR(100) DEFAULT '',            -- 地区：大陆/香港/美国/日本/韩国等
    language            VARCHAR(50) DEFAULT '',             -- 语言
    director            VARCHAR(500) DEFAULT '',            -- 导演
    actors              VARCHAR(2000) DEFAULT '',           -- 演员列表
    total_episodes      INTEGER DEFAULT 1,                  -- 总集数
    current_episode     INTEGER DEFAULT 0,                  -- 当前更新集数
    score               DECIMAL(3,1) DEFAULT 0 CHECK (score >= 0 AND score <= 10),
    score_count         INTEGER DEFAULT 0,                  -- 评分人数
    view_count          BIGINT DEFAULT 0,                   -- 总播放量
    daily_view_count    BIGINT DEFAULT 0,                   -- 日播放量（用于排行榜）
    weekly_view_count   BIGINT DEFAULT 0,                   -- 周播放量
    monthly_view_count  BIGINT DEFAULT 0,                   -- 月播放量
    like_count          INTEGER DEFAULT 0,                  -- 点赞数
    dislike_count       INTEGER DEFAULT 0,                  -- 点踩数
    favorite_count      INTEGER DEFAULT 0,                  -- 收藏数
    comment_count       INTEGER DEFAULT 0,                  -- 评论数
    status              video_status NOT NULL DEFAULT 'pending',
    source_from         VARCHAR(200) DEFAULT '',            -- 来源标识（如采集源名称）
    source_id           VARCHAR(200) DEFAULT '',            -- 来源原始ID
    extra_info          JSONB DEFAULT '{}',                 -- 扩展信息 JSONB
    search_vector       TSVECTOR,                           -- 全文检索向量（在 005 中建立触发器）
    published_at        TIMESTAMPTZ,                        -- 发布时间
    deleted_at          TIMESTAMPTZ,                        -- 软删除时间戳
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 表和列注释
COMMENT ON TABLE videos IS '视频主表：存储所有影视内容的基础信息';
COMMENT ON COLUMN videos.id IS 'UUID v4 主键，分布式友好';
COMMENT ON COLUMN videos.title IS '视频标题';
COMMENT ON COLUMN videos.sub_title IS '副标题或英文名';
COMMENT ON COLUMN videos.description IS '视频简介';
COMMENT ON COLUMN videos.cover_url IS '封面图片 URL';
COMMENT ON COLUMN videos.cover_vertical IS '竖版封面 URL（移动端使用）';
COMMENT ON COLUMN videos.category IS '分类：电影/电视剧/动漫/综艺/纪录片';
COMMENT ON COLUMN videos.tags IS '标签，逗号分隔';
COMMENT ON COLUMN videos.year IS '年份';
COMMENT ON COLUMN videos.area IS '地区：大陆/香港/美国/日本/韩国等';
COMMENT ON COLUMN videos.language IS '语言';
COMMENT ON COLUMN videos.director IS '导演';
COMMENT ON COLUMN videos.actors IS '演员列表，逗号分隔';
COMMENT ON COLUMN videos.total_episodes IS '总集数';
COMMENT ON COLUMN videos.current_episode IS '当前更新集数';
COMMENT ON COLUMN videos.score IS '评分 0-10';
COMMENT ON COLUMN videos.score_count IS '评分人数';
COMMENT ON COLUMN videos.view_count IS '总播放量';
COMMENT ON COLUMN videos.daily_view_count IS '日播放量';
COMMENT ON COLUMN videos.weekly_view_count IS '周播放量';
COMMENT ON COLUMN videos.monthly_view_count IS '月播放量';
COMMENT ON COLUMN videos.status IS '状态：pending/published/hidden/banned';
COMMENT ON COLUMN videos.source_from IS '来源标识（如采集源名称）';
COMMENT ON COLUMN videos.source_id IS '来源原始ID';
COMMENT ON COLUMN videos.extra_info IS '扩展信息 JSONB';
COMMENT ON COLUMN videos.search_vector IS '全文检索向量';
COMMENT ON COLUMN videos.published_at IS '发布时间';
COMMENT ON COLUMN videos.deleted_at IS '软删除时间戳，非空表示已删除';
COMMENT ON COLUMN videos.created_at IS '创建时间';
COMMENT ON COLUMN videos.updated_at IS '更新时间';

-- -----------------------------------------------------------
-- 视频播放源表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS video_sources (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id        UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    source_name     VARCHAR(200) NOT NULL DEFAULT '',      -- 来源名称：量子资源、红牛资源等
    play_url        VARCHAR(2048),                         -- 单线路播放地址（兼容旧数据）
    play_links      JSONB DEFAULT '[]',                    -- 聚合多线路: [{"from":"量子资源","url":"m3u8_url"},...]
    format          video_format NOT NULL DEFAULT 'hls',
    sort_order      INTEGER NOT NULL DEFAULT 0,            -- 排序权重
    status          BOOLEAN NOT NULL DEFAULT TRUE,         -- 是否启用
    extra_info      JSONB DEFAULT '{}',                    -- 扩展信息
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE video_sources IS '视频播放源表：存储视频的播放线路信息';
COMMENT ON COLUMN video_sources.video_id IS '关联的视频 ID';
COMMENT ON COLUMN video_sources.source_name IS '来源名称：量子资源、红牛资源等';
COMMENT ON COLUMN video_sources.play_url IS '单线路播放地址（兼容旧数据）';
COMMENT ON COLUMN video_sources.play_links IS '聚合多线路 JSONB，格式: [{"from":"来源名","url":"播放地址"}]';
COMMENT ON COLUMN video_sources.format IS '视频格式：hls/mp4/flv/dash';
COMMENT ON COLUMN video_sources.sort_order IS '排序权重，数字越小越靠前';
COMMENT ON COLUMN video_sources.status IS '是否启用';
COMMENT ON COLUMN video_sources.extra_info IS '扩展信息 JSONB';

-- -----------------------------------------------------------
-- 剧集表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS episodes (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id        UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    title           VARCHAR(500) NOT NULL DEFAULT '',      -- 剧集标题
    number          INTEGER NOT NULL,                      -- 集数编号
    duration        INTEGER DEFAULT 0,                     -- 时长（秒）
    status          episode_status NOT NULL DEFAULT 'pending',
    source_from     VARCHAR(200) DEFAULT '',               -- 来源标识
    source_id       VARCHAR(200) DEFAULT '',               -- 来源原始ID
    extra_info      JSONB DEFAULT '{}',                    -- 扩展信息
    deleted_at      TIMESTAMPTZ,                           -- 软删除时间戳
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (video_id, number)
);

COMMENT ON TABLE episodes IS '剧集表：存储电视剧、动漫等分集内容';
COMMENT ON COLUMN episodes.video_id IS '关联的视频 ID';
COMMENT ON COLUMN episodes.title IS '剧集标题';
COMMENT ON COLUMN episodes.number IS '集数编号';
COMMENT ON COLUMN episodes.duration IS '时长（秒）';
COMMENT ON COLUMN episodes.status IS '状态：pending/published/error';
COMMENT ON COLUMN episodes.source_from IS '来源标识';
COMMENT ON COLUMN episodes.source_id IS '来源原始ID';
COMMENT ON COLUMN episodes.extra_info IS '扩展信息 JSONB';
COMMENT ON COLUMN episodes.deleted_at IS '软删除时间戳';

-- -----------------------------------------------------------
-- 剧集播放源表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS episode_sources (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    episode_id      UUID NOT NULL REFERENCES episodes(id) ON DELETE CASCADE,
    source_name     VARCHAR(200) NOT NULL DEFAULT '',      -- 来源名称
    play_url        VARCHAR(2048) NOT NULL,                -- 播放地址
    format          video_format NOT NULL DEFAULT 'hls',
    sort_order      INTEGER NOT NULL DEFAULT 0,            -- 排序权重
    status          BOOLEAN NOT NULL DEFAULT TRUE,         -- 是否启用
    extra_info      JSONB DEFAULT '{}',                    -- 扩展信息
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE episode_sources IS '剧集播放源表：存储各剧集的播放线路';
COMMENT ON COLUMN episode_sources.episode_id IS '关联的剧集 ID';
COMMENT ON COLUMN episode_sources.source_name IS '来源名称';
COMMENT ON COLUMN episode_sources.play_url IS '播放地址';
COMMENT ON COLUMN episode_sources.format IS '视频格式';
COMMENT ON COLUMN episode_sources.sort_order IS '排序权重';
COMMENT ON COLUMN episode_sources.status IS '是否启用';
COMMENT ON COLUMN episode_sources.extra_info IS '扩展信息 JSONB';

-- -----------------------------------------------------------
-- 自动更新 updated_at 触发器函数
-- -----------------------------------------------------------
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION update_updated_at_column() IS '自动更新 updated_at 字段的触发器函数';

-- 为所有核心表添加 updated_at 自动更新触发器
CREATE TRIGGER trg_videos_updated_at
    BEFORE UPDATE ON videos
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_video_sources_updated_at
    BEFORE UPDATE ON video_sources
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_episodes_updated_at
    BEFORE UPDATE ON episodes
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_episode_sources_updated_at
    BEFORE UPDATE ON episode_sources
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- 基础索引
-- -----------------------------------------------------------

-- videos 表索引
CREATE INDEX IF NOT EXISTS idx_videos_category ON videos(category);
CREATE INDEX IF NOT EXISTS idx_videos_year ON videos(year);
CREATE INDEX IF NOT EXISTS idx_videos_area ON videos(area);
CREATE INDEX IF NOT EXISTS idx_videos_status ON videos(status);
CREATE INDEX IF NOT EXISTS idx_videos_score ON videos(score DESC);
CREATE INDEX IF NOT EXISTS idx_videos_view_count ON videos(view_count DESC);
CREATE INDEX IF NOT EXISTS idx_videos_daily_view ON videos(daily_view_count DESC);
CREATE INDEX IF NOT EXISTS idx_videos_created_at ON videos(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_videos_deleted_at ON videos(deleted_at) WHERE deleted_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_videos_source ON videos(source_from, source_id);

-- video_sources 表索引
CREATE INDEX IF NOT EXISTS idx_video_sources_video_id ON video_sources(video_id);
CREATE INDEX IF NOT EXISTS idx_video_sources_source_name ON video_sources(source_name);

-- episodes 表索引
CREATE INDEX IF NOT EXISTS idx_episodes_video_id ON episodes(video_id);
CREATE INDEX IF NOT EXISTS idx_episodes_number ON episodes(video_id, number);

-- episode_sources 表索引
CREATE INDEX IF NOT EXISTS idx_episode_sources_episode_id ON episode_sources(episode_id);

-- -----------------------------------------------------------
-- 迁移记录表（仅在第一个迁移中创建）
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS schema_migrations (
    id              SERIAL PRIMARY KEY,
    filename        VARCHAR(255) NOT NULL UNIQUE,
    applied_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    checksum        VARCHAR(64),                           -- 文件校验和（可选）
    execution_time  INTEGER                                -- 执行时间（毫秒，可选）
);

COMMENT ON TABLE schema_migrations IS '数据库迁移记录表，跟踪已应用的迁移';
COMMENT ON COLUMN schema_migrations.filename IS '迁移文件名';
COMMENT ON COLUMN schema_migrations.applied_at IS '应用时间';
COMMENT ON COLUMN schema_migrations.checksum IS '文件校验和（用于验证迁移文件完整性）';
COMMENT ON COLUMN schema_migrations.execution_time IS '执行耗时（毫秒）';

-- 记录本次迁移
INSERT INTO schema_migrations (filename) VALUES ('001_init_schema.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
