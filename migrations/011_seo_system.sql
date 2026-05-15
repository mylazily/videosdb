-- ============================================================
-- 011_seo_system.sql
-- SEO 站群系统：SEO 页面管理、Sitemap 缓存、URL 生成
-- ============================================================
-- 说明：
--   - 创建 SEO 专用页面表，支持多种页面类型
--   - 创建 Sitemap 缓存表，管理站点地图生成
--   - 提供 URL 生成函数，支持搜索引擎收录
--   - 支持自定义 meta 信息、canonical URL 等
-- ============================================================

BEGIN;

-- -----------------------------------------------------------
-- 枚举类型定义
-- -----------------------------------------------------------

-- SEO 页面类型枚举
CREATE TYPE seo_page_type AS ENUM (
    'tag',          -- 标签聚合页
    'actor',        -- 演员聚合页
    'director',     -- 导演聚合页
    'category',     -- 分类聚合页
    'special'       -- 专题页
);

COMMENT ON TYPE seo_page_type IS 'SEO 页面类型枚举';

-- Sitemap 类型枚举
CREATE TYPE sitemap_type AS ENUM (
    'video',        -- 视频站点地图
    'tag',          -- 标签站点地图
    'actor',        -- 演员站点地图
    'short'         -- 短视频站点地图
);

COMMENT ON TYPE sitemap_type IS 'Sitemap 类型枚举';

-- SEO 页面状态枚举
CREATE TYPE seo_page_status AS ENUM (
    'draft',        -- 草稿
    'published',    -- 已发布
    'archived'      -- 已归档
);

COMMENT ON TYPE seo_page_status IS 'SEO 页面状态枚举';

-- -----------------------------------------------------------
-- SEO 页面表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS seo_pages (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    page_type       seo_page_type NOT NULL,                   -- 页面类型
    slug            VARCHAR(500) NOT NULL,                    -- URL 路径（如 /tag/short-drama）
    title           VARCHAR(500) NOT NULL,                    -- 页面标题
    description     VARCHAR(1000) DEFAULT '',                 -- Meta Description
    keywords        VARCHAR(500) DEFAULT '',                  -- Meta Keywords（逗号分隔）
    h1_content      VARCHAR(500) DEFAULT '',                  -- H1 标签内容
    content_html    TEXT DEFAULT '',                           -- 页面 HTML 内容
    meta_robots     VARCHAR(100) DEFAULT 'index, follow',     -- Meta Robots 指令
    canonical_url   VARCHAR(1024),                            -- Canonical URL（规范链接）
    view_count      BIGINT NOT NULL DEFAULT 0,                -- 页面浏览量
    status          seo_page_status NOT NULL DEFAULT 'draft',
    published_at    TIMESTAMPTZ,                              -- 发布时间
    deleted_at      TIMESTAMPTZ,                              -- 软删除时间戳
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_seo_pages_type_slug UNIQUE (page_type, slug)
);

COMMENT ON TABLE seo_pages IS 'SEO 页面表：管理搜索引擎优化专用页面（标签页、演员页、专题页等）';
COMMENT ON COLUMN seo_pages.id IS 'UUID v4 主键';
COMMENT ON COLUMN seo_pages.page_type IS '页面类型：tag/actor/director/category/special';
COMMENT ON COLUMN seo_pages.slug IS 'URL 路径（如 /tag/short-drama），与 page_type 组合唯一';
COMMENT ON COLUMN seo_pages.title IS '页面标题（<title> 标签内容）';
COMMENT ON COLUMN seo_pages.description IS 'Meta Description（搜索引擎摘要）';
COMMENT ON COLUMN seo_pages.keywords IS 'Meta Keywords（逗号分隔的关键词）';
COMMENT ON COLUMN seo_pages.h1_content IS 'H1 标签内容';
COMMENT ON COLUMN seo_pages.content_html IS '页面 HTML 内容';
COMMENT ON COLUMN seo_pages.meta_robots IS 'Meta Robots 指令（如 index, follow / noindex, nofollow）';
COMMENT ON COLUMN seo_pages.canonical_url IS 'Canonical URL（规范链接，避免重复内容）';
COMMENT ON COLUMN seo_pages.view_count IS '页面浏览量';
COMMENT ON COLUMN seo_pages.status IS '状态：draft/published/archived';
COMMENT ON COLUMN seo_pages.published_at IS '发布时间';
COMMENT ON COLUMN seo_pages.deleted_at IS '软删除时间戳';

