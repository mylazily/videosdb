-- ============================================================
-- 008_tag_system.sql
-- 标签系统：标签管理、视频标签关联、层级分类
-- ============================================================
-- 说明：
--   - 创建标签表，支持二级层级分类（如 "短剧 > 穿越"）
--   - 创建视频-标签关联表
--   - 插入/删除关联时自动更新标签的冗余计数
--   - 预置 20+ 热门标签种子数据
-- ============================================================

BEGIN;

-- -----------------------------------------------------------
-- 枚举类型定义
-- -----------------------------------------------------------

-- 标签状态枚举
CREATE TYPE tag_status AS ENUM (
    'active',       -- 启用
    'hidden',       -- 隐藏
    'archived'      -- 归档
);

COMMENT ON TYPE tag_status IS '标签状态枚举';

-- -----------------------------------------------------------
-- 标签表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS tags (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(100) NOT NULL,                    -- 标签名称
    slug            VARCHAR(120) NOT NULL,                    -- URL 友好标识
    description     VARCHAR(500) DEFAULT '',                  -- 标签描述
    icon            VARCHAR(200) DEFAULT '',                  -- 图标 URL 或图标类名
    color           VARCHAR(20) DEFAULT '#6366f1',            -- 标签颜色（HEX）
    sort_order      INTEGER NOT NULL DEFAULT 0,               -- 排序权重，数字越小越靠前
    video_count     INTEGER NOT NULL DEFAULT 0,               -- 关联视频数（冗余计数）
    parent_id       UUID REFERENCES tags(id) ON DELETE SET NULL,  -- 父标签ID（支持二级分类）
    status          tag_status NOT NULL DEFAULT 'active',
    deleted_at      TIMESTAMPTZ,                              -- 软删除时间戳
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_tags_name UNIQUE (name),
    CONSTRAINT uq_tags_slug UNIQUE (slug)
);

COMMENT ON TABLE tags IS '标签表：管理视频分类标签，支持二级层级分类';
COMMENT ON COLUMN tags.id IS 'UUID v4 主键';
COMMENT ON COLUMN tags.name IS '标签名称，唯一';
COMMENT ON COLUMN tags.slug IS 'URL 友好标识（如 short-drama），唯一';
COMMENT ON COLUMN tags.description IS '标签描述';
COMMENT ON COLUMN tags.icon IS '图标 URL 或图标类名';
COMMENT ON COLUMN tags.color IS '标签颜色 HEX 值';
COMMENT ON COLUMN tags.sort_order IS '排序权重，数字越小越靠前';
COMMENT ON COLUMN tags.video_count IS '关联视频数（冗余计数，由触发器自动维护）';
COMMENT ON COLUMN tags.parent_id IS '父标签ID，NULL 表示顶级标签，支持二级分类如 "短剧 > 穿越"';
COMMENT ON COLUMN tags.status IS '状态：active/hidden/archived';
COMMENT ON COLUMN tags.deleted_at IS '软删除时间戳';

-- updated_at 触发器
CREATE TRIGGER trg_tags_updated_at
    BEFORE UPDATE ON tags
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- 视频-标签关联表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS video_tags (
    video_id        UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    tag_id          UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (video_id, tag_id)
);

COMMENT ON TABLE video_tags IS '视频-标签关联表：多对多关系';
COMMENT ON COLUMN video_tags.video_id IS '视频 ID';
COMMENT ON COLUMN video_tags.tag_id IS '标签 ID';
COMMENT ON COLUMN video_tags.created_at IS '关联创建时间';

-- -----------------------------------------------------------
-- 触发器：插入 video_tags 时自动更新 tags.video_count
-- -----------------------------------------------------------
CREATE OR REPLACE FUNCTION increment_tag_video_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE tags SET video_count = video_count + 1 WHERE id = NEW.tag_id;
    -- 如果有父标签，也更新父标签的计数
    IF EXISTS (SELECT 1 FROM tags WHERE id = NEW.tag_id AND parent_id IS NOT NULL) THEN
        UPDATE tags SET video_count = video_count + 1
        WHERE id = (SELECT parent_id FROM tags WHERE id = NEW.tag_id);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION increment_tag_video_count() IS '插入视频标签关联时自动递增标签的视频计数';

CREATE TRIGGER trg_video_tags_insert_count
    AFTER INSERT ON video_tags
    FOR EACH ROW EXECUTE FUNCTION increment_tag_video_count();

