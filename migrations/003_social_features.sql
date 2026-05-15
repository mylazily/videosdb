-- ============================================================
-- 003_social_features.sql
-- 评论、弹幕、排行榜、观看历史、热搜
-- ============================================================

BEGIN;

-- -----------------------------------------------------------
-- 枚举类型
-- -----------------------------------------------------------
CREATE TYPE comment_status AS ENUM (
    'pending',      -- 待审核
    'approved',     -- 已通过
    'rejected',     -- 已拒绝
    'hidden'        -- 已隐藏
);

CREATE TYPE danmaku_type AS ENUM (
    'scroll',       -- 滚动弹幕
    'top',          -- 顶部弹幕
    'bottom',       -- 底部弹幕
    'color'         -- 彩色弹幕
);

CREATE TYPE rank_type AS ENUM (
    'hot',          -- 热播榜
    'score',        -- 评分榜
    'latest',       -- 最新榜
    'monthly'       -- 月榜
    'weekly'        -- 周榜
    'daily'         -- 日榜
    'rising'        -- 飙升榜
    'favorite'      -- 收藏榜
);

-- -----------------------------------------------------------
-- 评论表（支持嵌套回复）
-- -----------------------------------------------------------
CREATE TABLE comments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id        UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    parent_id       UUID REFERENCES comments(id) ON DELETE CASCADE,  -- 父评论ID（嵌套回复）
    root_id         UUID REFERENCES comments(id) ON DELETE CASCADE,  -- 根评论ID（快速定位顶级评论）
    content         TEXT NOT NULL,
    like_count      INTEGER NOT NULL DEFAULT 0,
    reply_count     INTEGER NOT NULL DEFAULT 0,                     -- 回复数量（冗余计数，提升查询性能）
    ip_location     VARCHAR(100) DEFAULT '',                        -- IP 归属地
    status          comment_status NOT NULL DEFAULT 'approved',
    deleted_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE comments IS '评论表（支持嵌套回复）';
COMMENT ON COLUMN comments.parent_id IS '父评论ID，顶级评论为 NULL';
COMMENT ON COLUMN comments.root_id IS '根评论ID，用于快速定位顶级评论';
COMMENT ON COLUMN comments.reply_count IS '回复数量（冗余计数）';

-- updated_at 触发器
CREATE TRIGGER trg_comments_updated_at
    BEFORE UPDATE ON comments
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- 评论点赞表
-- -----------------------------------------------------------
CREATE TABLE comment_likes (
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    comment_id      UUID NOT NULL REFERENCES comments(id) ON DELETE CASCADE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (user_id, comment_id)
);

COMMENT ON TABLE comment_likes IS '评论点赞表';

