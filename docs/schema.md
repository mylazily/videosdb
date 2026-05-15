# 数据库设计文档

## 概述

本文档描述 xvideos 影视聚合系统的完整数据库设计，基于 PostgreSQL 18 构建。数据库包含 13 张核心表，覆盖影视数据管理、用户系统、社交功能和 MacCMS 采集源管理四大模块。

## 技术特性

- **主键策略**：所有核心表使用 `gen_random_uuid()` 生成 UUID v4 主键，关联表使用复合主键
- **时间戳**：所有表包含 `created_at`，核心表包含 `updated_at`（通过触发器自动更新）
- **软删除**：核心业务表支持 `deleted_at` 软删除字段
- **JSONB**：使用 JSONB 存储灵活的扩展信息和聚合播放线路
- **全文检索**：`videos` 表包含 `search_vector`（tsvector），通过 GIN 索引支持全文搜索
- **枚举类型**：使用 PostgreSQL 原生 ENUM 类型保证数据一致性

## ER 关系图

```
┌─────────────┐     ┌──────────────────┐     ┌──────────────────┐
│   videos    │────<│  video_sources   │     │  collect_sources │
│             │     │  (播放源)         │     │  (采集源)         │
└──────┬──────┘     └──────────────────┘     └────────┬─────────┘
       │                                              │
       │ 1:N                                          │ 1:N
       │                                              │
┌──────┴──────┐     ┌──────────────────┐     ┌───────┴──────────┐
│  episodes   │────<│ episode_sources  │     │  collect_logs    │
│  (剧集)     │     │  (剧集播放源)     │     │  (采集日志)       │
└─────────────┘     └──────────────────┘     └──────────────────┘

┌─────────────┐     ┌──────────────────┐     ┌──────────────────┐
│   users     │────<│   comments       │───<>│  comment_likes   │
│  (用户)     │     │   (评论)          │     │  (评论点赞)       │
└──────┬──────┘     └──────────────────┘     └──────────────────┘
       │
       │ 1:N
       │
┌──────┴──────────────┐     ┌──────────────────┐     ┌──────────────────┐
│ user_watch_histories │     │    danmakus      │     │  user_favorites  │
│  (观看历史)          │     │    (弹幕)         │     │  (收藏)           │
└─────────────────────┘     └──────────────────┘     └──────────────────┘

┌─────────────┐     ┌──────────────────┐
│   videos    │────<│     ranks        │
│             │     │   (排行榜)        │
└─────────────┘     └──────────────────┘

┌──────────────────┐
│  search_hots     │
│  (热搜词)         │
└──────────────────┘
```

## 表结构详细说明

### 1. videos — 视频主表

存储视频的基本信息、统计数据和全文检索向量。

| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID PK | 主键 |
| title | VARCHAR(500) | 视频标题 |
| sub_title | VARCHAR(500) | 副标题 |
| description | TEXT | 描述 |
| cover_url | VARCHAR(1024) | 横版封面 URL |
| cover_vertical | VARCHAR(1024) | 竖版封面 URL |
| category | VARCHAR(100) | 分类：电影/电视剧/动漫/综艺/纪录片 |
| tags | VARCHAR(500) | 标签，逗号分隔 |
| year | SMALLINT | 年份 |
| area | VARCHAR(100) | 地区 |
| language | VARCHAR(50) | 语言 |
| director | VARCHAR(500) | 导演 |
| actors | VARCHAR(2000) | 演员列表 |
| total_episodes | INTEGER | 总集数 |
| current_episode | INTEGER | 当前更新集数 |
| score | DECIMAL(3,1) | 评分 0-10 |
| score_count | INTEGER | 评分人数 |
| view_count | BIGINT | 总播放量 |
| daily_view_count | BIGINT | 日播放量 |
| weekly_view_count | BIGINT | 周播放量 |
| monthly_view_count | BIGINT | 月播放量 |
| like_count | INTEGER | 点赞数 |
| dislike_count | INTEGER | 踩数 |
| favorite_count | INTEGER | 收藏数 |
| comment_count | INTEGER | 评论数 |
| status | video_status ENUM | 状态 |
| source_from | VARCHAR(200) | 来源标识 |
| source_id | VARCHAR(200) | 来源原始 ID |
| extra_info | JSONB | 扩展信息 |
| search_vector | TSVECTOR | 全文检索向量 |
| published_at | TIMESTAMPTZ | 发布时间 |
| deleted_at | TIMESTAMPTZ | 软删除时间 |
| created_at | TIMESTAMPTZ | 创建时间 |
| updated_at | TIMESTAMPTZ | 更新时间（自动） |

