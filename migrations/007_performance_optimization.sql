-- ============================================================
-- 007_performance_optimization.sql
-- 性能优化：分区表、并行查询优化、连接池配置
-- ============================================================
-- 说明：
--   - 为大表创建分区表（弹幕、评论、观看历史）
--   - 配置并行查询参数
--   - 创建物化视图用于报表
--   - 添加更多性能优化索引
-- ============================================================

BEGIN;

-- -----------------------------------------------------------
-- 分区表：弹幕表（按月份分区）
-- -----------------------------------------------------------

-- 创建分区表（如果原表为空，可以替换；否则需要迁移数据）
-- 注意：此操作仅在新部署时执行，已有数据需要手动迁移

-- 创建弹幕分区表（带分区键）
CREATE TABLE IF NOT EXISTS danmakus_partitioned (
    id              UUID DEFAULT gen_random_uuid(),
    video_id        UUID NOT NULL,
    episode_id      UUID,
    user_id         UUID,
    content         VARCHAR(500) NOT NULL,
    time_pos        DECIMAL(8,3) NOT NULL,
    type            danmaku_type NOT NULL DEFAULT 'scroll',
    color           VARCHAR(7) DEFAULT '#FFFFFF',
    font_size       SMALLINT DEFAULT 25,
    status          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_month   DATE NOT NULL DEFAULT DATE_TRUNC('month', NOW()),

    PRIMARY KEY (id, created_month)
) PARTITION BY RANGE (created_month);

COMMENT ON TABLE danmakus_partitioned IS '弹幕分区表（按月份分区）';

-- 创建分区（当前月份及前后各6个月）
DO $$
DECLARE
    start_date DATE;
    end_date DATE;
    partition_name TEXT;
BEGIN
    -- 创建前后6个月的分区
    FOR i IN -6..6 LOOP
        start_date := DATE_TRUNC('month', NOW() + (i || ' months')::INTERVAL);
        end_date := start_date + INTERVAL '1 month';
        partition_name := 'danmakus_' || TO_CHAR(start_date, 'YYYY_MM');

        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS %I PARTITION OF danmakus_partitioned
             FOR VALUES FROM (%L) TO (%L)',
            partition_name,
            start_date,
            end_date
        );
    END LOOP;
END $$;

-- 为分区表创建索引
CREATE INDEX IF NOT EXISTS idx_danmakus_part_video ON danmakus_partitioned(video_id);
CREATE INDEX IF NOT EXISTS idx_danmakus_part_time ON danmakus_partitioned(video_id, time_pos);
CREATE INDEX IF NOT EXISTS idx_danmakus_part_created ON danmakus_partitioned(created_at DESC);

-- -----------------------------------------------------------
-- 分区表：评论表（按月份分区）
-- -----------------------------------------------------------

CREATE TABLE IF NOT EXISTS comments_partitioned (
    id              UUID DEFAULT gen_random_uuid(),
    video_id        UUID NOT NULL,
    user_id         UUID NOT NULL,
    parent_id       UUID,
    root_id         UUID,
    content         TEXT NOT NULL,
    like_count      INTEGER NOT NULL DEFAULT 0,
    reply_count     INTEGER NOT NULL DEFAULT 0,
    ip_location     VARCHAR(100) DEFAULT '',
    status          comment_status NOT NULL DEFAULT 'approved',
    deleted_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_month   DATE NOT NULL DEFAULT DATE_TRUNC('month', NOW()),

    PRIMARY KEY (id, created_month)
) PARTITION BY RANGE (created_month);

COMMENT ON TABLE comments_partitioned IS '评论分区表（按月份分区）';

-- 创建评论表分区
DO $$
DECLARE
    start_date DATE;
    end_date DATE;
    partition_name TEXT;
BEGIN
    FOR i IN -6..6 LOOP
        start_date := DATE_TRUNC('month', NOW() + (i || ' months')::INTERVAL);
        end_date := start_date + INTERVAL '1 month';
        partition_name := 'comments_' || TO_CHAR(start_date, 'YYYY_MM');

        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS %I PARTITION OF comments_partitioned
             FOR VALUES FROM (%L) TO (%L)',
            partition_name,
            start_date,
            end_date
        );
    END LOOP;
END $$;

-- 为评论分区表创建索引
CREATE INDEX IF NOT EXISTS idx_comments_part_video ON comments_partitioned(video_id);
CREATE INDEX IF NOT EXISTS idx_comments_part_user ON comments_partitioned(user_id);
CREATE INDEX IF NOT EXISTS idx_comments_part_status ON comments_partitioned(status) WHERE deleted_at IS NULL;

-- -----------------------------------------------------------
-- 分区表：观看历史（按用户ID哈希分区）
-- -----------------------------------------------------------

CREATE TABLE IF NOT EXISTS user_watch_histories_partitioned (
    user_id         UUID NOT NULL,
    video_id        UUID NOT NULL,
    episode_id      UUID,
    progress        INTEGER NOT NULL DEFAULT 0,
    duration        INTEGER NOT NULL DEFAULT 0,
    percentage      DECIMAL(5,2) DEFAULT 0,
    watch_count     INTEGER NOT NULL DEFAULT 1,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (user_id, video_id)
) PARTITION BY HASH (user_id);

