-- ============================================================
-- 002_users_auth.sql
-- 用户认证系统
-- ============================================================
-- 说明：
--   - 创建用户表及相关认证表
--   - 支持多角色权限管理
--   - 支持第三方 OAuth 登录
-- ============================================================

BEGIN;

-- -----------------------------------------------------------
-- 枚举类型定义
-- -----------------------------------------------------------

-- 用户角色枚举
CREATE TYPE user_role AS ENUM (
    'user',         -- 普通用户
    'vip',          -- VIP 用户
    'admin',        -- 管理员
    'super_admin'   -- 超级管理员
);

COMMENT ON TYPE user_role IS '用户角色枚举';

-- 用户状态枚举
CREATE TYPE user_status AS ENUM (
    'active',       -- 正常
    'disabled',     -- 禁用
    'banned'        -- 封禁
);

COMMENT ON TYPE user_status IS '用户状态枚举';

-- -----------------------------------------------------------
-- 用户表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username        VARCHAR(100) NOT NULL UNIQUE,
    password_hash   VARCHAR(255) NOT NULL,                 -- bcrypt/argon2 哈希
    nickname        VARCHAR(100) NOT NULL DEFAULT '',
    avatar_url      VARCHAR(1024) DEFAULT '',
    email           VARCHAR(255) DEFAULT '',
    phone           VARCHAR(50) DEFAULT '',
    gender          SMALLINT DEFAULT 0 CHECK (gender IN (0, 1, 2)),  -- 0:未知 1:男 2:女
    birthday        DATE,
    bio             VARCHAR(500) DEFAULT '',               -- 个人简介
    role            user_role NOT NULL DEFAULT 'user',
    status          user_status NOT NULL DEFAULT 'active',
    last_login_at   TIMESTAMPTZ,                           -- 最后登录时间
    last_login_ip   INET,                                  -- 最后登录 IP
    login_count     INTEGER DEFAULT 0,                     -- 登录次数
    extra_info      JSONB DEFAULT '{}',                    -- 扩展信息
    deleted_at      TIMESTAMPTZ,                           -- 软删除时间戳
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE users IS '用户表：存储系统用户信息';
COMMENT ON COLUMN users.id IS 'UUID v4 主键';
COMMENT ON COLUMN users.username IS '用户名，唯一';
COMMENT ON COLUMN users.password_hash IS '密码哈希（bcrypt/argon2）';
COMMENT ON COLUMN users.nickname IS '昵称';
COMMENT ON COLUMN users.avatar_url IS '头像 URL';
COMMENT ON COLUMN users.email IS '邮箱';
COMMENT ON COLUMN users.phone IS '手机号';
COMMENT ON COLUMN users.gender IS '性别：0未知 1男 2女';
COMMENT ON COLUMN users.birthday IS '生日';
COMMENT ON COLUMN users.bio IS '个人简介';
COMMENT ON COLUMN users.role IS '角色：user/vip/admin/super_admin';
COMMENT ON COLUMN users.status IS '状态：active/disabled/banned';
COMMENT ON COLUMN users.last_login_at IS '最后登录时间';
COMMENT ON COLUMN users.last_login_ip IS '最后登录 IP';
COMMENT ON COLUMN users.login_count IS '登录次数';
COMMENT ON COLUMN users.extra_info IS '扩展信息 JSONB';
COMMENT ON COLUMN users.deleted_at IS '软删除时间戳';

-- updated_at 触发器
CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- 用户第三方登录表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_oauth (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider        VARCHAR(50) NOT NULL,                  -- github/google/wechat/apple
    provider_id     VARCHAR(255) NOT NULL,                 -- 第三方平台用户ID
    access_token    VARCHAR(500),                          -- 访问令牌
    refresh_token   VARCHAR(500),                          -- 刷新令牌
    extra_info      JSONB DEFAULT '{}',                    -- 扩展信息
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (provider, provider_id)
);

COMMENT ON TABLE user_oauth IS '用户第三方登录表：存储 OAuth 绑定信息';
COMMENT ON COLUMN user_oauth.user_id IS '关联的用户 ID';
COMMENT ON COLUMN user_oauth.provider IS 'OAuth 提供商：github/google/wechat/apple';
COMMENT ON COLUMN user_oauth.provider_id IS '第三方平台用户唯一标识';
COMMENT ON COLUMN user_oauth.access_token IS '访问令牌';
COMMENT ON COLUMN user_oauth.refresh_token IS '刷新令牌';
COMMENT ON COLUMN user_oauth.extra_info IS '扩展信息 JSONB';

CREATE TRIGGER trg_user_oauth_updated_at
    BEFORE UPDATE ON user_oauth
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------
-- 用户收藏表
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_favorites (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    video_id        UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    remark          VARCHAR(500) DEFAULT '',               -- 收藏备注
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (user_id, video_id)
);

COMMENT ON TABLE user_favorites IS '用户收藏表：存储用户收藏的视频';
COMMENT ON COLUMN user_favorites.user_id IS '用户 ID';
COMMENT ON COLUMN user_favorites.video_id IS '视频 ID';
COMMENT ON COLUMN user_favorites.remark IS '收藏备注';
COMMENT ON COLUMN user_favorites.created_at IS '收藏时间';

-- -----------------------------------------------------------
-- 索引
-- -----------------------------------------------------------

-- users 表索引
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email) WHERE email IS NOT NULL AND email != '';
CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone) WHERE phone IS NOT NULL AND phone != '';
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
CREATE INDEX IF NOT EXISTS idx_users_status ON users(status);
CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_users_deleted_at ON users(deleted_at) WHERE deleted_at IS NOT NULL;

-- user_oauth 表索引
CREATE INDEX IF NOT EXISTS idx_user_oauth_user_id ON user_oauth(user_id);
CREATE INDEX IF NOT EXISTS idx_user_oauth_provider ON user_oauth(provider, provider_id);

-- user_favorites 表索引
CREATE INDEX IF NOT EXISTS idx_user_favorites_user_id ON user_favorites(user_id);
CREATE INDEX IF NOT EXISTS idx_user_favorites_video_id ON user_favorites(video_id);
CREATE INDEX IF NOT EXISTS idx_user_favorites_created_at ON user_favorites(created_at DESC);

-- -----------------------------------------------------------
-- 记录迁移
-- -----------------------------------------------------------
INSERT INTO schema_migrations (filename) VALUES ('002_users_auth.sql')
    ON CONFLICT (filename) DO NOTHING;

COMMIT;