-- -----------------------------------------------------------
-- 弹幕表
-- -----------------------------------------------------------
CREATE TABLE danmakus (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id        UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    episode_id      UUID REFERENCES episodes(id) ON DELETE CASCADE,
    user_id         UUID REFERENCES users(id) ON DELETE SET NULL,
    content         VARCHAR(500) NOT NULL,
    time_pos        DECIMAL(8,3) NOT NULL,                       -- 弹幕出现时间（秒）
    type            danmaku_type NOT NULL DEFAULT 'scroll',
    color           VARCHAR(7) DEFAULT '#FFFFFF',                -- 颜色 HEX
    font_size       SMALLINT DEFAULT 25,
    status          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE danmakus IS '弹幕表';
COMMENT ON COLUMN danmakus.time_pos IS '弹幕出现时间（秒），精确到毫秒';
COMMENT ON COLUMN danmakus.type IS '弹幕类型：scroll/top/bottom/color';

-- -----------------------------------------------------------
-- 排行榜表
-- -----------------------------------------------------------
CREATE TABLE ranks (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id        UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    type            rank_type NOT NULL,
    score           DECIMAL(12,2) NOT NULL DEFAULT 0,            -- 排行分数
    period_date     DATE NOT NULL DEFAULT CURRENT_DATE,          -- 周期日期
    extra_info      JSONB DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (video_id, type, period_date)
);

COMMENT ON TABLE ranks IS '排行榜';
COMMENT ON COLUMN ranks.type IS '排行榜类型：hot/score/latest/monthly/weekly/daily/rising/favorite';
COMMENT ON COLUMN ranks.score IS '排行分数';
COMMENT ON COLUMN ranks.period_date IS '周期日期（用于日/周/月榜）';

CREATE TRIGGER trg_ranks_updated_at
    BEFORE UPDATE ON ranks
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- 用户观看历史表
-- -----------------------------------------------------------
CREATE TABLE user_watch_histories (
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    video_id        UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    episode_id      UUID REFERENCES episodes(id) ON DELETE SET NULL,
    progress        INTEGER NOT NULL DEFAULT 0,                  -- 观看进度（秒）
    duration        INTEGER NOT NULL DEFAULT 0,                  -- 总时长（秒）
    percentage      DECIMAL(5,2) DEFAULT 0,                      -- 观看百分比
    watch_count     INTEGER NOT NULL DEFAULT 1,                  -- 观看次数
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (user_id, video_id)
);

COMMENT ON TABLE user_watch_histories IS '用户观看历史表（UPSERT 更新）';
COMMENT ON COLUMN user_watch_histories.progress IS '观看进度（秒）';
COMMENT ON COLUMN user_watch_histories.percentage IS '观看百分比 0-100';

-- -----------------------------------------------------------
-- 热搜词表
-- -----------------------------------------------------------
CREATE TABLE search_hots (
    keyword         VARCHAR(200) PRIMARY KEY,
    count           INTEGER NOT NULL DEFAULT 0,
    category        VARCHAR(100) DEFAULT '',
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE search_hots IS '热搜词表';

-- updated_at 触发器
CREATE TRIGGER trg_search_hots_updated_at
    BEFORE UPDATE ON search_hots
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- 索引
-- -----------------------------------------------------------
-- 评论索引
CREATE INDEX idx_comments_video_id ON comments(video_id);
CREATE INDEX idx_comments_user_id ON comments(user_id);
CREATE INDEX idx_comments_parent_id ON comments(parent_id) WHERE parent_id IS NOT NULL;
CREATE INDEX idx_comments_root_id ON comments(root_id) WHERE root_id IS NOT NULL;
CREATE INDEX idx_comments_status ON comments(status);
CREATE INDEX idx_comments_created_at ON comments(created_at DESC);
CREATE INDEX idx_comments_like_count ON comments(like_count DESC);

-- 评论点赞索引
CREATE INDEX idx_comment_likes_comment_id ON comment_likes(comment_id);

-- 弹幕索引
CREATE INDEX idx_danmakus_video_id ON danmakus(video_id);
CREATE INDEX idx_danmakus_episode_id ON danmakus(episode_id) WHERE episode_id IS NOT NULL;
CREATE INDEX idx_danmakus_time_pos ON danmakus(video_id, episode_id, time_pos);

-- 排行榜索引
CREATE INDEX idx_ranks_type ON ranks(type, period_date);
CREATE INDEX idx_ranks_score ON ranks(type, period_date, score DESC);
CREATE INDEX idx_ranks_video_id ON ranks(video_id);

-- 观看历史索引
CREATE INDEX idx_watch_histories_user_id ON user_watch_histories(user_id);
CREATE INDEX idx_watch_histories_video_id ON user_watch_histories(video_id);
CREATE INDEX idx_watch_histories_updated_at ON user_watch_histories(updated_at DESC);

-- 热搜索引
CREATE INDEX idx_search_hots_count ON search_hots(count DESC);

-- -----------------------------------------------------------
-- 记录迁移
-- -----------------------------------------------------------
INSERT INTO schema_migrations (filename) VALUES ('003_social_features.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
