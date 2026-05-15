-- ============================================================
-- health_check.sql
-- 数据库健康检查脚本
-- ============================================================
-- 说明：
--   - 检查数据库连接状态
--   - 检查表空间使用情况
--   - 检查索引健康状况
--   - 检查长时间运行的查询
--   - 检查锁等待情况
--   - 检查复制延迟（如果使用主从）
-- ============================================================

\echo '========================================'
\echo '      数据库健康检查报告'
\echo '========================================'
\echo ''

-- -----------------------------------------------------------
-- 1. 数据库基本信息
-- -----------------------------------------------------------
\echo '【1. 数据库基本信息】'
\echo '----------------------------------------'

SELECT
    current_database() AS database_name,
    version() AS postgres_version,
    current_user AS current_user,
    inet_server_addr() AS server_address,
    inet_server_port() AS server_port,
    pg_size_pretty(pg_database_size(current_database())) AS database_size;

\echo ''

-- -----------------------------------------------------------
-- 2. 连接状态检查
-- -----------------------------------------------------------
\echo '【2. 连接状态检查】'
\echo '----------------------------------------'

SELECT
    count(*) AS total_connections,
    count(*) FILTER (WHERE state = 'active') AS active_connections,
    count(*) FILTER (WHERE state = 'idle') AS idle_connections,
    count(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_transaction,
    count(*) FILTER (WHERE wait_event_type IS NOT NULL) AS waiting_connections
FROM pg_stat_activity
WHERE backend_type = 'client backend';

\echo ''

-- -----------------------------------------------------------
-- 3. 长时间运行的查询
-- -----------------------------------------------------------
\echo '【3. 长时间运行的查询（超过5分钟）】'
\echo '----------------------------------------'

SELECT
    pid,
    usename AS username,
    application_name,
    client_addr,
    state,
    EXTRACT(EPOCH FROM (NOW() - query_start))::INTEGER AS query_duration_seconds,
    LEFT(query, 100) AS query_preview
FROM pg_stat_activity
WHERE state = 'active'
  AND query_start < NOW() - INTERVAL '5 minutes'
  AND query NOT LIKE '%pg_stat_activity%'
ORDER BY query_start;

\echo ''

-- -----------------------------------------------------------
-- 4. 锁等待情况
-- -----------------------------------------------------------
\echo '【4. 锁等待情况】'
\echo '----------------------------------------'

SELECT
    blocked_locks.pid AS blocked_pid,
    blocked_activity.usename AS blocked_user,
    blocking_locks.pid AS blocking_pid,
    blocking_activity.usename AS blocking_user,
    blocked_activity.query AS blocked_query,
    blocking_activity.query AS blocking_query
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks
    ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.relation = blocked_locks.relation
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;

\echo ''

-- -----------------------------------------------------------
-- 5. 表空间使用情况
-- -----------------------------------------------------------
\echo '【5. 表空间使用情况】'
\echo '----------------------------------------'

SELECT
    spcname AS tablespace_name,
    pg_size_pretty(pg_tablespace_size(spcname)) AS size
FROM pg_tablespace
ORDER BY pg_tablespace_size(spcname) DESC;

\echo ''

-- -----------------------------------------------------------
-- 6. 表大小统计
-- -----------------------------------------------------------
\echo '【6. 表大小统计（Top 20）】'
\echo '----------------------------------------'

SELECT
    schemaname,
    tablename AS table_name,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
    pg_size_pretty(pg_indexes_size(schemaname||'.'||tablename)) AS indexes_size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 20;

\echo ''

-- -----------------------------------------------------------
-- 7. 索引大小统计
-- -----------------------------------------------------------
\echo '【7. 索引大小统计（Top 20）】'
\echo '----------------------------------------'

SELECT
    schemaname,
    tablename AS table_name,
    indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    idx_scan AS index_scans
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY pg_relation_size(indexrelid) DESC
LIMIT 20;

\echo ''

-- -----------------------------------------------------------
-- 8. 未使用的索引
-- -----------------------------------------------------------
\echo '【8. 未使用的索引（从未被扫描）】'
\echo '----------------------------------------'

SELECT
    schemaname,
    tablename AS table_name,
    indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
  AND idx_scan = 0
ORDER BY pg_relation_size(indexrelid) DESC;

\echo ''

-- -----------------------------------------------------------
-- 9. 表扫描统计（全表扫描过多）
-- -----------------------------------------------------------
\echo '【9. 全表扫描统计（Top 10）】'
\echo '----------------------------------------'

SELECT
    schemaname,
    relname AS table_name,
    seq_scan,
    seq_tup_read,
    idx_scan,
    idx_tup_fetch,
    n_live_tup AS live_tuples,
    CASE
        WHEN seq_scan > 0 THEN ROUND(100.0 * seq_scan / (seq_scan + COALESCE(idx_scan, 0)), 2)
        ELSE 0
    END AS seq_scan_ratio
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY seq_scan DESC
LIMIT 10;

\echo ''

-- -----------------------------------------------------------
-- 10. 死元组检查
-- -----------------------------------------------------------
\echo '【10. 死元组比例较高的表（超过10%）】'
\echo '----------------------------------------'

SELECT
    schemaname,
    relname AS table_name,
    n_live_tup AS live_tuples,
    n_dead_tup AS dead_tuples,
    ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_tuple_ratio,
    last_vacuum,
    last_autovacuum
FROM pg_stat_user_tables
WHERE schemaname = 'public'
  AND n_dead_tup > 1000
  AND (100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0)) > 10
