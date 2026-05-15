-- ============================================================
-- 001_init_schema.sql
-- 核心表结构：视频、剧集、播放源
-- ============================================================
-- 注意：此迁移假设已通过 init.sh 创建了 UUID 扩展
-- ============================================================

BEGIN;

-- -----------------------------------------------------------
-- 启用必要扩展（如果尚未启用）
-- -----------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- -----------------------------------------------------------
-- 枚举类型
-- -----------------------------------------------------------
CREATE TYPE video_status AS ENUM (
    'pending',      -- 待审核
    'published',    -- 已发布
    'hidden',       -- 已隐藏
    'banned'        -- 已封禁
);

CREATE TYPE video_format AS ENUM (
    'hls',          -- HLS (m3u8)
    'mp4',          -- MP4
    'flv',          -- FLV
    'dash'          -- DASH
);

CREATE TYPE episode_status AS ENUM (
    'pending',      -- 待发布
    'published',    -- 已发布
    'error'         -- 资源错误
);

-- -----------------------------------------------------------
-- 视频主表
-- -----------------------------------------------------------
CREATE TABLE videos (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title           VARCHAR(500) NOT NULL,
    sub_title       VARCHAR(500),
    description     TEXT,
    cover_url       VARCHAR(1024),
    cover_vertical  VARCHAR(1024),           -- 竖版封面
    category        VARCHAR(100) NOT NULL DEFAULT '',    -- 分类：电影/电视剧/动漫/综艺/纪录片
    tags            VARCHAR(500) DEFAULT '',              -- 标签，逗号分隔
    year            SMALLINT,
    area            VARCHAR(100) DEFAULT '',              -- 地区：大陆/香港/美国/日本/韩国等
    language        VARCHAR(50) DEFAULT '',
    director        VARCHAR(500) DEFAULT '',
    actors          VARCHAR(2000) DEFAULT '',
    total_episodes  INTEGER DEFAULT 1,                     -- 总集数
    current_episode INTEGER DEFAULT 0,                     -- 当前更新集数
    score           DECIMAL(3,1) DEFAULT 0 CHECK (score >= 0 AND score <= 10),
    score_count     INTEGER DEFAULT 0,                     -- 评分人数
    view_count      BIGINT DEFAULT 0,
    daily_view_count BIGINT DEFAULT 0,                     -- 日播放量（用于排行榜）
    weekly_view_count BIGINT DEFAULT 0,                    -- 周播放量
    monthly_view_count BIGINT DEFAULT 0,                   -- 月播放量
    like_count      INTEGER DEFAULT 0,
    dislike_count   INTEGER DEFAULT 0,
    favorite_count  INTEGER DEFAULT 0,
    comment_count   INTEGER DEFAULT 0,
    status          video_status NOT NULL DEFAULT 'pending',
    source_from     VARCHAR(200) DEFAULT '',               -- 来源标识
    source_id       VARCHAR(200) DEFAULT '',               -- 来源原始ID
    extra_info      JSONB DEFAULT '{}',                    -- 扩展信息
    search_vector   TSVECTOR,                              -- 全文检索向量（在 005 中建立触发器）
    published_at    TIMESTAMPTZ,
    deleted_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE videos IS '视频主表';
COMMENT ON COLUMN videos.id IS 'UUID 主键';
COMMENT ON COLUMN videos.title IS '视频标题';
COMMENT ON COLUMN videos.sub_title IS '副标题';
COMMENT ON COLUMN videos.category IS '分类：电影/电视剧/动漫/综艺/纪录片';
COMMENT ON COLUMN videos.tags IS '标签，逗号分隔';
COMMENT ON COLUMN videos.area IS '地区';
COMMENT ON COLUMN videos.director IS '导演';
COMMENT ON COLUMN videos.actors IS '演员列表';
COMMENT ON COLUMN videos.total_episodes IS '总集数';
COMMENT ON COLUMN videos.current_episode IS '当前更新集数';
COMMENT ON COLUMN videos.score IS '评分 0-10';
COMMENT ON COLUMN videos.view_count IS '总播放量';
COMMENT ON COLUMN videos.daily_view_count IS '日播放量';
COMMENT ON COLUMN videos.weekly_view_count IS '周播放量';
COMMENT ON COLUMN videos.monthly_view_count IS '月播放量';
COMMENT ON COLUMN videos.status IS '状态：pending/published/hidden/banned';
COMMENT ON COLUMN videos.source_from IS '来源标识（如采集源名称）';
COMMENT ON COLUMN videos.source_id IS '来源原始ID';
COMMENT ON COLUMN videos.extra_info IS '扩展信息 JSONB';
COMMENT ON COLUMN videos.search_vector IS '全文检索向量';
COMMENT ON COLUMN videos.deleted_at IS '软删除时间戳';

-- -----------------------------------------------------------
-- 视频播放源表
-- -----------------------------------------------------------
CREATE TABLE video_sources (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id        UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    source_name     VARCHAR(200) NOT NULL DEFAULT '',      -- 来源名称：量子资源、红牛资源等
    play_url        VARCHAR(2048),                         -- 单线路播放地址
    play_links      JSONB DEFAULT '[]',                    -- 聚合多线路: [{"from":"量子资源","url":"m3u8_url"},...]
    format          video_format NOT NULL DEFAULT 'hls',
    sort_order      INTEGER NOT NULL DEFAULT 0,
    status          BOOLEAN NOT NULL DEFAULT TRUE,
    extra_info      JSONB DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE video_sources IS '视频播放源表';
COMMENT ON COLUMN video_sources.play_links IS '聚合多线路 JSONB，格式: [{"from":"来源名","url":"播放地址"}]';
COMMENT ON COLUMN video_sources.play_url IS '单线路播放地址（兼容旧数据）';

-- -----------------------------------------------------------
-- 剧集表
-- -----------------------------------------------------------
CREATE TABLE episodes (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id        UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    title           VARCHAR(500) NOT NULL DEFAULT '',
    number          INTEGER NOT NULL,                      -- 集数
    duration        INTEGER DEFAULT 0,                     -- 时长（秒）
    status          episode_status NOT NULL DEFAULT 'pending',
    source_from     VARCHAR(200) DEFAULT '',
    source_id       VARCHAR(200) DEFAULT '',
    extra_info      JSONB DEFAULT '{}',
    deleted_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (video_id, number)
);

COMMENT ON TABLE episodes IS '剧集表';
COMMENT ON COLUMN episodes.number IS '集数编号';
COMMENT ON COLUMN episodes.duration IS '时长（秒）';

-- -----------------------------------------------------------
-- 剧集播放源表
-- -----------------------------------------------------------
CREATE TABLE episode_sources (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    episode_id      UUID NOT NULL REFERENCES episodes(id) ON DELETE CASCADE,
    source_name     VARCHAR(200) NOT NULL DEFAULT '',
    play_url        VARCHAR(2048) NOT NULL,
    format          video_format NOT NULL DEFAULT 'hls',
    sort_order      INTEGER NOT NULL DEFAULT 0,
    status          BOOLEAN NOT NULL DEFAULT TRUE,
    extra_info      JSONB DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE episode_sources IS '剧集播放源表';

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
CREATE INDEX idx_videos_category ON videos(category);
CREATE INDEX idx_videos_year ON videos(year);
CREATE INDEX idx_videos_area ON videos(area);
CREATE INDEX idx_videos_status ON videos(status);
CREATE INDEX idx_videos_score ON videos(score DESC);
CREATE INDEX idx_videos_view_count ON videos(view_count DESC);
CREATE INDEX idx_videos_daily_view ON videos(daily_view_count DESC);
CREATE INDEX idx_videos_created_at ON videos(created_at DESC);
CREATE INDEX idx_videos_deleted_at ON videos(deleted_at) WHERE deleted_at IS NOT NULL;
CREATE INDEX idx_videos_source ON videos(source_from, source_id);

CREATE INDEX idx_video_sources_video_id ON video_sources(video_id);
CREATE INDEX idx_video_sources_source_name ON video_sources(source_name);

CREATE INDEX idx_episodes_video_id ON episodes(video_id);
CREATE INDEX idx_episodes_number ON episodes(video_id, number);

CREATE INDEX idx_episode_sources_episode_id ON episode_sources(episode_id);

-- -----------------------------------------------------------
-- 记录迁移
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS schema_migrations (
    id              SERIAL PRIMARY KEY,
    filename        VARCHAR(255) NOT NULL UNIQUE,
    applied_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO schema_migrations (filename) VALUES ('001_init_schema.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
