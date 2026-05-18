# videosdb

> xvideos 影视聚合系统 -- PostgreSQL 18 数据库仓库

## 项目简介

`videosdb` 是 xvideos 影视聚合系统的数据库层，基于 PostgreSQL 18 构建，提供完整的影视数据模型、MacCMS 采集源管理、用户系统及社交功能。采用 UUID 主键、JSONB 聚合播放线路、tsvector 全文检索等现代 PostgreSQL 特性，为影视聚合平台提供高性能、可扩展的数据存储方案。

## 技术栈

| 组件 | 版本 | 说明 |
|------|------|------|
| PostgreSQL | 18 | 主数据库，使用 JSONB、tsvector、UUID 等高级特性 |
| Redis | 7 | 缓存层，用于热搜排行、会话管理等 |
| Make | - | 常用数据库操作命令封装 |

## 核心特性

- **UUID 主键** -- 所有核心表使用 UUID v4 作为主键，分布式友好
- **JSONB 播放线路** -- 使用 JSONB 存储聚合多线路播放源，灵活扩展
- **全文检索** -- tsvector + GIN 索引，支持中文分词搜索
- **软删除** -- 所有核心表支持 `deleted_at` 软删除
- **自动时间戳** -- `created_at` / `updated_at` 自动维护
- **MacCMS 采集** -- 内置采集源管理与采集日志系统
- **社交功能** -- 评论嵌套回复、弹幕、点赞、观看历史
- **排行榜** -- 热播榜、评分榜、最新榜

## 快速开始

### 环境要求

- PostgreSQL 18
- Redis 7
- Make

### 安装与初始化

```bash
# 克隆项目
git clone <repo-url> && cd videosdb

# 安装 PostgreSQL 18 和 Redis
make install

# 启动服务
make start

# 初始化数据库（创建扩展 + 执行迁移）
make init

# 导入种子数据
make seed
```

### 常用命令

```bash
# 安装与启动
make install     # 安装 PostgreSQL 18 和 Redis
make start       # 启动 PostgreSQL 和 Redis 服务
make stop        # 停止 PostgreSQL 和 Redis 服务
make restart     # 重启 PostgreSQL 和 Redis 服务
make status      # 查看服务状态
make logs        # 查看 PostgreSQL 日志

# 数据库操作
make init        # 初始化数据库（创建扩展 + 执行所有迁移）
make migrate     # 执行未应用的迁移
make rollback N=1 # 回滚最近 N 个迁移
make seed        # 导入种子数据
make migration-status  # 查看迁移状态

# 备份与恢复
make backup      # 备份数据库到 backups/ 目录
make restore FILE=backups/xxx.sql.gz  # 从备份恢复数据库
make reset       # 重置数据库（删除并重建）

# 代码质量与测试
make lint        # 检查 SQL 语法
make test        # 运行测试查询
make clean       # 清理软删除数据（默认30天前的数据）

# 性能分析
make analyze     # 更新表统计信息
make vacuum      # 执行 VACUUM ANALYZE

# 开发工具
make shell       # 进入 psql 交互式终端
make redis-cli   # 进入 Redis CLI
make health      # 运行数据库健康检查

# 帮助
make help        # 显示所有可用命令
```

### 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `POSTGRES_USER` | `videos` | 数据库用户名 |
| `POSTGRES_PASSWORD` | `videos123` | 数据库密码 |
| `POSTGRES_DB` | `videosdb` | 数据库名 |
| `POSTGRES_PORT` | `5432` | 数据库端口 |
| `REDIS_PORT` | `6379` | Redis 端口 |

## 目录结构