COMMENT ON TABLE user_watch_histories_partitioned IS '观看历史分区表（按用户ID哈希分区）';

-- 创建8个哈希分区
DO $$
DECLARE
    i INTEGER;
BEGIN
    FOR i IN 0..7 LOOP
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS user_watch_histories_p%s
             PARTITION OF user_watch_histories_partitioned
             FOR VALUES WITH (MODULUS 8, REMAINDER %s)',
            i, i
        );
    END LOOP;
END $$;

-- -----------------------------------------------------------
-- 物化视图：日报表（用于统计报表）
-- -----------------------------------------------------------

-- 视频日统计物化视图
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_video_daily_stats AS
SELECT
    DATE(v.created_at) AS stat_date,
    v.category,
    COUNT(*) AS video_count,
    SUM(v.view_count) AS total_views,
    AVG(v.score) AS avg_score,
    SUM(v.comment_count) AS total_comments,
    SUM(v.favorite_count) AS total_favorites
FROM videos v
WHERE v.deleted_at IS NULL
GROUP BY DATE(v.created_at), v.category
ORDER BY stat_date DESC, v.category;

COMMENT ON MATERIALIZED VIEW mv_video_daily_stats IS '视频日统计物化视图';

-- 创建物化视图索引
CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_video_daily_stats
    ON mv_video_daily_stats(stat_date, category);

-- 用户日统计物化视图
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_user_daily_stats AS
SELECT
    DATE(u.created_at) AS stat_date,
    u.role,
    COUNT(*) AS user_count,
    COUNT(*) FILTER (WHERE u.status = 'active') AS active_count
FROM users u
WHERE u.deleted_at IS NULL
GROUP BY DATE(u.created_at), u.role
ORDER BY stat_date DESC, u.role;

COMMENT ON MATERIALIZED VIEW mv_user_daily_stats IS '用户日统计物化视图';

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_user_daily_stats
    ON mv_user_daily_stats(stat_date, role);

-- -----------------------------------------------------------
-- 刷新物化视图的函数
-- -----------------------------------------------------------

CREATE OR REPLACE FUNCTION refresh_daily_stats()
RETURNS VOID AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_video_daily_stats;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_user_daily_stats;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION refresh_daily_stats() IS '刷新日统计物化视图';

-- -----------------------------------------------------------
-- 并行查询配置（会话级）
-- -----------------------------------------------------------

-- 设置并行查询参数
-- 注意：这些设置可以根据硬件配置调整

-- 启用并行查询
SET max_parallel_workers_per_gather = 4;

-- 设置并行工作进程数
SET max_parallel_workers = 8;

-- 设置并行维护工作进程数
SET max_parallel_maintenance_workers = 4;

-- -----------------------------------------------------------
-- 表级并行查询配置
-- -----------------------------------------------------------

-- 为大表设置并行度
ALTER TABLE videos SET (parallel_workers = 4);
ALTER TABLE danmakus SET (parallel_workers = 4);
ALTER TABLE comments SET (parallel_workers = 4);
ALTER TABLE user_watch_histories SET (parallel_workers = 4);

-- -----------------------------------------------------------
-- 高级索引优化
-- -----------------------------------------------------------

-- BRIN 索引（用于大表的时间范围查询）
-- 适用于按时间顺序插入的大表，如弹幕、评论
CREATE INDEX IF NOT EXISTS idx_danmakus_brin_created
    ON danmakus USING BRIN (created_at)
    WITH (pages_per_range = 128);

COMMENT ON INDEX idx_danmakus_brin_created IS '弹幕创建时间 BRIN 索引（适用于范围查询）';

CREATE INDEX IF NOT EXISTS idx_comments_brin_created
    ON comments USING BRIN (created_at)
    WITH (pages_per_range = 128);

COMMENT ON INDEX idx_comments_brin_created IS '评论创建时间 BRIN 索引（适用于范围查询）';

-- 表达式索引（用于常用查询条件）
CREATE INDEX IF NOT EXISTS idx_videos_year_range
    ON videos ((year / 10 * 10))
    WHERE year IS NOT NULL;

COMMENT ON INDEX idx_videos_year_range IS '视频年代范围索引（如 2020s）';

-- 函数索引（用于大小写不敏感搜索）
CREATE INDEX IF NOT EXISTS idx_videos_title_lower
    ON videos (LOWER(title));

COMMENT ON INDEX idx_videos_title_lower IS '视频标题小写索引（大小写不敏感搜索）';

-- 多列复合索引优化
CREATE INDEX IF NOT EXISTS idx_videos_category_area_year
    ON videos (category, area, year DESC)
    WHERE status = 'published' AND deleted_at IS NULL;

COMMENT ON INDEX idx_videos_category_area_year IS '视频分类+地区+年份复合索引';

-- 覆盖索引（Index Only Scan）
CREATE INDEX IF NOT EXISTS idx_videos_cover_basic
    ON videos (category, status, updated_at DESC)
    INCLUDE (title, cover_url, score, view_count)
    WHERE deleted_at IS NULL;