-- updated_at 触发器
CREATE TRIGGER trg_seo_pages_updated_at
    BEFORE UPDATE ON seo_pages
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- Sitemap 缓存表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS sitemap_cache (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sitemap_type        sitemap_type NOT NULL,                -- Sitemap 类型
    file_path           VARCHAR(500) NOT NULL,                -- Sitemap 文件路径（如 /sitemaps/video_1.xml）
    url_count           INTEGER NOT NULL DEFAULT 0,           -- 包含的 URL 数量
    last_generated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),   -- 最后生成时间
    expires_at          TIMESTAMPTZ NOT NULL,                 -- 过期时间
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE sitemap_cache IS 'Sitemap 缓存表：管理站点地图的生成和缓存';
COMMENT ON COLUMN sitemap_cache.sitemap_type IS 'Sitemap 类型：video/tag/actor/short';
COMMENT ON COLUMN sitemap_cache.file_path IS 'Sitemap 文件路径';
COMMENT ON COLUMN sitemap_cache.url_count IS '包含的 URL 数量';
COMMENT ON COLUMN sitemap_cache.last_generated_at IS '最后生成时间';
COMMENT ON COLUMN sitemap_cache.expires_at IS '过期时间';

-- updated_at 触发器
CREATE TRIGGER trg_sitemap_cache_updated_at
    BEFORE UPDATE ON sitemap_cache
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- 函数：生成 Sitemap URL 列表
-- -----------------------------------------------------------
CREATE OR REPLACE FUNCTION generate_sitemap_urls(
    p_page_type seo_page_type,
    p_limit INTEGER DEFAULT 50000
)
RETURNS TABLE (
    url TEXT,
    lastmod TIMESTAMPTZ,
    priority REAL,
    changefreq VARCHAR(20)
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        sp.canonical_url,
        sp.updated_at AS lastmod,
        CASE
            WHEN sp.page_type = 'tag' THEN 0.8
            WHEN sp.page_type = 'actor' THEN 0.7
            WHEN sp.page_type = 'director' THEN 0.6
            WHEN sp.page_type = 'category' THEN 0.9
            WHEN sp.page_type = 'special' THEN 0.8
            ELSE 0.5
        END AS priority,
        CASE
            WHEN sp.view_count > 10000 THEN 'daily'
            WHEN sp.view_count > 1000 THEN 'weekly'
            ELSE 'monthly'
        END AS changefreq
    FROM seo_pages sp
    WHERE sp.page_type = p_page_type
      AND sp.status = 'published'
      AND sp.deleted_at IS NULL
      AND sp.canonical_url IS NOT NULL
    ORDER BY sp.view_count DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION generate_sitemap_urls IS '生成指定页面类型的 Sitemap URL 列表';

-- -----------------------------------------------------------
-- 索引
-- -----------------------------------------------------------

-- seo_pages 表索引
CREATE INDEX IF NOT EXISTS idx_seo_pages_page_type ON seo_pages(page_type);
CREATE INDEX IF NOT EXISTS idx_seo_pages_slug ON seo_pages(slug);
-- page_type + slug 唯一复合索引已通过约束创建
CREATE INDEX IF NOT EXISTS idx_seo_pages_status ON seo_pages(status);
CREATE INDEX IF NOT EXISTS idx_seo_pages_view_count ON seo_pages(view_count DESC);
CREATE INDEX IF NOT EXISTS idx_seo_pages_published_at ON seo_pages(published_at DESC);
CREATE INDEX IF NOT EXISTS idx_seo_pages_deleted_at ON seo_pages(deleted_at) WHERE deleted_at IS NOT NULL;
-- 已发布页面部分索引
CREATE INDEX IF NOT EXISTS idx_seo_pages_published
    ON seo_pages (page_type, updated_at DESC)
    WHERE status = 'published' AND deleted_at IS NULL;

-- sitemap_cache 表索引
CREATE INDEX IF NOT EXISTS idx_sitemap_cache_type ON sitemap_cache(sitemap_type);
CREATE INDEX IF NOT EXISTS idx_sitemap_cache_expires ON sitemap_cache(expires_at);

-- -----------------------------------------------------------
-- 记录迁移
-- -----------------------------------------------------------
INSERT INTO schema_migrations (filename) VALUES ('011_seo_system.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
