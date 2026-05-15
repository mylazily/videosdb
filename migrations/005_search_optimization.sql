-- ============================================================
-- 005_search_optimization.sql
-- 全文检索 + 索引优化
-- ============================================================

BEGIN;

-- -----------------------------------------------------------
-- 全文检索：为 videos 表创建 tsvector 更新触发器
-- -----------------------------------------------------------

-- 中文分词配置（使用 simple 分词器 + 自定义中文词库）
-- 如需更高级的中文分词，可安装 pg_jieba 或 zhparser 扩展
-- 这里使用 PostgreSQL 内置的 simple 分词器作为基础方案
CREATE TEXT SEARCH CONFIGURATION IF NOT EXISTS chinese_zh (COPY = simple);

COMMENT ON TEXT SEARCH CONFIGURATION chinese_zh IS '中文搜索配置（基于 simple 分词器）';

-- 创建 tsvector 自动更新触发器函数
CREATE OR REPLACE FUNCTION videos_search_vector_update()
RETURNS TRIGGER AS $$
BEGIN
    -- 合并 title、sub_title、description、director、actors、tags 为搜索向量
    NEW.search_vector :=
        setweight(to_tsvector('chinese_zh', COALESCE(NEW.title, '')), 'A') ||
        setweight(to_tsvector('chinese_zh', COALESCE(NEW.sub_title, '')), 'A') ||
        setweight(to_tsvector('chinese_zh', COALESCE(NEW.description, '')), 'B') ||
        setweight(to_tsvector('chinese_zh', COALESCE(NEW.director, '')), 'B') ||
        setweight(to_tsvector('chinese_zh', COALESCE(NEW.actors, '')), 'C') ||
        setweight(to_tsvector('chinese_zh', COALESCE(NEW.tags, '')), 'C') ||
        setweight(to_tsvector('chinese_zh', COALESCE(NEW.area, '')), 'D') ||
        setweight(to_tsvector('chinese_zh', COALESCE(NEW.category, '')), 'D');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION videos_search_vector_update() IS '视频全文检索向量自动更新触发器';

-- 创建触发器
DROP TRIGGER IF EXISTS trg_videos_search_vector ON videos;
CREATE TRIGGER trg_videos_search_vector
    BEFORE INSERT OR UPDATE ON videos
    FOR EACH ROW EXECUTE FUNCTION videos_search_vector_update();

-- -----------------------------------------------------------
-- 全文检索 GIN 索引
-- -----------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_videos_search_vector
    ON videos USING GIN (search_vector);

COMMENT ON INDEX idx_videos_search_vector IS '视频全文检索 GIN 索引';

-- -----------------------------------------------------------
-- 为现有数据填充 search_vector
-- -----------------------------------------------------------
UPDATE videos SET search_vector =
    setweight(to_tsvector('chinese_zh', COALESCE(title, '')), 'A') ||
    setweight(to_tsvector('chinese_zh', COALESCE(sub_title, '')), 'A') ||
    setweight(to_tsvector('chinese_zh', COALESCE(description, '')), 'B') ||
    setweight(to_tsvector('chinese_zh', COALESCE(director, '')), 'B') ||
    setweight(to_tsvector('chinese_zh', COALESCE(actors, '')), 'C') ||
    setweight(to_tsvector('chinese_zh', COALESCE(tags, '')), 'C') ||
    setweight(to_tsvector('chinese_zh', COALESCE(area, '')), 'D') ||
    setweight(to_tsvector('chinese_zh', COALESCE(category, '')), 'D')
WHERE search_vector IS NULL;

-- -----------------------------------------------------------
-- 标题 pg_trgm 模糊匹配索引
-- -----------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS idx_videos_title_trgm
    ON videos USING GIN (title gin_trgm_ops);

COMMENT ON INDEX idx_videos_title_trgm IS '视频标题模糊匹配 trigram 索引';

-- -----------------------------------------------------------
-- JSONB 索引（video_sources.play_links）
-- -----------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_video_sources_play_links
    ON video_sources USING GIN (play_links);

COMMENT ON INDEX idx_video_sources_play_links IS '播放线路 JSONB GIN 索引';

-- -----------------------------------------------------------
-- 复合索引优化
-- -----------------------------------------------------------

-- 视频列表查询：按分类 + 状态 + 更新时间
CREATE INDEX IF NOT EXISTS idx_videos_category_status_updated
    ON videos (category, status, updated_at DESC);

-- 视频列表查询：按分类 + 评分
CREATE INDEX IF NOT EXISTS idx_videos_category_score
    ON videos (category, score DESC NULLS LAST)
    WHERE status = 'published' AND deleted_at IS NULL;

-- 视频列表查询：按地区 + 年份
CREATE INDEX IF NOT EXISTS idx_videos_area_year
    ON videos (area, year DESC)
    WHERE status = 'published' AND deleted_at IS NULL;

-- 视频列表查询：按标签（GIN 索引）
CREATE INDEX IF NOT EXISTS idx_videos_tags
    ON videos USING GIN (to_tsvector('chinese_zh', COALESCE(tags, '')));

-- 剧集查询：按视频ID + 状态
CREATE INDEX IF NOT EXISTS idx_episodes_video_status
    ON episodes (video_id, status)
    WHERE deleted_at IS NULL;

-- 剧集播放源查询：按剧集ID + 排序
CREATE INDEX IF NOT EXISTS idx_episode_sources_episode_order
    ON episode_sources (episode_id, sort_order)
    WHERE status = TRUE;

-- 评论查询：按视频 + 状态 + 创建时间（分页）
CREATE INDEX IF NOT EXISTS idx_comments_video_status_created
    ON comments (video_id, status, created_at DESC)
    WHERE deleted_at IS NULL;