ORDER BY dead_tuple_ratio DESC;

\echo ''

-- -----------------------------------------------------------
-- 11. 缓存命中率
-- -----------------------------------------------------------
\echo '【11. 缓存命中率】'
\echo '----------------------------------------'

SELECT
    ROUND(100.0 * sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0), 2) AS cache_hit_ratio,
    sum(heap_blks_hit) AS heap_blocks_hit,
    sum(heap_blks_read) AS heap_blocks_read
FROM pg_statio_user_tables;

\echo ''

-- -----------------------------------------------------------
-- 12. 索引缓存命中率
-- -----------------------------------------------------------
\echo '【12. 索引缓存命中率】'
\echo '----------------------------------------'

SELECT
    ROUND(100.0 * sum(idx_blks_hit) / NULLIF(sum(idx_blks_hit) + sum(idx_blks_read), 0), 2) AS index_cache_hit_ratio,
    sum(idx_blks_hit) AS index_blocks_hit,
    sum(idx_blks_read) AS index_blocks_read
FROM pg_statio_user_indexes;

\echo ''

-- -----------------------------------------------------------
-- 13. 复制延迟检查（如果使用主从）
-- -----------------------------------------------------------
\echo '【13. 复制延迟检查】'
\echo '----------------------------------------'

SELECT
    client_addr AS replica_address,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS replication_lag
FROM pg_stat_replication;

\echo ''

-- -----------------------------------------------------------
-- 14. 数据库对象统计
-- -----------------------------------------------------------
\echo '【14. 数据库对象统计】'
\echo '----------------------------------------'

SELECT
    (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public') AS table_count,
    (SELECT COUNT(*) FROM information_schema.views WHERE table_schema = 'public') AS view_count,
    (SELECT COUNT(*) FROM information_schema.routines WHERE routine_schema = 'public') AS function_count,
    (SELECT COUNT(*) FROM information_schema.triggers WHERE trigger_schema = 'public') AS trigger_count,
    (SELECT COUNT(*) FROM pg_indexes WHERE schemaname = 'public') AS index_count;

\echo ''

-- -----------------------------------------------------------
-- 15. 系统概览
-- -----------------------------------------------------------
\echo '【15. 系统概览】'
\echo '----------------------------------------'

SELECT * FROM v_system_overview;

\echo ''

-- -----------------------------------------------------------
-- 16. 健康检查总结
-- -----------------------------------------------------------
\echo '========================================'
\echo '      健康检查总结'
\echo '========================================'
\echo ''

DO $$
DECLARE
    dead_tables INTEGER;
    long_queries INTEGER;
    lock_waits INTEGER;
    unused_indexes INTEGER;
    high_dead_tuple_tables INTEGER;
BEGIN
    -- 检查死元组比例高的表
    SELECT COUNT(*) INTO high_dead_tuple_tables
    FROM pg_stat_user_tables
    WHERE schemaname = 'public'
      AND n_dead_tup > 1000
      AND (100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0)) > 20;

    -- 检查长时间运行的查询
    SELECT COUNT(*) INTO long_queries
    FROM pg_stat_activity
    WHERE state = 'active'
      AND query_start < NOW() - INTERVAL '5 minutes';

    -- 检查锁等待
    SELECT COUNT(*) INTO lock_waits
    FROM pg_catalog.pg_locks blocked_locks
    JOIN pg_catalog.pg_locks blocking_locks
        ON blocking_locks.locktype = blocked_locks.locktype
        AND blocking_locks.relation = blocked_locks.relation
        AND blocking_locks.pid != blocked_locks.pid
    WHERE NOT blocked_locks.granted;

    -- 检查未使用的索引
    SELECT COUNT(*) INTO unused_indexes
    FROM pg_stat_user_indexes
    WHERE schemaname = 'public'
      AND idx_scan = 0
      AND pg_relation_size(indexrelid) > 1000000;

    -- 输出总结
    RAISE NOTICE '检查结果：';
    RAISE NOTICE '- 长时间运行的查询: %', long_queries;
    RAISE NOTICE '- 锁等待: %', lock_waits;
    RAISE NOTICE '- 死元组比例高的表: %', high_dead_tuple_tables;
    RAISE NOTICE '- 未使用的大索引: %', unused_indexes;

    IF long_queries > 0 OR lock_waits > 0 OR high_dead_tuple_tables > 0 THEN
        RAISE NOTICE '';
        RAISE NOTICE '警告：发现潜在问题，请查看上述详细报告！';
    ELSE
        RAISE NOTICE '';
        RAISE NOTICE '状态：数据库健康状况良好！';
    END IF;
END $$;

\echo ''
\echo '健康检查完成！'
\echo '========================================'
