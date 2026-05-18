-- ============================================================
-- 012_recommendation.sql
-- 推荐系统支持：用户偏好、推荐缓存、标签共现矩阵
-- ============================================================
-- 说明：
--   - 创建用户偏好表（基于设备指纹）
--   - 创建视频推荐缓存表（预计算相似视频）
--   - 提供相似视频计算函数（基于标签重叠度）
--   - 提供个性化推荐函数（基于用户偏好）
--   - 创建标签共现物化视图（标签关联矩阵）
-- ============================================================

BEGIN;

-- -----------------------------------------------------------
-- 用户偏好表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_preferences (
    fingerprint_id          UUID PRIMARY KEY REFERENCES device_fingerprints(id) ON DELETE CASCADE,
    preferred_tags          JSONB DEFAULT '[]',               -- 偏好标签：[{tag_id, weight}]
    preferred_categories    JSONB DEFAULT '[]',               -- 偏好分类：[{category, weight}]
    watch_history_summary   JSONB DEFAULT '{}',               -- 观看历史摘要（用于冷启动）
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE user_preferences IS '用户偏好表：基于设备指纹记录用户的内容偏好';
COMMENT ON COLUMN user_preferences.fingerprint_id IS '设备指纹 ID（主键，一对一关系）';
COMMENT ON COLUMN user_preferences.preferred_tags IS '偏好标签 JSONB 数组，格式: [{"tag_id": "uuid", "weight": 0.85}, ...]';
COMMENT ON COLUMN user_preferences.preferred_categories IS '偏好分类 JSONB 数组，格式: [{"category": "短剧", "weight": 0.9}, ...]';
COMMENT ON COLUMN user_preferences.watch_history_summary IS '观看历史摘要 JSONB，用于冷启动推荐';

-- updated_at 触发器
CREATE TRIGGER trg_user_preferences_updated_at
    BEFORE UPDATE ON user_preferences
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- 视频推荐缓存表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS video_recommendations (
    video_id            UUID PRIMARY KEY REFERENCES videos(id) ON DELETE CASCADE,
    related_video_ids   UUID[] NOT NULL DEFAULT '{}',          -- 相似视频 ID 数组
    computed_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),    -- 计算时间
    expires_at          TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '24 hours'  -- 过期时间
);

COMMENT ON TABLE video_recommendations IS '视频推荐缓存表：预计算的相似视频列表';
COMMENT ON COLUMN video_recommendations.video_id IS '视频 ID（主键）';
COMMENT ON COLUMN video_recommendations.related_video_ids IS '相似视频 UUID 数组，按相似度降序排列';
COMMENT ON COLUMN video_recommendations.computed_at IS '计算时间';
COMMENT ON COLUMN video_recommendations.expires_at IS '过期时间（默认 24 小时）';

