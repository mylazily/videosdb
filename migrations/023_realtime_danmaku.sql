-- ============================================================
-- 023_realtime_danmaku.sql
-- WebSocket 实时弹幕：高性能弹幕存储、弹幕导入任务
-- ============================================================
-- 说明：
--   - 创建实时弹幕消息表，使用 BIGSERIAL 主键提升高并发写入性能
--   - 与现有 danmakus 表分离，专注 WebSocket 实时弹幕场景
--   - 支持弹幕类型：滚动(1)/顶部(2)/底部(3)
--   - 支持 VIP 弹幕（特殊样式展示）
--   - 支持弹幕来源：live(实时)/imported(导入)/preset(预设)
--   - 创建弹幕导入任务表，支持从 B站/P站 等平台批量导入
-- ============================================================

BEGIN;

-- -----------------------------------------------------------
-- 实时弹幕消息表（高性能写入）
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS danmaku_realtime (
    id              BIGSERIAL PRIMARY KEY,                  -- BIGINT 自增主键，提升写入性能
    video_id        UUID NOT NULL,                          -- 视频 ID
    episode_id      UUID,                                   -- 剧集 ID（可选）
    user_id         UUID,                                   -- 用户 ID（可选）
    fingerprint_id  UUID,                                   -- 设备指纹 ID（可选）
    content         TEXT NOT NULL,                          -- 弹幕内容
    time_pos        DECIMAL(6,2) NOT NULL DEFAULT 0,        -- 弹幕时间位置（秒）
    danmaku_type    SMALLINT NOT NULL DEFAULT 1,            -- 1滚动 2顶部 3底部
    color           VARCHAR(7) DEFAULT '#FFFFFF',           -- 弹幕颜色（HEX）
    is_premium      BOOLEAN DEFAULT FALSE,                  -- VIP 弹幕（特殊样式）
    source          VARCHAR(20) DEFAULT 'live',             -- live/imported/preset
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE danmaku_realtime IS '实时弹幕消息表：存储 WebSocket 实时弹幕，使用 BIGSERIAL 主键优化高并发写入';
COMMENT ON COLUMN danmaku_realtime.id IS 'BIGINT 自增主键（相比 UUID，自增 ID 在高并发写入场景下性能更优）';
COMMENT ON COLUMN danmaku_realtime.video_id IS '视频 ID';
COMMENT ON COLUMN danmaku_realtime.episode_id IS '剧集 ID（可选，用于分集弹幕）';
COMMENT ON COLUMN danmaku_realtime.user_id IS '用户 ID（可选，已注册用户）';
COMMENT ON COLUMN danmaku_realtime.fingerprint_id IS '设备指纹 ID（可选，匿名用户）';
COMMENT ON COLUMN danmaku_realtime.content IS '弹幕文本内容';
COMMENT ON COLUMN danmaku_realtime.time_pos IS '弹幕出现的时间位置（秒，精确到百分之一秒）';
COMMENT ON COLUMN danmaku_realtime.danmaku_type IS '弹幕类型：1(滚动弹幕)/2(顶部固定)/3(底部固定)';
COMMENT ON COLUMN danmaku_realtime.color IS '弹幕颜色（HEX 格式，如 #FFFFFF）';
COMMENT ON COLUMN danmaku_realtime.is_premium IS '是否为 VIP 弹幕（VIP 弹幕有特殊样式）';
COMMENT ON COLUMN danmaku_realtime.source IS '弹幕来源：live(实时发送)/imported(外部导入)/preset(预设弹幕)';

-- -----------------------------------------------------------
-- 弹幕导入任务表（从 B站/P站 等平台批量导入）
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS danmaku_import_tasks (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id            UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    source_platform     VARCHAR(30) NOT NULL,               -- bilibili/pornhub/etc
    source_video_id     VARCHAR(200),                       -- 源平台视频 ID
    total_imported      INT DEFAULT 0,                      -- 成功导入数量
    total_skipped       INT DEFAULT 0,                      -- 跳过数量
    status              VARCHAR(20) DEFAULT 'pending',      -- pending/running/completed/failed
    error_message       TEXT,                               -- 错误信息
    started_at          TIMESTAMPTZ,                        -- 开始时间
    finished_at         TIMESTAMPTZ,                        -- 完成时间
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE danmaku_import_tasks IS '弹幕导入任务表：管理从外部平台（B站/P站等）批量导入弹幕的任务';
COMMENT ON COLUMN danmaku_import_tasks.id IS 'UUID v4 主键';
COMMENT ON COLUMN danmaku_import_tasks.video_id IS '目标视频 ID';
COMMENT ON COLUMN danmaku_import_tasks.source_platform IS '来源平台：bilibili(B站)/pornhub(P站)/其他';
COMMENT ON COLUMN danmaku_import_tasks.source_video_id IS '源平台上的视频 ID（用于定位弹幕数据）';
COMMENT ON COLUMN danmaku_import_tasks.total_imported IS '成功导入的弹幕数量';
COMMENT ON COLUMN danmaku_import_tasks.total_skipped IS '跳过的弹幕数量（格式不兼容等）';
COMMENT ON COLUMN danmaku_import_tasks.status IS '任务状态：pending(待执行)/running(执行中)/completed(已完成)/failed(失败)';
COMMENT ON COLUMN danmaku_import_tasks.error_message IS '任务失败时的错误信息';
COMMENT ON COLUMN danmaku_import_tasks.started_at IS '任务开始执行时间';
COMMENT ON COLUMN danmaku_import_tasks.finished_at IS '任务完成时间';

-- -----------------------------------------------------------
-- 索引
-- -----------------------------------------------------------

-- danmaku_realtime 表索引
CREATE INDEX IF NOT EXISTS idx_danmaku_realtime_video_time ON danmaku_realtime(video_id, time_pos);
CREATE INDEX IF NOT EXISTS idx_danmaku_realtime_created ON danmaku_realtime(created_at DESC) WITH (fillfactor = 90);

-- danmaku_import_tasks 表索引
CREATE INDEX IF NOT EXISTS idx_danmaku_import_video ON danmaku_import_tasks(video_id);
CREATE INDEX IF NOT EXISTS idx_danmaku_import_status ON danmaku_import_tasks(status);

-- -----------------------------------------------------------
-- 记录迁移
-- -----------------------------------------------------------
INSERT INTO schema_migrations (filename) VALUES ('023_realtime_danmaku.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
