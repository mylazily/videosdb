-- ============================================================
-- 022_ad_reward.sql
-- 广告金币系统：广告任务、金币流水、每日任务记录
-- ============================================================
-- 说明：
--   - 创建广告任务配置表，定义可用的广告任务及奖励规则
--   - 创建金币流水记录表，记录每笔金币的收支明细
--   - 创建每日任务完成记录表，追踪用户每日任务完成情况
--   - 支持任务类型：watch_video/watch_ad/share_invite/daily_checkin
--   - 支持奖励类型：coin(金币)/time(时间)/vip_days(VIP天数)
--   - 关联 device_fingerprints 表，与现有虚拟币系统协同
-- ============================================================

BEGIN;

-- -----------------------------------------------------------
-- 广告任务配置表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS ad_tasks (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_name       VARCHAR(100) NOT NULL,                  -- 任务名称
    task_type       VARCHAR(30) NOT NULL,                   -- watch_video/watch_ad/share_invite/daily_checkin
    reward_coins    INT NOT NULL DEFAULT 0,                 -- 奖励金币数
    reward_type     VARCHAR(20) DEFAULT 'coin',             -- coin/time/vip_days
    reward_value    INT DEFAULT 0,                          -- 奖励数值（时间秒数/VIP天数）
    max_daily       INT DEFAULT 0,                          -- 每日最大次数（0=无限）
    duration_seconds INT DEFAULT 0,                         -- 需要的时长（看广告30秒等）
    is_active       BOOLEAN DEFAULT TRUE,
    sort_order      INT DEFAULT 0,                         -- 排序权重
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE ad_tasks IS '广告任务配置表：定义可用的广告任务及对应奖励规则';
COMMENT ON COLUMN ad_tasks.id IS 'UUID v4 主键';
COMMENT ON COLUMN ad_tasks.task_name IS '任务显示名称';
COMMENT ON COLUMN ad_tasks.task_type IS '任务类型：watch_video(看视频)/watch_ad(看广告)/share_invite(分享邀请)/daily_checkin(每日签到)';
COMMENT ON COLUMN ad_tasks.reward_coins IS '奖励金币数量';
COMMENT ON COLUMN ad_tasks.reward_type IS '奖励类型：coin(金币)/time(观看时间)/vip_days(VIP天数)';
COMMENT ON COLUMN ad_tasks.reward_value IS '奖励数值（当 reward_type 为 time 时为秒数，为 vip_days 时为天数）';
COMMENT ON COLUMN ad_tasks.max_daily IS '每日最大完成次数（0 表示不限制）';
COMMENT ON COLUMN ad_tasks.duration_seconds IS '任务需要持续时长（如看广告需 30 秒）';
COMMENT ON COLUMN ad_tasks.is_active IS '任务是否启用';
COMMENT ON COLUMN ad_tasks.sort_order IS '排序权重，数字越小越靠前';

-- updated_at 触发器
CREATE TRIGGER trg_ad_tasks_updated_at
    BEFORE UPDATE ON ad_tasks
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- 金币流水记录表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS coin_transactions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fingerprint_id      UUID NOT NULL REFERENCES device_fingerprints(id) ON DELETE CASCADE,
    amount              INT NOT NULL,                       -- 正数=收入，负数=支出
    balance_after       INT NOT NULL,                       -- 操作后余额
    transaction_type    VARCHAR(30) NOT NULL,               -- reward/ad_watch/share/vip_purchase/video_unlock
    reference_id        UUID,                               -- 关联的业务 ID
    description         VARCHAR(255),                       -- 交易描述
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE coin_transactions IS '金币流水记录表：记录每笔金币的收支明细';
COMMENT ON COLUMN coin_transactions.id IS 'UUID v4 主键';
COMMENT ON COLUMN coin_transactions.fingerprint_id IS '设备指纹 ID';
COMMENT ON COLUMN coin_transactions.amount IS '金币变动数量（正数=收入，负数=支出）';
COMMENT ON COLUMN coin_transactions.balance_after IS '操作后的金币余额';
COMMENT ON COLUMN coin_transactions.transaction_type IS '交易类型：reward(任务奖励)/ad_watch(看广告)/share(分享)/vip_purchase(VIP购买)/video_unlock(视频解锁)';
COMMENT ON COLUMN coin_transactions.reference_id IS '关联的业务 ID（如广告任务 ID、视频 ID 等）';
COMMENT ON COLUMN coin_transactions.description IS '交易描述（如"每日签到奖励"、"解锁视频《xxx》"）';

-- -----------------------------------------------------------
-- 每日任务完成记录表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS daily_task_completions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fingerprint_id      UUID NOT NULL REFERENCES device_fingerprints(id) ON DELETE CASCADE,
    task_id             UUID NOT NULL REFERENCES ad_tasks(id) ON DELETE CASCADE,
    completed_at        DATE NOT NULL DEFAULT CURRENT_DATE, -- 完成日期
    completion_count    INT DEFAULT 1,                      -- 当日完成次数
    reward_given        INT DEFAULT 0,                      -- 已发放奖励金币
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_daily_task_completions UNIQUE (fingerprint_id, task_id, completed_at)
);

COMMENT ON TABLE daily_task_completions IS '每日任务完成记录表：追踪用户每日广告任务的完成情况';
COMMENT ON COLUMN daily_task_completions.id IS 'UUID v4 主键';
COMMENT ON COLUMN daily_task_completions.fingerprint_id IS '设备指纹 ID';
COMMENT ON COLUMN daily_task_completions.task_id IS '广告任务 ID';
COMMENT ON COLUMN daily_task_completions.completed_at IS '完成日期';
COMMENT ON COLUMN daily_task_completions.completion_count IS '当日已完成次数';
COMMENT ON COLUMN daily_task_completions.reward_given IS '当日已发放的奖励金币总数';

-- -----------------------------------------------------------
-- 索引
-- -----------------------------------------------------------

-- coin_transactions 表索引
CREATE INDEX IF NOT EXISTS idx_coin_transactions_fingerprint ON coin_transactions(fingerprint_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_coin_transactions_type ON coin_transactions(transaction_type, created_at DESC);

-- daily_task_completions 表索引
CREATE INDEX IF NOT EXISTS idx_daily_tasks_fingerprint ON daily_task_completions(fingerprint_id, completed_at);

-- -----------------------------------------------------------
-- 记录迁移
-- -----------------------------------------------------------
INSERT INTO schema_migrations (filename) VALUES ('022_ad_reward.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
