-- ============================================================
-- 005_search_optimization.sql
-- 全文检索 + 索引优化 + 实用函数
-- ============================================================
-- 说明：
--   - 创建全文检索配置和触发器
--   - 添加各种优化索引
--   - 创建实用的数据库函数
--   - 创建统计视图
-- ============================================================

BEGIN;

-- -----------------------------------------------------------
-- 扩展安装
-- -----------------------------------------------------------
-- pg_trgm: 用于模糊匹配和相似度搜索
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

COMMENT ON EXTENSION "pg_trgm" IS '提供 trigram 匹配功能，用于模糊搜索';

-- -----------------------------------------------------------
-- 全文检索配置
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
    -- 权重：A(1.0) > B(0.4) > C(0.2) > D(0.1)
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

COMMENT ON FUNCTION videos_search_vector_update() IS '视频全文检索向量自动更新触发器函数';

-- 创建触发器
DROP TRIGGER IF EXISTS trg_videos_search_vector ON videos;
CREATE TRIGGER trg_videos_search_vector
    BEFORE INSERT OR UPDATE OF title, sub_title, description, director, actors, tags, area, category
    ON videos
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
-- 注意：此索引被 007_performance_optimization.sql 中的 idx_videos_cover_basic 覆盖索引包含
-- 已在 026_cleanup_redundant_indexes.sql 中删除
-- CREATE INDEX IF NOT EXISTS idx_videos_category_status_updated
--     ON videos (category, status, updated_at DESC);

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

-- 新增：用户收藏复合索引
CREATE INDEX IF NOT EXISTS idx_user_favorites_user_video
    ON user_favorites (user_id, video_id);

-- 新增：观看历史复合索引
CREATE INDEX IF NOT EXISTS idx_watch_histories_user_updated
    ON user_watch_histories (user_id, updated_at DESC);

-- 新增：弹幕复合索引（按视频和时间）
CREATE INDEX IF NOT EXISTS idx_danmakus_video_time
    ON danmakus (video_id, time_pos);

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

-- 新增：近期热门视频部分索引（30天内）
CREATE INDEX IF NOT EXISTS idx_videos_recent_hot
    ON videos (daily_view_count DESC)
    WHERE status = 'published'
      AND deleted_at IS NULL
      AND published_at > NOW() - INTERVAL '30 days';

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

-- 新增：采集源统计视图
CREATE OR REPLACE VIEW v_collect_source_stats AS
SELECT
    cs.id,
    cs.name,
    cs.source_type,
    cs.status,
    cs.total_collected,
    cs.total_new,
    cs.last_sync,
    COALESCE(cl.recent_count, 0) AS recent_7d_logs,
    COALESCE(cl.success_rate, 0) AS recent_success_rate
FROM collect_sources cs
LEFT JOIN (
    SELECT
        collect_source_id,
        COUNT(*) AS recent_count,
        ROUND(100.0 * COUNT(*) FILTER (WHERE status = 'success') / NULLIF(COUNT(*), 0), 2) AS success_rate
    FROM collect_logs
    WHERE started_at > NOW() - INTERVAL '7 days'
    GROUP BY collect_source_id
) cl ON cl.collect_source_id = cs.id
WHERE cs.deleted_at IS NULL;

COMMENT ON VIEW v_collect_source_stats IS '采集源统计视图（含近期采集情况）';

-- 新增：系统概览视图
CREATE OR REPLACE VIEW v_system_overview AS
SELECT
    (SELECT COUNT(*) FROM videos WHERE deleted_at IS NULL) AS total_videos,
    (SELECT COUNT(*) FROM videos WHERE status = 'published' AND deleted_at IS NULL) AS published_videos,
    (SELECT COUNT(*) FROM users WHERE deleted_at IS NULL) AS total_users,
    (SELECT COUNT(*) FROM users WHERE status = 'active' AND deleted_at IS NULL) AS active_users,
    (SELECT COUNT(*) FROM comments WHERE deleted_at IS NULL) AS total_comments,
    (SELECT COUNT(*) FROM danmakus) AS total_danmakus,
    (SELECT COUNT(*) FROM collect_sources WHERE deleted_at IS NULL) AS total_collect_sources,
    (SELECT COUNT(*) FROM episodes WHERE deleted_at IS NULL) AS total_episodes;

COMMENT ON VIEW v_system_overview IS '系统概览视图（整体数据统计）';

-- -----------------------------------------------------------
-- 实用数据库函数
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
DECLARE
    query_tsquery TSQUERY;
BEGIN
    -- 转换查询文本为 tsquery
    query_tsquery := plainto_tsquery('chinese_zh', query_text);

    RETURN QUERY
    SELECT v.*
    FROM videos v
    WHERE v.search_vector @@ query_tsquery
      AND v.status = 'published'
      AND v.deleted_at IS NULL
      AND (search_category IS NULL OR v.category = search_category)
      AND (search_area IS NULL OR v.area = search_area)
      AND (search_year IS NULL OR v.year = search_year)
    ORDER BY
        ts_rank_cd(v.search_vector, query_tsquery) DESC,
        v.view_count DESC
    LIMIT limit_count
    OFFSET offset_count;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION search_videos IS '视频全文搜索函数，支持分类、地区、年份过滤';

