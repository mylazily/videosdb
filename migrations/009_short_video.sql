-- ============================================================
-- 009_short_video.sql
-- 短视频系统：独立于长视频的短视频内容管理
-- ============================================================
-- 说明：
--   - 创建短视频表，用于 /short 专区
--   - 短视频为独立于长视频（videos 表）的内容类型
--   - 支持动态预览（GIF/WebP）、标签数组、统计计数
--   - 使用 TEXT 数组存储标签，支持 GIN 索引高效查询
-- ============================================================

BEGIN;

-- -----------------------------------------------------------
-- 枚举类型定义
-- -----------------------------------------------------------

-- 短视频状态枚举
CREATE TYPE short_video_status AS ENUM (
    'pending',      -- 待审核
    'published',    -- 已发布
    'hidden',       -- 已隐藏
    'banned'        -- 已封禁
);

COMMENT ON TYPE short_video_status IS '短视频状态枚举';

-- -----------------------------------------------------------
-- 短视频表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS short_videos (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title           VARCHAR(500) NOT NULL,                    -- 短视频标题
    description     TEXT DEFAULT '',                           -- 短视频描述
    cover_url       VARCHAR(1024),                            -- 封面图片 URL
    preview_url     VARCHAR(1024),                            -- 动态预览 URL（GIF/WebP 格式，鼠标悬停时播放）
    video_url       VARCHAR(2048) NOT NULL,                   -- 视频播放地址（m3u8 格式）
    duration        INTEGER NOT NULL DEFAULT 0,               -- 时长（秒），通常 15-300 秒
    source_from     VARCHAR(200) DEFAULT '',                  -- 来源标识
    source_id       VARCHAR(200) DEFAULT '',                  -- 来源原始 ID
    view_count      BIGINT NOT NULL DEFAULT 0,                -- 播放量
    like_count      INTEGER NOT NULL DEFAULT 0,               -- 点赞数
    share_count     INTEGER NOT NULL DEFAULT 0,               -- 分享数
    tags            TEXT[] DEFAULT '{}',                       -- 标签数组（如 '{短剧,穿越,甜宠}'）
    status          short_video_status NOT NULL DEFAULT 'pending',
    deleted_at      TIMESTAMPTZ,                              -- 软删除时间戳
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE short_videos IS '短视频表：独立于长视频的短视频内容，用于 /short 专区';
COMMENT ON COLUMN short_videos.id IS 'UUID v4 主键';
COMMENT ON COLUMN short_videos.title IS '短视频标题';
COMMENT ON COLUMN short_videos.description IS '短视频描述';
COMMENT ON COLUMN short_videos.cover_url IS '封面图片 URL';
COMMENT ON COLUMN short_videos.preview_url IS '动态预览 URL（GIF/WebP 格式，鼠标悬停时播放预览动画）';
COMMENT ON COLUMN short_videos.video_url IS '视频播放地址（m3u8 格式）';
COMMENT ON COLUMN short_videos.duration IS '时长（秒），通常 15-300 秒';
COMMENT ON COLUMN short_videos.source_from IS '来源标识（如采集源名称）';
COMMENT ON COLUMN short_videos.source_id IS '来源原始 ID';
COMMENT ON COLUMN short_videos.view_count IS '播放量';
COMMENT ON COLUMN short_videos.like_count IS '点赞数';
COMMENT ON COLUMN short_videos.share_count IS '分享数';
COMMENT ON COLUMN short_videos.tags IS '标签数组（TEXT[]），如 ARRAY['短剧','穿越','甜宠']';
COMMENT ON COLUMN short_videos.status IS '状态：pending/published/hidden/banned';
COMMENT ON COLUMN short_videos.deleted_at IS '软删除时间戳';

-- updated_at 触发器
CREATE TRIGGER trg_short_videos_updated_at
    BEFORE UPDATE ON short_videos
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- 索引
-- -----------------------------------------------------------

-- 基础索引
CREATE INDEX IF NOT EXISTS idx_short_videos_status ON short_videos(status);
CREATE INDEX IF NOT EXISTS idx_short_videos_duration ON short_videos(duration);
CREATE INDEX IF NOT EXISTS idx_short_videos_source ON short_videos(source_from, source_id);

-- 播放量排序索引（用于热门短视频排行）
CREATE INDEX IF NOT EXISTS idx_short_videos_view_count ON short_videos(view_count DESC)
    WHERE status = 'published' AND deleted_at IS NULL;

-- 创建时间排序索引（用于最新短视频列表）
CREATE INDEX IF NOT EXISTS idx_short_videos_created_at ON short_videos(created_at DESC)
    WHERE status = 'published' AND deleted_at IS NULL;

-- 标签 GIN 索引（支持数组包含查询，如 WHERE tags @> ARRAY['短剧']）
CREATE INDEX IF NOT EXISTS idx_short_videos_tags ON short_videos USING GIN (tags);

-- 软删除索引
CREATE INDEX IF NOT EXISTS idx_short_videos_deleted_at ON short_videos(deleted_at) WHERE deleted_at IS NOT NULL;

-- 已发布短视频部分索引（覆盖索引，支持 Index Only Scan）
CREATE INDEX IF NOT EXISTS idx_short_videos_published_cover
    ON short_videos (created_at DESC)
    INCLUDE (title, cover_url, preview_url, duration, view_count, like_count)
    WHERE status = 'published' AND deleted_at IS NULL;

-- -----------------------------------------------------------
-- 记录迁移
-- -----------------------------------------------------------
INSERT INTO schema_migrations (filename) VALUES ('009_short_video.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
