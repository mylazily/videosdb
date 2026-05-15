#!/usr/bin/env bash
# ============================================================
# init.sh — 数据库初始化脚本
# 用途：创建扩展、执行所有迁移
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
POSTGRES_DB="${POSTGRES_DB:-videosdb}"
PG_CONTAINER="${PG_CONTAINER:-videosdb-postgres}"

# 等待 PostgreSQL 就绪
echo "==> 等待 PostgreSQL 就绪..."
MAX_RETRIES=30
RETRY_COUNT=0

until docker exec "$PG_CONTAINER" pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" > /dev/null 2>&1; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "错误: PostgreSQL 在 ${MAX_RETRIES} 秒后仍未就绪"
        exit 1
    fi
    sleep 1
done

echo "==> PostgreSQL 已就绪"

# 执行所有迁移
echo "==> 执行数据库迁移..."
bash "$SCRIPT_DIR/migrate.sh"

echo "==> 初始化完成!"
