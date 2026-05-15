-- ============================================================
-- 002_users_auth.sql
-- 用户认证系统
-- ============================================================

BEGIN;

-- -----------------------------------------------------------
-- 枚举类型
-- -----------------------------------------------------------
CREATE TYPE user_role AS ENUM (
    'user',         -- 普通用户
    'vip',          -- VIP 用户
    'admin',        -- 管理员
    'super_admin'   -- 超级管理员
);

CREATE TYPE user_status AS ENUM (
    'active',       -- 正常
    'disabled',     -- 禁用
    'banned'        -- 封禁
);

-- -----------------------------------------------------------
-- 用户表
-- -----------------------------------------------------------
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username        VARCHAR(100) NOT NULL UNIQUE,
    password_hash   VARCHAR(255) NOT NULL,
    nickname        VARCHAR(100) NOT NULL DEFAULT '',
    avatar_url      VARCHAR(1024) DEFAULT '',
    email           VARCHAR(255) DEFAULT '',
    phone           VARCHAR(50) DEFAULT '',
    gender          SMALLINT DEFAULT 0 CHECK (gender IN (0, 1, 2)),  -- 0未知 1男 2女
    birthday        DATE,
    bio             VARCHAR(500) DEFAULT '',
    role            user_role NOT NULL DEFAULT 'user',
    status          user_status NOT NULL DEFAULT 'active',
    last_login_at   TIMESTAMPTZ,
    last_login_ip   INET,
    login_count     INTEGER DEFAULT 0,
    extra_info      JSONB DEFAULT '{}',
    deleted_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE users IS '用户表';
COMMENT ON COLUMN users.username IS '用户名，唯一';
COMMENT ON COLUMN users.password_hash IS '密码哈希（bcrypt/argon2）';
COMMENT ON COLUMN users.nickname IS '昵称';
COMMENT ON COLUMN users.role IS '角色：user/vip/admin/super_admin';
COMMENT ON COLUMN users.status IS '状态：active/disabled/banned';
COMMENT ON COLUMN users.last_login_ip IS '最后登录 IP';

-- updated_at 触发器
CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- 用户第三方登录表（可选扩展）
-- -----------------------------------------------------------
CREATE TABLE user_oauth (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider        VARCHAR(50) NOT NULL,                  -- github/google/wechat/apple
    provider_id     VARCHAR(255) NOT NULL,
    access_token    VARCHAR(500),
    refresh_token   VARCHAR(500),
    extra_info      JSONB DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (provider, provider_id)
);

COMMENT ON TABLE user_oauth IS '用户第三方登录表';

CREATE TRIGGER trg_user_oauth_updated_at
    BEFORE UPDATE ON user_oauth
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- 用户收藏表
-- -----------------------------------------------------------
CREATE TABLE user_favorites (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    video_id        UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    remark          VARCHAR(500) DEFAULT '',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (user_id, video_id)
);

COMMENT ON TABLE user_favorites IS '用户收藏表';

-- -----------------------------------------------------------
-- 索引
-- -----------------------------------------------------------
CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_email ON users(email) WHERE email IS NOT NULL AND email != '';
CREATE INDEX idx_users_phone ON users(phone) WHERE phone IS NOT NULL AND phone != '';
CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_status ON users(status);
CREATE INDEX idx_users_created_at ON users(created_at DESC);
CREATE INDEX idx_users_deleted_at ON users(deleted_at) WHERE deleted_at IS NOT NULL;

CREATE INDEX idx_user_oauth_user_id ON user_oauth(user_id);
CREATE INDEX idx_user_oauth_provider ON user_oauth(provider, provider_id);

CREATE INDEX idx_user_favorites_user_id ON user_favorites(user_id);
CREATE INDEX idx_user_favorites_video_id ON user_favorites(video_id);
CREATE INDEX idx_user_favorites_created_at ON user_favorites(created_at DESC);

-- -----------------------------------------------------------
-- 记录迁移
-- -----------------------------------------------------------
INSERT INTO schema_migrations (filename) VALUES ('002_users_auth.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
