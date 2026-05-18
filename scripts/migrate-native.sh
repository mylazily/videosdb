#!/usr/bin/env bash
# ============================================================
# migrate-native.sh — 数据库迁移执行脚本（非 Docker 版本）
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

MIGRATIONS_DIR="$PROJECT_DIR/migrations"

# psql 命令
export PGPASSWORD="$POSTGRES_PASSWORD"
PSQL_CMD="psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB -v ON_ERROR_STOP=1"

# 确保迁移目录存在
if [ ! -d "$MIGRATIONS_DIR" ]; then
    echo "错误: 迁移目录不存在: $MIGRATIONS_DIR"
    exit 1
fi

# 等待 PostgreSQL 就绪
echo "==> 等待 PostgreSQL 就绪..."
MAX_RETRIES=30
RETRY_COUNT=0

until pg_isready -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" > /dev/null 2>&1; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "错误: PostgreSQL 在 ${MAX_RETRIES} 秒后仍未就绪"
        exit 1
    fi
    sleep 1
done

echo "==> PostgreSQL 已就绪"

# 确保迁移记录表存在
echo "==> 检查迁移记录表..."
$PSQL_CMD -c "
CREATE TABLE IF NOT EXISTS schema_migrations (
    id              SERIAL PRIMARY KEY,
    filename        VARCHAR(255) NOT NULL UNIQUE,
    applied_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    checksum        VARCHAR(64),
    execution_time  INTEGER
);
" > /dev/null 2>&1

# 回滚模式
if [ "${1:-}" = "--rollback" ]; then
    ROLLBACK_COUNT="${2:-1}"
    echo "==> 回滚最近 ${ROLLBACK_COUNT} 个迁移..."

    # 获取已应用的迁移列表（倒序）
    APPLIED=$($PSQL_CMD -t -A -c "
        SELECT filename FROM schema_migrations
        ORDER BY id DESC
        LIMIT $ROLLBACK_COUNT;
    ")

    if [ -z "$APPLIED" ]; then
        echo "没有可回滚的迁移"
        exit 0
    fi

    echo "$APPLIED" | while read -r filename; do
        if [ -n "$filename" ]; then
            echo "  [回滚] $filename"
            echo "  注意: 回滚需要手动执行对应的 down SQL"
            echo "  请手动执行: DELETE FROM schema_migrations WHERE filename = '$filename';"
        fi
    done

    echo "==> 回滚提示完成（请手动执行对应的 down SQL）"
    exit 0
fi

# 正向迁移模式
echo "==> 检查未应用的迁移..."

# 获取所有迁移文件（按名称排序）
MIGRATION_FILES=$(ls -1 "$MIGRATIONS_DIR"/*.sql 2>/dev/null | sort)

if [ -z "$MIGRATION_FILES" ]; then
    echo "没有找到迁移文件"
    exit 0
fi

APPLIED_COUNT=0
SKIPPED_COUNT=0

for migration_file in $MIGRATION_FILES; do
    filename=$(basename "$migration_file")

    # 检查是否已应用
    IS_APPLIED=$($PSQL_CMD -t -A -c "
        SELECT COUNT(*) FROM schema_migrations WHERE filename = '$filename';
    ")

    if [ "$IS_APPLIED" -gt 0 ]; then
        echo "  [跳过] $filename（已应用）"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    fi

    # 执行迁移
    echo "  [执行] $filename ..."
    if $PSQL_CMD -f "$migration_file"; then
        echo "  [完成] $filename"
        APPLIED_COUNT=$((APPLIED_COUNT + 1))
    else
        echo "  [错误] $filename 执行失败!"
        exit 1
    fi
done

echo ""
echo "==> 迁移完成: 应用 ${APPLIED_COUNT} 个, 跳过 ${SKIPPED_COUNT} 个"