-- -----------------------------------------------------------
-- 触发器：删除 video_tags 时自动更新 tags.video_count
-- -----------------------------------------------------------
CREATE OR REPLACE FUNCTION decrement_tag_video_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE tags SET video_count = GREATEST(video_count - 1, 0) WHERE id = OLD.tag_id;
    -- 如果有父标签，也更新父标签的计数
    IF EXISTS (SELECT 1 FROM tags WHERE id = OLD.tag_id AND parent_id IS NOT NULL) THEN
        UPDATE tags SET video_count = GREATEST(video_count - 1, 0)
        WHERE id = (SELECT parent_id FROM tags WHERE id = OLD.tag_id);
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION decrement_tag_video_count() IS '删除视频标签关联时自动递减标签的视频计数';

CREATE TRIGGER trg_video_tags_delete_count
    AFTER DELETE ON video_tags
    FOR EACH ROW EXECUTE FUNCTION decrement_tag_video_count();

-- -----------------------------------------------------------
-- 索引
-- -----------------------------------------------------------

-- tags 表索引
CREATE INDEX IF NOT EXISTS idx_tags_name ON tags(name);
CREATE INDEX IF NOT EXISTS idx_tags_slug ON tags(slug);
CREATE INDEX IF NOT EXISTS idx_tags_video_count ON tags(video_count DESC);
CREATE INDEX IF NOT EXISTS idx_tags_parent_id ON tags(parent_id) WHERE parent_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tags_status ON tags(status);
CREATE INDEX IF NOT EXISTS idx_tags_sort_order ON tags(sort_order);
CREATE INDEX IF NOT EXISTS idx_tags_deleted_at ON tags(deleted_at) WHERE deleted_at IS NOT NULL;

-- video_tags 表索引
CREATE INDEX IF NOT EXISTS idx_video_tags_tag_id ON video_tags(tag_id);
CREATE INDEX IF NOT EXISTS idx_video_tags_video_id ON video_tags(video_id);
-- 标签查询索引：按标签查找视频
CREATE INDEX IF NOT EXISTS idx_video_tags_tag_created ON video_tags(tag_id, created_at DESC);

-- -----------------------------------------------------------
-- 种子数据：预置热门标签
-- -----------------------------------------------------------

-- 顶级标签
INSERT INTO tags (id, name, slug, description, icon, color, sort_order, status) VALUES
    ('t0000001-0000-0000-0000-000000000001', '短剧', 'short-drama', '热门短剧合集，每集几分钟精彩不断', '🎬', '#ef4444', 1, 'active'),
    ('t0000001-0000-0000-0000-000000000002', '国产', 'domestic', '国产影视作品', '🇨🇳', '#f97316', 2, 'active'),
    ('t0000001-0000-0000-0000-000000000003', '穿越', 'time-travel', '穿越题材影视作品', '⏰', '#eab308', 3, 'active'),
    ('t0000001-0000-0000-0000-000000000004', '限制级', 'restricted', '限制级内容，需要验证年龄', '🔞', '#dc2626', 4, 'active'),
    ('t0000001-0000-0000-0000-000000000005', '探花', 'exploration', '探花系列精选内容', '🌸', '#ec4899', 5, 'active'),
    ('t0000001-0000-0000-0000-000000000006', '动漫', 'anime', '日本及国产动漫', '🎌', '#8b5cf6', 6, 'active'),
    ('t0000001-0000-0000-0000-000000000007', '综艺', 'variety-show', '综艺真人秀节目', '🎤', '#06b6d4', 7, 'active'),
    ('t0000001-0000-0000-0000-000000000008', '欧美', 'western', '欧美影视作品', '🌍', '#3b82f6', 8, 'active'),
    ('t0000001-0000-0000-0000-000000000009', '韩国', 'korean', '韩国影视作品', '🇰🇷', '#a855f7', 9, 'active'),
    ('t0000001-0000-0000-0000-000000000010', '日本', 'japanese', '日本影视作品', '🇯🇵', '#f43f5e', 10, 'active'),
    ('t0000001-0000-0000-0000-000000000011', '科幻', 'sci-fi', '科幻题材影视作品', '🚀', '#0ea5e9', 11, 'active'),
    ('t0000001-0000-0000-0000-000000000012', '恐怖', 'horror', '恐怖惊悚题材', '👻', '#64748b', 12, 'active'),
    ('t0000001-0000-0000-0000-000000000013', '喜剧', 'comedy', '轻松搞笑的喜剧作品', '😂', '#fbbf24', 13, 'active'),
    ('t0000001-0000-0000-0000-000000000014', '动作', 'action', '动作冒险类影视作品', '💥', '#ef4444', 14, 'active'),
    ('t0000001-0000-0000-0000-000000000015', '爱情', 'romance', '浪漫爱情题材', '❤️', '#f472b6', 15, 'active'),
    ('t0000001-0000-0000-0000-000000000016', '悬疑', 'mystery', '悬疑推理题材', '🔍', '#6366f1', 16, 'active'),
    ('t0000001-0000-0000-0000-000000000017', '纪录片', 'documentary', '纪录片专题', '📹', '#78716c', 17, 'active'),
    ('t0000001-0000-0000-0000-000000000018', '古装', 'period-drama', '古装历史题材', '🏯', '#b45309', 18, 'active'),
    ('t0000001-0000-0000-0000-000000000019', '武侠', 'wuxia', '武侠江湖题材', '⚔️', '#92400e', 19, 'active'),
    ('t0000001-0000-0000-0000-000000000020', '奇幻', 'fantasy', '奇幻魔幻题材', '🧙', '#7c3aed', 20, 'active'),
    ('t0000001-0000-0000-0000-000000000021', '战争', 'war', '战争军事题材', '🎖️', '#374151', 21, 'active'),
    ('t0000001-0000-0000-0000-000000000022', '犯罪', 'crime', '犯罪警匪题材', '🔫', '#1f2937', 22, 'active')
