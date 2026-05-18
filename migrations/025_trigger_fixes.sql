-- ============================================================
-- 025_trigger_fixes.sql
-- 触发器修复：补充缺失的 updated_at 触发器
-- ============================================================
-- 说明：
--   - 为缺失 updated_at 触发器的表添加触发器
--   - 为没有 updated_at 列的表添加该列
-- ============================================================

BEGIN;

-- -----------------------------------------------------------
-- 1. danmakus 表：添加 updated_at 列和触发器
-- -----------------------------------------------------------

-- 添加 updated_at 字段（如果不存在）
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'danmakus' AND column_name = 'updated_at'
    ) THEN
        ALTER TABLE danmakus ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
    END IF;
END $$;

COMMENT ON COLUMN danmakus.updated_at IS '更新时间';

-- 创建触发器函数（如果不存在）
CREATE OR REPLACE FUNCTION update_danmakus_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 删除旧触发器（如果存在）
DROP TRIGGER IF EXISTS trg_danmakus_updated_at ON danmakus;

-- 创建 updated_at 触发器
CREATE TRIGGER trg_danmakus_updated_at
    BEFORE UPDATE ON danmakus
    FOR EACH ROW EXECUTE FUNCTION update_danmakus_updated_at();

-- -----------------------------------------------------------
-- 2. user_watch_histories 表：添加 updated_at 触发器
-- -----------------------------------------------------------

-- 创建触发器函数（如果不存在）
CREATE OR REPLACE FUNCTION update_watch_history_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 删除旧触发器（如果存在）
DROP TRIGGER IF EXISTS trg_watch_histories_updated_at ON user_watch_histories;

-- 创建 updated_at 触发器
CREATE TRIGGER trg_watch_histories_updated_at
    BEFORE UPDATE ON user_watch_histories
    FOR EACH ROW EXECUTE FUNCTION update_watch_history_updated_at();

-- -----------------------------------------------------------
-- 3. video_tags 表：添加 updated_at 列和触发器
-- -----------------------------------------------------------

-- 添加 updated_at 字段（如果不存在）
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'video_tags' AND column_name = 'updated_at'
    ) THEN
        ALTER TABLE video_tags ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
    END IF;
END $$;

COMMENT ON COLUMN video_tags.updated_at IS '更新时间';

-- 创建触发器函数（如果不存在）
CREATE OR REPLACE FUNCTION update_video_tags_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 删除旧触发器（如果存在）
DROP TRIGGER IF EXISTS trg_video_tags_updated_at ON video_tags;

-- 创建 updated_at 触发器
CREATE TRIGGER trg_video_tags_updated_at
    BEFORE UPDATE ON video_tags
    FOR EACH ROW EXECUTE FUNCTION update_video_tags_updated_at();

-- -----------------------------------------------------------
-- 4. user_favorites 表：添加 updated_at 触发器
-- -----------------------------------------------------------

-- 检查 user_favorites 是否有 updated_at 列
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'user_favorites' AND column_name = 'updated_at'
    ) THEN
        ALTER TABLE user_favorites ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
    END IF;
END $$;

COMMENT ON COLUMN user_favorites.updated_at IS '更新时间';

-- 创建触发器函数（如果不存在）
CREATE OR REPLACE FUNCTION update_user_favorites_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 删除旧触发器（如果存在）
DROP TRIGGER IF EXISTS trg_user_favorites_updated_at ON user_favorites;

-- 创建 updated_at 触发器
CREATE TRIGGER trg_user_favorites_updated_at
    BEFORE UPDATE ON user_favorites
    FOR EACH ROW EXECUTE FUNCTION update_user_favorites_updated_at();

-- -----------------------------------------------------------
-- 5. collect_logs 表：添加 updated_at 列和触发器
-- -----------------------------------------------------------

-- 检查 collect_logs 是否有 updated_at 列
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'collect_logs' AND column_name = 'updated_at'
    ) THEN
        ALTER TABLE collect_logs ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
    END IF;
END $$;

COMMENT ON COLUMN collect_logs.updated_at IS '更新时间';

-- 创建触发器函数（如果不存在）
CREATE OR REPLACE FUNCTION update_collect_logs_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 删除旧触发器（如果存在）
DROP TRIGGER IF EXISTS trg_collect_logs_updated_at ON collect_logs;

-- 创建 updated_at 触发器
CREATE TRIGGER trg_collect_logs_updated_at
    BEFORE UPDATE ON collect_logs
    FOR EACH ROW EXECUTE FUNCTION update_collect_logs_updated_at();

-- -----------------------------------------------------------
-- 6. comment_likes 表：添加 updated_at 列和触发器
-- -----------------------------------------------------------

-- 检查 comment_likes 是否有 updated_at 列
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'comment_likes' AND column_name = 'updated_at'
    ) THEN
        ALTER TABLE comment_likes ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
    END IF;
END $$;

COMMENT ON COLUMN comment_likes.updated_at IS '更新时间';

-- 创建触发器函数（如果不存在）
CREATE OR REPLACE FUNCTION update_comment_likes_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 删除旧触发器（如果存在）
DROP TRIGGER IF EXISTS trg_comment_likes_updated_at ON comment_likes;

-- 创建 updated_at 触发器
CREATE TRIGGER trg_comment_likes_updated_at
    BEFORE UPDATE ON comment_likes
    FOR EACH ROW EXECUTE FUNCTION update_comment_likes_updated_at();

-- -----------------------------------------------------------
-- 记录迁移
-- -----------------------------------------------------------
INSERT INTO schema_migrations (filename) VALUES ('025_trigger_fixes.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