COMMENT ON INDEX idx_videos_cover_basic IS '视频基础信息覆盖索引（支持 Index Only Scan）';

-- -----------------------------------------------------------
-- 性能监控视图
-- -----------------------------------------------------------

-- 表访问统计视图
CREATE OR REPLACE VIEW v_table_access_stats AS
SELECT
    schemaname,
    relname AS table_name,
    seq_scan,
    seq_tup_read,
    idx_scan,
    idx_tup_fetch,
    n_tup_ins AS inserts,
    n_tup_upd AS updates,
    n_tup_del AS deletes,
    n_live_tup AS live_tuples,
    n_dead_tup AS dead_tuples,
    ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_tuple_ratio,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY seq_scan DESC;

COMMENT ON VIEW v_table_access_stats IS '表访问统计视图（用于性能分析）';

-- 索引使用统计视图
CREATE OR REPLACE VIEW v_index_usage_stats AS
SELECT
    schemaname,
    tablename AS table_name,
    indexrelname AS index_name,
    idx_scan AS index_scans,
    idx_tup_read AS tuples_read,
    idx_tup_fetch AS tuples_fetched,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan DESC;

COMMENT ON VIEW v_index_usage_stats IS '索引使用统计视图';

-- 慢查询统计视图（需要启用 pg_stat_statements）
CREATE OR REPLACE VIEW v_slow_queries AS
SELECT
    query,
    calls,
    ROUND(total_exec_time::NUMERIC, 2) AS total_time_ms,
    ROUND(mean_exec_time::NUMERIC, 2) AS avg_time_ms,
    ROUND(max_exec_time::NUMERIC, 2) AS max_time_ms,
    rows,
    ROUND(100.0 * shared_blks_hit / NULLIF(shared_blks_hit + shared_blks_read, 0), 2) AS cache_hit_ratio
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
ORDER BY mean_exec_time DESC
LIMIT 50;

COMMENT ON VIEW v_slow_queries IS '慢查询统计视图（需要启用 pg_stat_statements 扩展）';

-- -----------------------------------------------------------
-- 分区管理函数
-- -----------------------------------------------------------

-- 创建下个月分区的函数
CREATE OR REPLACE FUNCTION create_next_month_partition(table_name TEXT)
RETURNS TEXT AS $$
DECLARE
    next_month DATE;
    next_month_end DATE;
    partition_name TEXT;
    create_sql TEXT;
BEGIN
    next_month := DATE_TRUNC('month', NOW() + INTERVAL '1 month');
    next_month_end := next_month + INTERVAL '1 month';
    partition_name := table_name || '_' || TO_CHAR(next_month, 'YYYY_MM');

    create_sql := format(
        'CREATE TABLE IF NOT EXISTS %I PARTITION OF %I
         FOR VALUES FROM (%L) TO (%L)',
        partition_name,
        table_name,
        next_month,
        next_month_end
    );

    EXECUTE create_sql;

    RETURN partition_name;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION create_next_month_partition IS '创建下个月的分区表';

-- 删除旧分区的函数
CREATE OR REPLACE FUNCTION drop_old_partition(table_name TEXT, months_ago INTEGER)
RETURNS TEXT AS $$
DECLARE
    old_month DATE;
    partition_name TEXT;
    drop_sql TEXT;
BEGIN
    old_month := DATE_TRUNC('month', NOW() - (months_ago || ' months')::INTERVAL);
    partition_name := table_name || '_' || TO_CHAR(old_month, 'YYYY_MM');

    drop_sql := format('DROP TABLE IF EXISTS %I', partition_name);
    EXECUTE drop_sql;

    RETURN partition_name;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION drop_old_partition IS '删除指定月份前的分区表';

-- -----------------------------------------------------------
-- 自动分区维护任务
-- -----------------------------------------------------------

-- 创建分区维护函数
CREATE OR REPLACE FUNCTION maintain_partitions()
RETURNS TABLE(action TEXT, partition_name TEXT) AS $$
DECLARE
    partition_result TEXT;
BEGIN
    -- 为弹幕表创建下个月分区
    partition_result := create_next_month_partition('danmakus_partitioned');
    RETURN QUERY SELECT 'created'::TEXT, partition_result::TEXT;

    -- 为评论表创建下个月分区
    partition_result := create_next_month_partition('comments_partitioned');
    RETURN QUERY SELECT 'created'::TEXT, partition_result::TEXT;

    -- 删除6个月前的弹幕分区
    partition_result := drop_old_partition('danmakus_partitioned', 6);
    RETURN QUERY SELECT 'dropped'::TEXT, partition_result::TEXT;

    -- 删除6个月前的评论分区
    partition_result := drop_old_partition('comments_partitioned', 6);
    RETURN QUERY SELECT 'dropped'::TEXT, partition_result::TEXT;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION maintain_partitions() IS '自动维护分区表（创建新分区、删除旧分区）';

-- -----------------------------------------------------------
-- 记录迁移
-- -----------------------------------------------------------
INSERT INTO schema_migrations (filename) VALUES ('007_performance_optimization.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