**索引**：
- `idx_videos_category` — 分类查询
- `idx_videos_year` — 年份查询
- `idx_videos_area` — 地区查询
- `idx_videos_status` — 状态过滤
- `idx_videos_score` — 评分排序
- `idx_videos_view_count` — 播放量排序
- `idx_videos_daily_view` — 日播放量排序
- `idx_videos_created_at` — 最新排序
- `idx_videos_search_vector` — 全文检索 GIN 索引
- `idx_videos_title_trgm` — 标题模糊匹配 trigram 索引
- `idx_videos_category_status_updated` — 复合索引
- `idx_videos_published` — 已发布视频部分索引
- `idx_videos_high_score` — 高分视频部分索引

### 2. video_sources — 视频播放源表

存储视频的播放源信息，支持 JSONB 聚合多线路。

| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID PK | 主键 |
| video_id | UUID FK | 关联视频 |
| source_name | VARCHAR(200) | 来源名称 |
| play_url | VARCHAR(2048) | 单线路播放地址 |
| play_links | JSONB | 聚合多线路 |
| format | video_format ENUM | 格式：hls/mp4/flv/dash |
| sort_order | INTEGER | 排序 |
| status | BOOLEAN | 是否可用 |
| extra_info | JSONB | 扩展信息 |
| created_at | TIMESTAMPTZ | 创建时间 |
| updated_at | TIMESTAMPTZ | 更新时间 |

**play_links JSONB 结构**：
```json
[
    {"from": "量子资源", "url": "https://cdn.example.com/m3u8/movie/index.m3u8"},
    {"from": "红牛资源", "url": "https://cdn.example.com/m3u8/movie/index.m3u8"},
    {"from": "光速资源", "url": "https://cdn.example.com/m3u8/movie/index.m3u8"}
]
```

### 3. episodes — 剧集表

存储电视剧/动漫等分集内容。

| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID PK | 主键 |
| video_id | UUID FK | 关联视频 |
| title | VARCHAR(500) | 集标题 |
| number | INTEGER | 集数编号 |
| duration | INTEGER | 时长（秒） |
| status | episode_status ENUM | 状态 |
| source_from | VARCHAR(200) | 来源标识 |
| source_id | VARCHAR(200) | 来源原始 ID |
| extra_info | JSONB | 扩展信息 |
| deleted_at | TIMESTAMPTZ | 软删除时间 |
| created_at | TIMESTAMPTZ | 创建时间 |
| updated_at | TIMESTAMPTZ | 更新时间 |

**约束**：`UNIQUE (video_id, number)` — 同一视频的集数不重复。

### 4. episode_sources — 剧集播放源表

存储每集的播放源信息。

| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID PK | 主键 |
| episode_id | UUID FK | 关联剧集 |
| source_name | VARCHAR(200) | 来源名称 |
| play_url | VARCHAR(2048) | 播放地址 |
| format | video_format ENUM | 格式 |
| sort_order | INTEGER | 排序 |
| status | BOOLEAN | 是否可用 |
| extra_info | JSONB | 扩展信息 |
| created_at | TIMESTAMPTZ | 创建时间 |
| updated_at | TIMESTAMPTZ | 更新时间 |

### 5. users — 用户表

| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID PK | 主键 |
| username | VARCHAR(100) UNIQUE | 用户名 |
| password_hash | VARCHAR(255) | 密码哈希 |
| nickname | VARCHAR(100) | 昵称 |
| avatar_url | VARCHAR(1024) | 头像 URL |
| email | VARCHAR(255) | 邮箱 |
| phone | VARCHAR(50) | 手机号 |
| gender | SMALLINT | 性别：0未知/1男/2女 |
| birthday | DATE | 生日 |
| bio | VARCHAR(500) | 个人简介 |
| role | user_role ENUM | 角色：user/vip/admin/super_admin |
| status | user_status ENUM | 状态：active/disabled/banned |
| last_login_at | TIMESTAMPTZ | 最后登录时间 |
| last_login_ip | INET | 最后登录 IP |
| login_count | INTEGER | 登录次数 |
| extra_info | JSONB | 扩展信息 |
| deleted_at | TIMESTAMPTZ | 软删除时间 |
| created_at | TIMESTAMPTZ | 创建时间 |
| updated_at | TIMESTAMPTZ | 更新时间 |

