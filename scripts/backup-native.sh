#!/usr/bin/env bash
# ============================================================
# backup-native.sh — 数据库备份脚本（非 Docker 版本）
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
BACKUP_DIR="${BACKUP_DIR:-$PROJECT_DIR/backups}"

# 创建备份目录
mkdir -p "$BACKUP_DIR"

# 生成备份文件名（含时间戳）
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/${POSTGRES_DB}_${TIMESTAMP}.sql.gz"

echo "==> 开始备份数据库: $POSTGRES_DB"
echo "    主机: $POSTGRES_HOST:$POSTGRES_PORT"
echo "    目标: $BACKUP_FILE"

# 执行备份
export PGPASSWORD="$POSTGRES_PASSWORD"
pg_dump \
    -h "$POSTGRES_HOST" \
    -p "$POSTGRES_PORT" \
    -U "$POSTGRES_USER" \
    -d "$POSTGRES_DB" \
    --no-owner \
    --no-privileges \
    --format=plain \
    --verbose 2>/dev/null | gzip > "$BACKUP_FILE"

# 检查备份结果
if [ -f "$BACKUP_FILE" ] && [ -s "$BACKUP_FILE" ]; then
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo "==> 备份成功!"
    echo "    文件: $BACKUP_FILE"
    echo "    大小: $BACKUP_SIZE"

    # 清理超过 30 天的旧备份
    echo "==> 清理超过 30 天的旧备份..."
    DELETED_COUNT=$(find "$BACKUP_DIR" -name "${POSTGRES_DB}_*.sql.gz" -mtime +30 -delete -print 2>/dev/null | wc -l)
    if [ "$DELETED_COUNT" -gt 0 ]; then
        echo "    已清理 ${DELETED_COUNT} 个旧备份文件"
    else
        echo "    无需清理"
    fi
else
    echo "==> 备份失败!"
    rm -f "$BACKUP_FILE"
    exit 1
fi
