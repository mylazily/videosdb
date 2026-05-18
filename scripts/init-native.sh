#!/usr/bin/env bash
# ============================================================
# init-native.sh — 数据库初始化脚本（非 Docker 版本）
# ============================================================

set -euo pipefail

# 加载环境变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$PROJECT_DIR/.env" ]; then
    source "$PROJECT_DIR/.env"
fi

# 默认值
POSTGRES_USER="${POSTGRES_USER:-videos}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-videos123}"
POSTGRES_DB="${POSTGRES_DB:-videosdb}"
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
PG_VERSION="${PG_VERSION:-18}"

echo "==> 初始化数据库..."
echo "    主机: $POSTGRES_HOST:$POSTGRES_PORT"
echo "    数据库: $POSTGRES_DB"
echo "    用户: $POSTGRES_USER"

# 等待 PostgreSQL 就绪
echo "==> 等待 PostgreSQL 就绪..."
MAX_RETRIES=30
RETRY_COUNT=0

until pg_isready -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" > /dev/null 2>&1; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "错误: PostgreSQL 在 ${MAX_RETRIES} 秒后仍未就绪"
        echo "请确保 PostgreSQL 服务已启动:"
        echo "  sudo systemctl start postgresql@${PG_VERSION}-main"
        exit 1
    fi
    sleep 1
done

echo "==> PostgreSQL 已就绪"

# 检查数据库是否存在，不存在则创建
echo "==> 检查数据库..."
if ! sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$POSTGRES_DB"; then
    echo "==> 创建数据库 $POSTGRES_DB..."
    sudo -u postgres psql -c "CREATE DATABASE $POSTGRES_DB OWNER $POSTGRES_USER ENCODING 'UTF8' LC_COLLATE 'C' LC_CTYPE 'C' TEMPLATE template0;"
fi

# 创建扩展
echo "==> 创建扩展..."
export PGPASSWORD="$POSTGRES_PASSWORD"
psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;" 2>/dev/null || true

# 执行所有迁移
echo "==> 执行数据库迁移..."
bash "$SCRIPT_DIR/migrate-native.sh"

echo "==> 初始化完成!"