```
videosdb/
├── README.md                    # 项目说明
├── .gitignore                   # Git 忽略规则
├── .editorconfig                # 编辑器配置
├── Makefile                     # 常用数据库操作命令
├── .github/
│   └── workflows/
│       └── deploy.yml           # CI/CD 配置
├── migrations/                  # 数据库迁移文件（按序号执行）
│   ├── 001_init_schema.sql      # 核心表结构（视频、剧集、播放源）
│   ├── 002_users_auth.sql       # 用户认证系统
│   ├── 003_social_features.sql  # 评论、弹幕、排行榜、观看历史
│   ├── 004_collect_system.sql   # MacCMS 采集源管理
│   ├── 005_search_optimization.sql # 全文检索 + 索引优化 + 实用函数
│   ├── 006_seed_data.sql        # 初始种子数据
│   ├── 007_performance_optimization.sql # 性能优化（分区表、并行查询）
│   ├── 008_tag_system.sql       # 标签系统
│   ├── 009_short_video.sql      # 短视频支持
│   ├── 010_fingerprint_auth.sql # 设备指纹认证
│   ├── 011_seo_system.sql       # SEO 优化
│   ├── 012_recommendation.sql   # 推荐系统
│   ├── 013_share_viral.sql      # 分享裂变
│   ├── 014_site_cluster.sql     # 站群管理
│   ├── 015_push_notification.sql # 推送通知
│   ├── 016_p2p_signaling.sql    # P2P 信令
│   ├── 017_redirect_rules.sql   # 重定向规则引擎
│   ├── 018_sitemap_auto_submit.sql # Sitemap 自动提交
│   ├── 019_tg_integration.sql   # Telegram 集成
│   ├── 020_x_social.sql         # X(Twitter) 社交集成
│   ├── 021_payment.sql          # 支付系统
│   ├── 022_ad_reward.sql        # 广告金币系统
│   ├── 023_realtime_danmaku.sql # 实时弹幕
│   ├── 024_domain_rotation.sql  # 域名轮询
│   ├── 025_trigger_fixes.sql    # 触发器修复
│   └── 026_cleanup_redundant_indexes.sql # 清理冗余索引 + 补充约束
├── scripts/                     # 运维脚本
│   ├── install-postgres.sh      # PostgreSQL 安装脚本
│   ├── init-native.sh           # 数据库初始化脚本
│   ├── migrate-native.sh        # 迁移执行脚本
│   ├── backup-native.sh         # 备份脚本
│   └── health_check.sql         # 数据库健康检查脚本
└── docs/
    └── schema.md                # 数据库设计文档
```

## 数据库设计概览

### ER 关系

```
videos 1──N video_sources        (视频 -> 播放源)
videos 1──N episodes             (视频 -> 剧集)
episodes 1──N episode_sources    (剧集 -> 剧集播放源)
users 1──N comments              (用户 -> 评论)
comments 1──N comments           (评论 -> 子评论/回复)
users N──N comment_likes         (用户 <-> 评论点赞)
users 1──N danmakus              (用户 -> 弹幕)
videos 1──N danmakus             (视频 -> 弹幕)
videos 1──N ranks                (视频 -> 排行榜)
users 1──N user_watch_histories  (用户 -> 观看历史)
videos 1──N user_watch_histories (视频 -> 观看历史)
collect_sources 1──N collect_logs (采集源 -> 采集日志)
```

### 核心表一览

| 表名 | 说明 | 主键 |
|------|------|------|
| `videos` | 视频主表 | UUID |
| `video_sources` | 视频播放源 | UUID |
| `episodes` | 剧集表 | UUID |
| `episode_sources` | 剧集播放源 | UUID |
| `users` | 用户表 | UUID |
| `comments` | 评论表 | UUID |
| `comment_likes` | 评论点赞 | 复合主键 |
| `danmakus` | 弹幕表 | UUID |
| `ranks` | 排行榜 | UUID |
| `user_watch_histories` | 观看历史 | 复合主键 |
| `search_hots` | 热搜词 | keyword |
| `collect_sources` | 采集源 | UUID |
| `collect_logs` | 采集日志 | UUID |

详细设计文档见 [docs/schema.md](docs/schema.md)。

## 性能优化建议

### 1. 索引优化

项目已内置多种索引优化策略：

- **B-Tree 索引**：用于等值查询和范围查询（如 `category`、`year`、`status`）
- **GIN 索引**：用于全文检索（`search_vector`）和 JSONB 查询（`play_links`）
- **部分索引**：仅索引有效数据，减少索引大小（如 `status = 'published'`）
- **复合索引**：优化多条件查询（如 `category + status + updated_at`）
- **覆盖索引**：支持 Index Only Scan，减少回表（如 `idx_videos_cover_basic`）

### 2. 查询优化

```sql
-- 使用全文检索进行高效搜索
SELECT * FROM search_videos('流浪地球', '电影', '大陆', 2026, 20, 0);

-- 使用模糊搜索进行相似匹配
SELECT * FROM fuzzy_search_videos('流浪地球', 0.3, 20);

-- 使用视图获取聚合统计
SELECT * FROM v_video_stats WHERE category = '电影';
```

### 3. 表分区（大表优化）

对于数据量大的表（如 `danmakus`、`comments`），建议使用分区表：

```sql
-- 按时间范围分区示例（在 007_performance_optimization.sql 中实现）
CREATE TABLE danmakus_2024 PARTITION OF danmakus_partitioned
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
```