-- -----------------------------------------------------------
-- 触发器：插入设备指纹时自动创建用户偏好记录
-- -----------------------------------------------------------
CREATE OR REPLACE FUNCTION create_user_preference()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO user_preferences (fingerprint_id)
    VALUES (NEW.id)
    ON CONFLICT (fingerprint_id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION create_user_preference() IS '新设备注册时自动创建用户偏好记录';

CREATE TRIGGER trg_device_fingerprints_create_preference
    AFTER INSERT ON device_fingerprints
    FOR EACH ROW EXECUTE FUNCTION create_user_preference();

-- -----------------------------------------------------------
-- 函数：基于标签重叠度计算相似视频
-- -----------------------------------------------------------
CREATE OR REPLACE FUNCTION compute_similar_videos(
    p_video_id UUID,
    p_limit INTEGER DEFAULT 20
)
RETURNS UUID[] AS $$
DECLARE
    result UUID[];
BEGIN
    -- 基于标签重叠度（Jaccard 相似度简化版）查找相似视频
    -- 通过 video_tags 关联表计算标签交集
    SELECT ARRAY_AGG(DISTINCT vt2.video_id)
    INTO result
    FROM video_tags vt1
    JOIN video_tags vt2 ON vt1.tag_id = vt2.tag_id AND vt1.video_id != vt2.video_id
    JOIN videos v ON v.id = vt2.video_id
    WHERE vt1.video_id = p_video_id
      AND v.status = 'published'
      AND v.deleted_at IS NULL
    GROUP BY vt2.video_id
    ORDER BY COUNT(*) DESC, v.view_count DESC
    LIMIT p_limit;

    RETURN COALESCE(result, '{}');
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION compute_similar_videos IS '基于标签重叠度计算与指定视频相似的视频列表';

-- -----------------------------------------------------------
-- 函数：基于用户偏好推荐视频
-- -----------------------------------------------------------
CREATE OR REPLACE FUNCTION get_personalized_recommendations(
    p_fingerprint_id UUID,
    p_limit INTEGER DEFAULT 20
)
RETURNS TABLE (
    video_id UUID,
    score REAL
) AS $$
DECLARE
    v_preferred_tags JSONB;
    v_preferred_categories JSONB;
BEGIN
    -- 获取用户偏好
    SELECT preferred_tags, preferred_categories
    INTO v_preferred_tags, v_preferred_categories
    FROM user_preferences
    WHERE fingerprint_id = p_fingerprint_id;

    -- 如果没有偏好数据，返回热门视频
    IF v_preferred_tags = '[]'::JSONB OR v_preferred_tags IS NULL THEN
        RETURN QUERY
        SELECT v.id, (v.view_count / (SELECT MAX(view_count) FROM videos WHERE status = 'published' AND deleted_at IS NULL))::REAL AS score
        FROM videos v
        WHERE v.status = 'published'
          AND v.deleted_at IS NULL
        ORDER BY v.view_count DESC
        LIMIT p_limit;
        RETURN;
    END IF;

    -- 基于偏好标签推荐（标签匹配度 + 热度加权）
    RETURN QUERY
    SELECT
        v.id,
        (
            -- 标签匹配得分（权重 0.7）
            COALESCE(
                (SELECT SUM(pt.weight)
                 FROM jsonb_array_elements(v_preferred_tags) AS pt
                 WHERE EXISTS (
                     SELECT 1 FROM video_tags vt
                     WHERE vt.video_id = v.id AND vt.tag_id = (pt->>'tag_id')::UUID
                 )), 0
            ) * 0.7
            +
            -- 热度得分（权重 0.3）
            (v.view_count::REAL / NULLIF((SELECT MAX(view_count) FROM videos WHERE status = 'published' AND deleted_at IS NULL), 0)) * 0.3
        ) AS score
    FROM videos v
    WHERE v.status = 'published'
      AND v.deleted_at IS NULL
      AND EXISTS (
          SELECT 1 FROM video_tags vt
          JOIN jsonb_array_elements(v_preferred_tags) AS pt ON vt.tag_id = (pt->>'tag_id')::UUID
          WHERE vt.video_id = v.id
      )
    ORDER BY score DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_personalized_recommendations IS '基于用户偏好标签推荐视频（冷启动时返回热门视频）';

-- -----------------------------------------------------------
-- 物化视图：标签共现矩阵
-- -----------------------------------------------------------
-- 记录同时出现在同一视频的标签对及其共现频次
-- 用于推荐系统中 "喜欢这个标签的人也喜欢..." 的推荐逻辑
-- 使用 CTE 预计算标签计数，避免在关联强度计算中重复执行子查询
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_tag_correlation AS
WITH tag_counts AS (
    SELECT tag_id, COUNT(*) AS tag_count
    FROM video_tags
    GROUP BY tag_id
)
SELECT
    vt1.tag_id AS tag_a,
    vt2.tag_id AS tag_b,
    COUNT(*) AS co_occurrence_count,
    -- 关联强度（归一化）
    ROUND(
        COUNT(*)::DECIMAL / NULLIF(
            SQRT(tc1.tag_count::DECIMAL * tc2.tag_count::DECIMAL), 0
        ), 4
    ) AS correlation_strength
FROM video_tags vt1
JOIN video_tags vt2 ON vt1.video_id = vt2.video_id AND vt1.tag_id < vt2.tag_id
JOIN tag_counts tc1 ON tc1.tag_id = vt1.tag_id
JOIN tag_counts tc2 ON tc2.tag_id = vt2.tag_id
GROUP BY vt1.tag_id, vt2.tag_id, tc1.tag_count, tc2.tag_count
ORDER BY co_occurrence_count DESC;

COMMENT ON MATERIALIZED VIEW mv_tag_correlation IS '标签共现矩阵物化视图：记录同时出现在同一视频的标签对及其频次和关联强度';

-- 物化视图索引
CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_tag_correlation
    ON mv_tag_correlation(tag_a, tag_b);

CREATE INDEX IF NOT EXISTS idx_mv_tag_correlation_count
    ON mv_tag_correlation(co_occurrence_count DESC);

CREATE INDEX IF NOT EXISTS idx_mv_tag_correlation_strength
    ON mv_tag_correlation(correlation_strength DESC);

-- 刷新标签共现矩阵的函数
CREATE OR REPLACE FUNCTION refresh_tag_correlation()
RETURNS VOID AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_tag_correlation;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION refresh_tag_correlation() IS '刷新标签共现矩阵物化视图';

-- -----------------------------------------------------------
-- 索引
-- -----------------------------------------------------------

-- user_preferences 表索引（主键索引已通过 PK 创建）
-- preferred_tags JSONB 索引（支持 @> 包含查询）
CREATE INDEX IF NOT EXISTS idx_user_preferences_tags
    ON user_preferences USING GIN (preferred_tags);

-- video_recommendations 表索引
CREATE INDEX IF NOT EXISTS idx_video_recommendations_expires
    ON video_recommendations(expires_at)
    WHERE expires_at < NOW();

-- -----------------------------------------------------------
-- 记录迁移
-- -----------------------------------------------------------
INSERT INTO schema_migrations (filename) VALUES ('012_recommendation.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
