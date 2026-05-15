# videosdb

> xvideos 影视聚合系统 — PostgreSQL 18 数据库仓库

## 项目简介

`videosdb` 是 xvideos 影视聚合系统的数据库层，基于 PostgreSQL 18 构建，提供完整的影视数据模型、MacCMS 采集源管理、用户系统及社交功能。采用 UUID 主键、JSONB 聚合播放线路、tsvector 全文检索等现代 PostgreSQL 特性，为影视聚合平台提供高性能、可扩展的数据存储方案。

## 技术栈

| 组件 | 版本 | 说明 |
|------|------|------|
| PostgreSQL | 18 | 主数据库，使用 JSONB、tsvector、UUID 等高级特性 |
| Redis | 7 | 缓存层，用于热搜排行、会话管理等 |
| Docker | - | 容器化开发环境 |
| Make | - | 常用数据库操作命令封装 |

## 核心特性

- **UUID 主键** — 所有核心表使用 UUID v7 作为主键，分布式友好
- **JSONB 播放线路** — 使用 JSONB 存储聚合多线路播放源，灵活扩展
- **全文检索** — tsvector + GIN 索引，支持中文分词搜索
- **软删除** — 所有核心表支持 `deleted_at` 软删除
- **自动时间戳** — `created_at` / `updated_at` 自动维护
- **MacCMS 采集** — 内置采集源管理与采集日志系统
- **社交功能** — 评论嵌套回复、弹幕、点赞、观看历史
- **排行榜** — 热播榜、评分榜、最新榜

## 快速开始

### 环境要求

- Docker & Docker Compose
- Make

### 启动开发环境

```bash
# 克隆项目
git clone <repo-url> && cd videosdb

# 启动 PostgreSQL + Redis
make up

# 初始化数据库（创建扩展 + 执行迁移）
make init

# 导入种子数据
make seed
```

### 常用命令

```bash
make init          # 初始化数据库（创建扩展 + 执行所有迁移）
make migrate       # 执行未应用的迁移
make rollback N=1  # 回滚最近 N 个迁移（需手动执行对应 down SQL）
make seed          # 导入种子数据
make backup        # 备份数据库
make restore       # 恢复数据库
make reset         # 重置数据库（删除并重建）
make shell         # 进入 psql 交互式终端
make status        # 查看迁移状态
make down          # 停止容器
make logs          # 查看容器日志
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
├── Makefile                     # 常用数据库操作命令
├── docker-compose.yml           # PostgreSQL 18 + Redis 开发环境
├── migrations/                  # 数据库迁移文件（按序号执行）
│   ├── 001_init_schema.sql      # 核心表结构（视频、剧集、播放源）
│   ├── 002_users_auth.sql       # 用户认证系统
│   ├── 003_social_features.sql  # 评论、弹幕、排行榜、观看历史
│   ├── 004_collect_system.sql   # MacCMS 采集源管理
│   ├── 005_search_optimization.sql # 全文检索 + 索引优化
│   └── 006_seed_data.sql        # 初始种子数据
├── scripts/                     # 运维脚本
│   ├── init.sh                  # 初始化脚本
│   ├── migrate.sh               # 迁移执行脚本
│   └── backup.sh                # 备份脚本
└── docs/
    └── schema.md                # 数据库设计文档
```

## 数据库设计概览

### ER 关系

```
videos 1──N video_sources        (视频 → 播放源)
videos 1──N episodes             (视频 → 剧集)
episodes 1──N episode_sources    (剧集 → 剧集播放源)
users 1──N comments              (用户 → 评论)
comments 1──N comments           (评论 → 子评论/回复)
users N──N comment_likes         (用户 ↔ 评论点赞)
users 1──N danmakus              (用户 → 弹幕)
videos 1──N danmakus             (视频 → 弹幕)
videos 1──N ranks                (视频 → 排行榜)
users 1──N user_watch_histories  (用户 → 观看历史)
videos 1──N user_watch_histories (视频 → 观看历史)
collect_sources 1──N collect_logs (采集源 → 采集日志)
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

## License

MIT