ON CONFLICT (name) DO NOTHING;

-- 二级标签（短剧子分类）
INSERT INTO tags (id, name, slug, description, icon, color, sort_order, parent_id, status) VALUES
    ('t0000002-0000-0000-0000-000000000001', '穿越短剧', 'short-drama-time-travel', '穿越题材短剧', '⏰', '#eab308', 1, 't0000001-0000-0000-0000-000000000001', 'active'),
    ('t0000002-0000-0000-0000-000000000002', '甜宠短剧', 'short-drama-sweet', '甜宠恋爱短剧', '💕', '#f472b6', 2, 't0000001-0000-0000-0000-000000000001', 'active'),
    ('t0000002-0000-0000-0000-000000000003', '复仇短剧', 'short-drama-revenge', '复仇逆袭短剧', '🔥', '#ef4444', 3, 't0000001-0000-0000-0000-000000000001', 'active'),
    ('t0000002-0000-0000-0000-000000000004', '霸总短剧', 'short-drama-ceo', '霸道总裁题材短剧', '👔', '#3b82f6', 4, 't0000001-0000-0000-0000-000000000001', 'active'),
    ('t0000002-0000-0000-0000-000000000005', '古装短剧', 'short-drama-period', '古装穿越短剧', '🏯', '#b45309', 5, 't0000001-0000-0000-0000-000000000001', 'active')
ON CONFLICT (name) DO NOTHING;

-- 二级标签（动漫子分类）
INSERT INTO tags (id, name, slug, description, icon, color, sort_order, parent_id, status) VALUES
    ('t0000003-0000-0000-0000-000000000001', '热血动漫', 'anime-shounen', '热血战斗类动漫', '🔥', '#ef4444', 1, 't0000001-0000-0000-0000-000000000006', 'active'),
    ('t0000003-0000-0000-0000-000000000002', '恋爱动漫', 'anime-romance', '恋爱甜蜜类动漫', '💗', '#f472b6', 2, 't0000001-0000-0000-0000-000000000006', 'active'),
    ('t0000003-0000-0000-0000-000000000003', '日常动漫', 'anime-slice-of-life', '日常治愈类动漫', '☀️', '#fbbf24', 3, 't0000001-0000-0000-0000-000000000006', 'active'),
    ('t0000003-0000-0000-0000-000000000004', '国漫', 'chinese-anime', '国产动漫精选', '🐉', '#dc2626', 4, 't0000001-0000-0000-0000-000000000006', 'active')
ON CONFLICT (name) DO NOTHING;

-- -----------------------------------------------------------
-- 记录迁移
-- -----------------------------------------------------------
INSERT INTO schema_migrations (filename) VALUES ('008_tag_system.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