### 6. comments — 评论表

支持嵌套回复的评论系统。

| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID PK | 主键 |
| video_id | UUID FK | 关联视频 |
| user_id | UUID FK | 关联用户 |
| parent_id | UUID FK | 父评论 ID（嵌套回复） |
| root_id | UUID FK | 根评论 ID（快速定位顶级评论） |
| content | TEXT | 评论内容 |
| like_count | INTEGER | 点赞数 |
| reply_count | INTEGER | 回复数（冗余计数） |
| ip_location | VARCHAR(100) | IP 归属地 |
| status | comment_status ENUM | 状态 |
| deleted_at | TIMESTAMPTZ | 软删除时间 |
| created_at | TIMESTAMPTZ | 创建时间 |
| updated_at | TIMESTAMPTZ | 更新时间 |

**嵌套评论设计**：
- `parent_id` 指向直接父评论，用于构建评论树
- `root_id` 指向顶级评论，用于快速查询某条评论下的所有回复
- `reply_count` 冗余存储回复数量，避免递归计数

### 7. comment_likes — 评论点赞表

| 字段 | 类型 | 说明 |
|------|------|------|
| user_id | UUID PK, FK | 用户 ID |
| comment_id | UUID PK, FK | 评论 ID |
| created_at | TIMESTAMPTZ | 创建时间 |

**约束**：`PRIMARY KEY (user_id, comment_id)` — 每个用户对每条评论只能点赞一次。

### 8. danmakus — 弹幕表

| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID PK | 主键 |
| video_id | UUID FK | 关联视频 |
| episode_id | UUID FK | 关联剧集（可选） |
| user_id | UUID FK | 关联用户（可选） |
| content | VARCHAR(500) | 弹幕内容 |
| time_pos | DECIMAL(8,3) | 出现时间（秒，精确到毫秒） |
| type | danmaku_type ENUM | 类型：scroll/top/bottom/color |
| color | VARCHAR(7) | 颜色 HEX |
| font_size | SMALLINT | 字号 |
| status | BOOLEAN | 是否显示 |
| created_at | TIMESTAMPTZ | 创建时间 |

### 9. ranks — 排行榜表

| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID PK | 主键 |
| video_id | UUID FK | 关联视频 |
| type | rank_type ENUM | 类型：hot/score/latest/monthly/weekly/daily/rising/favorite |
| score | DECIMAL(12,2) | 排行分数 |
| period_date | DATE | 周期日期 |
| extra_info | JSONB | 扩展信息 |
| created_at | TIMESTAMPTZ | 创建时间 |
| updated_at | TIMESTAMPTZ | 更新时间 |

**约束**：`UNIQUE (video_id, type, period_date)` — 每个视频在每个类型和周期中只有一条记录。

### 10. user_watch_histories — 观看历史表

| 字段 | 类型 | 说明 |
|------|------|------|
| user_id | UUID PK, FK | 用户 ID |
| video_id | UUID PK, FK | 视频 ID |
| episode_id | UUID FK | 剧集 ID（可选） |
| progress | INTEGER | 观看进度（秒） |
| duration | INTEGER | 总时长（秒） |
| percentage | DECIMAL(5,2) | 观看百分比 |
| watch_count | INTEGER | 观看次数 |
| updated_at | TIMESTAMPTZ | 更新时间 |

**设计说明**：使用 UPSERT 策略，每次观看时通过 `INSERT ... ON CONFLICT (user_id, video_id) DO UPDATE` 更新进度。

### 11. search_hots — 热搜词表

| 字段 | 类型 | 说明 |
|------|------|------|
| keyword | VARCHAR(200) PK | 热搜关键词 |
| count | INTEGER | 搜索次数 |
| category | VARCHAR(100) | 关联分类 |
| updated_at | TIMESTAMPTZ | 更新时间 |

### 12. collect_sources — 采集源表

| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID PK | 主键 |
| name | VARCHAR(200) UNIQUE | 采集源名称 |
| api_url | VARCHAR(2048) | API 地址 |
| source_type | collect_source_type ENUM | 类型：maccms/cms/api/rss/spider |
| category | collect_category ENUM | 分类 |
| api_key | VARCHAR(500) | API 密钥 |
| api_param | JSONB | API 请求参数 |
| headers | JSONB | 自定义请求头 |
| interval | INTEGER | 采集间隔（秒） |
| max_pages | INTEGER | 最大采集页数 |
| timeout | INTEGER | 请求超时（秒） |
| retry_count | INTEGER | 失败重试次数 |
| status | collect_status ENUM | 状态 |
| last_sync | TIMESTAMPTZ | 上次同步时间 |
| last_error | TEXT | 上次错误信息 |
| total_collected | INTEGER | 累计采集数 |
| total_new | INTEGER | 累计新增数 |
| extra_info | JSONB | 扩展信息 |
| deleted_at | TIMESTAMPTZ | 软删除时间 |
| created_at | TIMESTAMPTZ | 创建时间 |
| updated_at | TIMESTAMPTZ | 更新时间 |

### 13. collect_logs — 采集日志表

| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID PK | 主键 |
| collect_source_id | UUID FK | 关联采集源 |
| status | collect_status ENUM | 状态 |
| total_collected | INTEGER | 本次采集总数 |
| total_new | INTEGER | 本次新增数 |
| total_updated | INTEGER | 本次更新数 |
| total_failed | INTEGER | 本次失败数 |
| error_message | TEXT | 错误信息 |
| started_at | TIMESTAMPTZ | 开始时间 |
| finished_at | TIMESTAMPTZ | 结束时间 |
| duration_seconds | INTEGER | 耗时（秒） |
| extra_info | JSONB | 扩展信息 |
| created_at | TIMESTAMPTZ | 创建时间 |

## 辅助表

### user_oauth — 第三方登录表

| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID PK | 主键 |
| user_id | UUID FK | 关联用户 |
| provider | VARCHAR(50) | 提供商：github/google/wechat/apple |
| provider_id | VARCHAR(255) | 提供商用户 ID |
| access_token | VARCHAR(500) | 访问令牌 |
| refresh_token | VARCHAR(500) | 刷新令牌 |
| extra_info | JSONB | 扩展信息 |
| created_at | TIMESTAMPTZ | 创建时间 |
| updated_at | TIMESTAMPTZ | 更新时间 |

### user_favorites — 用户收藏表

| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID PK | 主键 |
| user_id | UUID FK | 关联用户 |
| video_id | UUID FK | 关联视频 |
| remark | VARCHAR(500) | 备注 |
| created_at | TIMESTAMPTZ | 创建时间 |

### collect_tasks — 采集任务队列表

| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID PK | 主键 |
| collect_source_id | UUID FK | 关联采集源 |
| task_type | VARCHAR(50) | 任务类型：full/incremental/single |
| target_url | VARCHAR(2048) | 单个采集目标 URL |
| priority | INTEGER | 优先级 |
| status | collect_status ENUM | 状态 |
| retry_count | INTEGER | 已重试次数 |
| max_retries | INTEGER | 最大重试次数 |
| scheduled_at | TIMESTAMPTZ | 计划执行时间 |
| started_at | TIMESTAMPTZ | 开始时间 |
| finished_at | TIMESTAMPTZ | 结束时间 |
| error_message | TEXT | 错误信息 |
| result_info | JSONB | 结果信息 |
| created_at | TIMESTAMPTZ | 创建时间 |
| updated_at | TIMESTAMPTZ | 更新时间 |

## 视图

### v_video_stats — 视频统计视图

聚合视频的播放源数、剧集数、最新集数等统计信息。

### v_user_stats — 用户统计视图

聚合用户的收藏数、评论数、观看数等统计信息。

## 函数

### videos_search_vector_update()

自动更新 `videos.search_vector` 的触发器函数，将 title、description、director、actors、tags 等字段合并为 tsvector，并设置不同的权重：
- A 级：title, sub_title
- B 级：description, director
- C 级：actors, tags
- D 级：area, category

### search_videos(query_text, category, area, year, limit, offset)

全文搜索函数，支持分类、地区、年份过滤，按相关度和播放量排序。

### update_video_score(video_id)

更新视频统计计数（评论数、收藏数）的维护函数。

## 迁移管理

迁移记录存储在 `schema_migrations` 表中：

| 字段 | 类型 | 说明 |
|------|------|------|
| id | SERIAL PK | 自增主键 |
| filename | VARCHAR(255) UNIQUE | 迁移文件名 |
| applied_at | TIMESTAMPTZ | 应用时间 |

迁移文件按文件名排序依次执行，已应用的迁移会被跳过。