-- 评论查询：按根评论 + 创建时间（楼中楼分页）
CREATE INDEX IF NOT EXISTS idx_comments_root_created
    ON comments (root_id, created_at)
    WHERE root_id IS NOT NULL AND deleted_at IS NULL;

-- 采集日志查询：按采集源 + 时间
CREATE INDEX IF NOT EXISTS idx_collect_logs_source_started
    ON collect_logs (collect_source_id, started_at DESC);

-- 用户查询：按角色 + 状态
CREATE INDEX IF NOT EXISTS idx_users_role_status
    ON users (role, status)
    WHERE deleted_at IS NULL;

-- -----------------------------------------------------------
-- 部分索引（仅包含有效数据）
-- -----------------------------------------------------------

-- 已发布视频的部分索引
CREATE INDEX IF NOT EXISTS idx_videos_published
    ON videos (updated_at DESC)
    WHERE status = 'published' AND deleted_at IS NULL;

-- 高分视频部分索引
CREATE INDEX IF NOT EXISTS idx_videos_high_score
    ON videos (score DESC)
    WHERE status = 'published' AND score >= 7.0 AND deleted_at IS NULL;

-- 活跃用户部分索引
CREATE INDEX IF NOT EXISTS idx_users_active
    ON users (last_login_at DESC)
    WHERE status = 'active' AND deleted_at IS NULL;

-- -----------------------------------------------------------
-- 统计视图
-- -----------------------------------------------------------

-- 视频统计视图
CREATE OR REPLACE VIEW v_video_stats AS
SELECT
    v.id,
    v.title,
    v.category,
    v.status,
    v.view_count,
    v.score,
    v.comment_count,
    v.favorite_count,
    COALESCE(src.source_count, 0) AS source_count,
    COALESCE(ep.episode_count, 0) AS episode_count,
    COALESCE(ep.latest_episode, 0) AS latest_episode,
    v.updated_at
FROM videos v
LEFT JOIN (
    SELECT video_id, COUNT(*) AS source_count
    FROM video_sources
    WHERE status = TRUE
    GROUP BY video_id
) src ON src.video_id = v.id
LEFT JOIN (
    SELECT video_id, COUNT(*) AS episode_count, MAX(number) AS latest_episode
    FROM episodes
    WHERE deleted_at IS NULL
    GROUP BY video_id
) ep ON ep.video_id = v.id
WHERE v.deleted_at IS NULL;

COMMENT ON VIEW v_video_stats IS '视频统计视图（含播放源数、剧集数等聚合信息）';

-- 用户统计视图
CREATE OR REPLACE VIEW v_user_stats AS
SELECT
    u.id,
    u.username,
    u.nickname,
    u.role,
    u.status,
    u.login_count,
    COALESCE(fav.favorite_count, 0) AS favorite_count,
    COALESCE(cmt.comment_count, 0) AS comment_count,
    COALESCE(watch.watch_count, 0) AS watch_count,
    u.created_at
FROM users u
LEFT JOIN (
    SELECT user_id, COUNT(*) AS favorite_count
    FROM user_favorites
    GROUP BY user_id
) fav ON fav.user_id = u.id
LEFT JOIN (
    SELECT user_id, COUNT(*) AS comment_count
    FROM comments
    WHERE deleted_at IS NULL
    GROUP BY user_id
) cmt ON cmt.user_id = u.id
LEFT JOIN (
    SELECT user_id, COUNT(*) AS watch_count
    FROM user_watch_histories
    GROUP BY user_id
) watch ON watch.user_id = u.id
WHERE u.deleted_at IS NULL;

COMMENT ON VIEW v_user_stats IS '用户统计视图（含收藏数、评论数、观看数）';

-- -----------------------------------------------------------
-- 有用的数据库函数
-- -----------------------------------------------------------

-- 全文搜索函数
CREATE OR REPLACE FUNCTION search_videos(
    query_text TEXT,
    search_category VARCHAR DEFAULT NULL,
    search_area VARCHAR DEFAULT NULL,
    search_year SMALLINT DEFAULT NULL,
    limit_count INTEGER DEFAULT 20,
    offset_count INTEGER DEFAULT 0
)
RETURNS SETOF videos AS $$
BEGIN
    RETURN QUERY
    SELECT v.*
    FROM videos v,
         plainto_tsquery('chinese_zh', query_text) AS query
    WHERE v.search_vector @@ query
      AND v.status = 'published'
      AND v.deleted_at IS NULL
      AND (search_category IS NULL OR v.category = search_category)
      AND (search_area IS NULL OR v.area = search_area)
      AND (search_year IS NULL OR v.year = search_year)
    ORDER BY
        ts_rank_cd(v.search_vector, query) DESC,
        v.view_count DESC
    LIMIT limit_count
    OFFSET offset_count;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION search_videos IS '视频全文搜索函数，支持分类、地区、年份过滤';

-- 更新视频评分函数
CREATE OR REPLACE FUNCTION update_video_score(p_video_id UUID)
RETURNS VOID AS $$
BEGIN
    UPDATE videos SET
        comment_count = (
            SELECT COUNT(*) FROM comments
            WHERE video_id = p_video_id AND deleted_at IS NULL AND status = 'approved'
        ),
        favorite_count = (
            SELECT COUNT(*) FROM user_favorites
            WHERE video_id = p_video_id
        )
    WHERE id = p_video_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION update_video_score IS '更新视频统计计数（评论数、收藏数）';

-- 记录迁移
INSERT INTO schema_migrations (filename) VALUES ('005_search_optimization.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
