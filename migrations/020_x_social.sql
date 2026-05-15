-- ============================================================
-- 020_x_social.sql
-- X.com (Twitter) 联动：账号管理、发布记录、定时发布队列
-- ============================================================
-- 说明：
--   - 创建 X.com 账号配置表，管理多个 X 账号的 OAuth 凭证
--   - 创建 X.com 发布记录表，追踪推文发布状态和互动数据
--   - 创建 X.com 定时发布队列表，支持定时/排队发布
--   - 支持互动数据追踪：展示/点击/转发/点赞
--   - 支持发布状态：pending/posted/failed/deleted
--   - 支持域名追踪，记录每条推文使用的推广域名
-- ============================================================

BEGIN;

-- -----------------------------------------------------------
-- X.com 账号配置表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS x_accounts (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id          VARCHAR(50) NOT NULL,               -- X.com Account ID
    username            VARCHAR(100) NOT NULL,              -- X.com 用户名
    access_token        TEXT,                               -- OAuth Access Token（加密存储）
    access_token_secret TEXT,                               -- OAuth Access Token Secret（加密存储）
    is_active           BOOLEAN DEFAULT TRUE,
    follower_count      INT DEFAULT 0,                      -- 粉丝数
    last_post_at        TIMESTAMPTZ,                       -- 最后发布时间
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_x_accounts_account_id UNIQUE (account_id)
);

COMMENT ON TABLE x_accounts IS 'X.com 账号配置表：管理 Twitter/X 平台的账号和 OAuth 凭证';
COMMENT ON COLUMN x_accounts.id IS 'UUID v4 主键';
COMMENT ON COLUMN x_accounts.account_id IS 'X.com 账号 ID（唯一标识）';
COMMENT ON COLUMN x_accounts.username IS 'X.com 用户名（如 @my_channel）';
COMMENT ON COLUMN x_accounts.access_token IS 'OAuth Access Token（加密存储）';
COMMENT ON COLUMN x_accounts.access_token_secret IS 'OAuth Access Token Secret（加密存储）';
COMMENT ON COLUMN x_accounts.is_active IS '账号是否启用';
COMMENT ON COLUMN x_accounts.follower_count IS '粉丝数量（定期同步）';
COMMENT ON COLUMN x_accounts.last_post_at IS '最后一次发布推文时间';

-- updated_at 触发器
CREATE TRIGGER trg_x_accounts_updated_at
    BEFORE UPDATE ON x_accounts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- X.com 发布记录表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS x_post_logs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id          UUID NOT NULL REFERENCES x_accounts(id) ON DELETE CASCADE,
    video_id            UUID REFERENCES videos(id) ON DELETE SET NULL,
    tweet_id            VARCHAR(50),                        -- X.com Tweet ID
    tweet_text          TEXT NOT NULL,                      -- 推文内容
    media_urls          JSONB DEFAULT '[]',                 -- 媒体文件 URL 列表
    hashtags            JSONB DEFAULT '[]',                 -- 使用的标签列表
    link_url            VARCHAR(1024),                      -- 推广链接
    domain_used         VARCHAR(255),                       -- 使用的推广域名
    impression_count    INT DEFAULT 0,                      -- 展示次数
    click_count         INT DEFAULT 0,                      -- 点击次数
    retweet_count       INT DEFAULT 0,                      -- 转发次数
    like_count          INT DEFAULT 0,                      -- 点赞次数
    status              VARCHAR(20) DEFAULT 'pending',      -- pending/posted/failed/deleted
    error_message       TEXT,                               -- 失败原因
    posted_at           TIMESTAMPTZ,                        -- 实际发布时间
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE x_post_logs IS 'X.com 发布记录表：追踪推文发布状态和互动数据';
COMMENT ON COLUMN x_post_logs.id IS 'UUID v4 主键';
COMMENT ON COLUMN x_post_logs.account_id IS '发布账号 ID';
COMMENT ON COLUMN x_post_logs.video_id IS '关联的视频 ID（可选）';
COMMENT ON COLUMN x_post_logs.tweet_id IS 'X.com 服务端返回的 Tweet ID';
COMMENT ON COLUMN x_post_logs.tweet_text IS '推文正文内容';
COMMENT ON COLUMN x_post_logs.media_urls IS '媒体文件 URL 列表 JSONB（图片/视频）';
COMMENT ON COLUMN x_post_logs.hashtags IS '使用的标签列表 JSONB（如 ["#电影", "#推荐"]）';
COMMENT ON COLUMN x_post_logs.link_url IS '推广链接（视频详情页等）';
COMMENT ON COLUMN x_post_logs.domain_used IS '使用的推广域名（用于域名效果分析）';
COMMENT ON COLUMN x_post_logs.impression_count IS '展示次数（定期同步）';
COMMENT ON COLUMN x_post_logs.click_count IS '链接点击次数';
COMMENT ON COLUMN x_post_logs.retweet_count IS '转发次数';
COMMENT ON COLUMN x_post_logs.like_count IS '点赞次数';
COMMENT ON COLUMN x_post_logs.status IS '发布状态：pending(待发布)/posted(已发布)/failed(失败)/deleted(已删除)';
COMMENT ON COLUMN x_post_logs.error_message IS '发布失败时的错误信息';
COMMENT ON COLUMN x_post_logs.posted_at IS '实际发布时间';

-- -----------------------------------------------------------
-- X.com 定时发布队列表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS x_post_queue (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id      UUID NOT NULL REFERENCES x_accounts(id) ON DELETE CASCADE,
    video_id        UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    scheduled_at    TIMESTAMPTZ NOT NULL,                   -- 计划发布时间
    status          VARCHAR(20) DEFAULT 'pending',          -- pending/processing/completed/failed
    retry_count     INT DEFAULT 0,                          -- 已重试次数
    max_retries     INT DEFAULT 3,                          -- 最大重试次数
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE x_post_queue IS 'X.com 定时发布队列表：管理定时和排队发布的推文任务';
COMMENT ON COLUMN x_post_queue.id IS 'UUID v4 主键';
COMMENT ON COLUMN x_post_queue.account_id IS '发布账号 ID';
COMMENT ON COLUMN x_post_queue.video_id IS '关联的视频 ID';
COMMENT ON COLUMN x_post_queue.scheduled_at IS '计划发布时间';
COMMENT ON COLUMN x_post_queue.status IS '任务状态：pending(待执行)/processing(执行中)/completed(已完成)/failed(失败)';
COMMENT ON COLUMN x_post_queue.retry_count IS '已重试次数';
COMMENT ON COLUMN x_post_queue.max_retries IS '最大重试次数（默认 3 次）';

-- -----------------------------------------------------------
-- 索引
-- -----------------------------------------------------------

-- x_post_logs 表索引
CREATE INDEX IF NOT EXISTS idx_x_posts_account ON x_post_logs(account_id, posted_at DESC);
CREATE INDEX IF NOT EXISTS idx_x_posts_video ON x_post_logs(video_id);

-- x_post_queue 表索引
CREATE INDEX IF NOT EXISTS idx_x_queue_scheduled ON x_post_queue(scheduled_at, status) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_x_queue_status ON x_post_queue(status);

-- -----------------------------------------------------------
-- 记录迁移
-- -----------------------------------------------------------
INSERT INTO schema_migrations (filename) VALUES ('020_x_social.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