-- 模糊搜索函数（基于 pg_trgm）
CREATE OR REPLACE FUNCTION fuzzy_search_videos(
    query_text TEXT,
    similarity_threshold REAL DEFAULT 0.3,
    limit_count INTEGER DEFAULT 20
)
RETURNS TABLE (
    id UUID,
    title VARCHAR,
    similarity REAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        v.id,
        v.title,
        similarity(v.title, query_text) AS similarity
    FROM videos v
    WHERE v.title % query_text
      AND similarity(v.title, query_text) >= similarity_threshold
      AND v.status = 'published'
      AND v.deleted_at IS NULL
    ORDER BY similarity DESC
    LIMIT limit_count;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION fuzzy_search_videos IS '视频标题模糊搜索函数，基于 trigram 相似度';

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

-- 新增：批量更新视频评分函数
-- 使用 FULL OUTER JOIN 确保所有视频都被更新（包括没有评论/收藏的视频）
CREATE OR REPLACE FUNCTION batch_update_video_scores()
RETURNS INTEGER AS $$
DECLARE
    updated_count INTEGER;
BEGIN
    WITH comment_counts AS (
        SELECT video_id, COUNT(*) AS count
        FROM comments
        WHERE deleted_at IS NULL AND status = 'approved'
        GROUP BY video_id
    ),
    favorite_counts AS (
        SELECT video_id, COUNT(*) AS count
        FROM user_favorites
        GROUP BY video_id
    ),
    updated AS (
        UPDATE videos v SET
            comment_count = COALESCE(cc.count, 0),
            favorite_count = COALESCE(fc.count, 0)
        FROM comment_counts cc
        FULL OUTER JOIN favorite_counts fc ON cc.video_id = fc.video_id
        WHERE v.id = COALESCE(cc.video_id, fc.video_id)
        RETURNING v.id
    )
    SELECT COUNT(*) INTO updated_count FROM updated;

    RETURN updated_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION batch_update_video_scores IS '批量更新所有视频的统计计数';

-- 新增：获取视频播放链接函数
CREATE OR REPLACE FUNCTION get_video_play_links(p_video_id UUID)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    SELECT jsonb_agg(
        jsonb_build_object(
            'source_name', vs.source_name,
            'play_links', vs.play_links,
            'format', vs.format
        ) ORDER BY vs.sort_order
    )
    INTO result
    FROM video_sources vs
    WHERE vs.video_id = p_video_id
      AND vs.status = TRUE;

    RETURN COALESCE(result, '[]'::JSONB);
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_video_play_links IS '获取视频的所有播放链接';

-- 新增：获取剧集播放链接函数
CREATE OR REPLACE FUNCTION get_episode_play_links(p_episode_id UUID)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    SELECT jsonb_agg(
        jsonb_build_object(
            'source_name', es.source_name,
            'play_url', es.play_url,
            'format', es.format
        ) ORDER BY es.sort_order
    )
    INTO result
    FROM episode_sources es
    WHERE es.episode_id = p_episode_id
      AND es.status = TRUE;

    RETURN COALESCE(result, '[]'::JSONB);
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_episode_play_links IS '获取剧集的所有播放链接';

-- 新增：获取视频评论树函数
CREATE OR REPLACE FUNCTION get_comment_tree(
    p_video_id UUID,
    p_limit INTEGER DEFAULT 10,
    p_offset INTEGER DEFAULT 0
)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    SELECT jsonb_agg(
        jsonb_build_object(
            'id', c.id,
            'user_id', c.user_id,
            'content', c.content,
            'like_count', c.like_count,
            'reply_count', c.reply_count,
            'created_at', c.created_at,
            'replies', COALESCE(
                (SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', r.id,
                        'user_id', r.user_id,
                        'content', r.content,
                        'like_count', r.like_count,
                        'created_at', r.created_at
                    ) ORDER BY r.created_at
                )
                FROM comments r
                WHERE r.root_id = c.id
                  AND r.parent_id IS NOT NULL
                  AND r.deleted_at IS NULL
                  AND r.status = 'approved'),
                '[]'::JSONB
            )
        ) ORDER BY c.created_at DESC
    )
    INTO result
    FROM comments c
    WHERE c.video_id = p_video_id
      AND c.parent_id IS NULL
      AND c.root_id IS NULL
      AND c.deleted_at IS NULL
      AND c.status = 'approved'
    LIMIT p_limit
    OFFSET p_offset;

    RETURN COALESCE(result, '[]'::JSONB);
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_comment_tree IS '获取视频的评论树（顶级评论及其回复）';

-- 新增：清理软删除数据函数
-- 安全限制：仅允许清理白名单中的表，防止 SQL 注入风险
CREATE OR REPLACE FUNCTION cleanup_soft_deleted(
    p_table_name TEXT,
    p_days INTEGER DEFAULT 30
)
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
    sql_query TEXT;
    allowed_tables TEXT[] := ARRAY[
        'videos', 'users', 'comments', 'danmakus', 'episodes',
        'video_sources', 'episode_sources', 'collect_logs',
        'user_watch_histories', 'share_links', 'redirect_rules',
        'payment_orders', 'vip_subscriptions', 'coin_transactions',
        'ad_tasks', 'daily_task_completions', 'danmaku_import_tasks'
    ];
BEGIN
    -- 白名单校验：防止任意表被删除
    IF NOT EXISTS (SELECT 1 FROM unnest(allowed_tables) AS t WHERE t = p_table_name) THEN
        RAISE EXCEPTION '表 "%" 不在清理白名单中，拒绝执行', p_table_name;
    END IF;

    -- 参数校验
    IF p_days < 1 THEN
        RAISE EXCEPTION '清理天数必须大于 0';
    END IF;

    sql_query := format(
        'DELETE FROM %I WHERE deleted_at < NOW() - INTERVAL ''%s days''',
        p_table_name,
        p_days
    );

    EXECUTE sql_query;

    GET DIAGNOSTICS deleted_count = ROW_COUNT;

    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION cleanup_soft_deleted IS '清理指定表的软删除数据（默认删除30天前的数据）';

-- -----------------------------------------------------------
-- 记录迁移
-- -----------------------------------------------------------
INSERT INTO schema_migrations (filename) VALUES ('005_search_optimization.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