### 4. 定期维护

```bash
# 更新统计信息
make analyze

# 清理死元组
make vacuum

# 清理软删除数据
make clean
```

## 监控查询示例

### 数据库连接监控

```sql
-- 查看当前连接数
SELECT count(*) FROM pg_stat_activity;

-- 查看活跃连接
SELECT pid, usename, application_name, client_addr, state, query_start, query
FROM pg_stat_activity
WHERE state = 'active';

-- 查看长时间运行的查询
SELECT pid, usename, query_start, query
FROM pg_stat_activity
WHERE state = 'active'
  AND query_start < NOW() - INTERVAL '5 minutes';
```

### 表大小监控

```sql
-- 查看表大小
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- 查看索引大小
SELECT
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY pg_relation_size(indexrelid) DESC;
```

### 查询性能监控

```sql
-- 查看慢查询（需要启用 pg_stat_statements 扩展）
SELECT query, calls, total_exec_time, mean_exec_time, rows
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;

-- 查看表扫描情况
SELECT
    schemaname,
    tablename,
    seq_scan,
    seq_tup_read,
    idx_scan,
    idx_tup_fetch
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY seq_scan DESC;
```

## 备份恢复详细说明

### 自动备份

```bash
# 执行备份（自动压缩）
make backup

# 备份文件存储在 backups/ 目录，格式：videosdb_YYYYMMDD_HHMMSS.sql.gz
```

### 手动备份

```bash
# 完整备份（包含数据 + 结构）
pg_dump -U videos -d videosdb > backup.sql

# 仅备份结构
pg_dump -U videos -d videosdb --schema-only > schema.sql

# 仅备份数据
pg_dump -U videos -d videosdb --data-only > data.sql

# 压缩备份
pg_dump -U videos -d videosdb | gzip > backup.sql.gz
```

### 恢复数据

```bash
# 使用 make 命令恢复
make restore FILE=backups/videosdb_20240115_120000.sql.gz

# 手动恢复（未压缩）
psql -U videos -d videosdb < backup.sql

# 手动恢复（压缩）
gunzip -c backup.sql.gz | psql -U videos -d videosdb
```

### 定时备份（Cron）

```bash
# 编辑 crontab
crontab -e

# 每天凌晨 2 点执行备份
0 2 * * * cd /path/to/videosdb && make backup

# 保留最近 7 天的备份
0 3 * * * find /path/to/videosdb/backups -name "*.sql.gz" -mtime +7 -delete
```

## 实用函数

### 搜索函数

```sql
-- 全文搜索
SELECT * FROM search_videos('流浪地球', '电影', '大陆', 2026, 20, 0);

-- 模糊搜索
SELECT * FROM fuzzy_search_videos('流浪地球', 0.3, 20);
```

### 播放链接函数

```sql
-- 获取视频播放链接
SELECT get_video_play_links('b0000000-0000-0000-0000-000000000001');

-- 获取剧集播放链接
SELECT get_episode_play_links('c0000001-0000-0000-0000-000000000001');
```

### 评论函数

```sql
-- 获取评论树
SELECT get_comment_tree('b0000000-0000-0000-0000-000000000001', 10, 0);
```

### 统计函数

```sql
-- 更新单个视频统计
SELECT update_video_score('b0000000-0000-0000-0000-000000000001');

-- 批量更新所有视频统计
SELECT batch_update_video_scores();

-- 清理软删除数据（仅限白名单表）
SELECT cleanup_soft_deleted('videos', 30);
```

## 健康检查

```bash
# 运行健康检查
make health
```

健康检查脚本会检查以下内容：
- 数据库连接状态
- 表空间使用情况
- 索引健康状况
- 长时间运行的查询
- 锁等待情况
- 复制延迟（如果使用主从）

## 迁移管理

### 创建新迁移

1. 在 `migrations/` 目录创建新文件，命名格式：`XXX_description.sql`
2. 文件开头添加事务：`BEGIN;`
3. 文件结尾添加迁移记录并提交：
   ```sql
   INSERT INTO schema_migrations (filename) VALUES ('XXX_description.sql')
       ON CONFLICT (filename) DO NOTHING;
   COMMIT;
   ```

### 迁移执行顺序

迁移按文件名排序执行，建议格式：`001_init_schema.sql`、`002_users_auth.sql` 等。

### 回滚迁移

```bash
# 回滚最近 1 个迁移
make rollback N=1

# 回滚最近 3 个迁移
make rollback N=3
```

**注意**：回滚需要手动编写对应的 down SQL 脚本。

## License

MIT
