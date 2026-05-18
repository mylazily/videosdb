#!/usr/bin/env bash
# ============================================================
# install-postgres.sh — PostgreSQL 18.x 安装脚本（非 Docker）
# 用途：在 Ubuntu/Debian 系统上安装 PostgreSQL 18.x
# ============================================================

set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 配置
PG_VERSION="18"
PG_USER="${POSTGRES_USER:-videos}"
PG_PASSWORD="${POSTGRES_PASSWORD:-videos123}"
PG_DB="${POSTGRES_DB:-videosdb}"
PG_PORT="${POSTGRES_PORT:-5432}"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查 root 权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 root 权限运行此脚本"
        exit 1
    fi
}

# 安装 PostgreSQL 18.x
install_postgres() {
    log_info "开始安装 PostgreSQL ${PG_VERSION}..."
    
    # 添加 PostgreSQL 官方仓库
    log_info "添加 PostgreSQL APT 仓库..."
    
    # 安装依赖
    apt-get update
    apt-get install -y wget gnupg2 lsb-release curl
    
    # 添加官方仓库密钥
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
    
    # 添加仓库
    echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
    
    # 更新并安装
    apt-get update
    
    # 安装 PostgreSQL 18.x
    log_info "安装 PostgreSQL ${PG_VERSION}..."
    apt-get install -y postgresql-${PG_VERSION} postgresql-client-${PG_VERSION} postgresql-contrib-${PG_VERSION}
    
    # 安装额外扩展
    apt-get install -y postgresql-${PG_VERSION}-pgdg-pgroonga 2>/dev/null || true
    
    log_info "PostgreSQL ${PG_VERSION} 安装完成"
}

# 配置 PostgreSQL
configure_postgres() {
    log_info "配置 PostgreSQL..."
    
    PG_DATA_DIR="/var/lib/postgresql/${PG_VERSION}/main"
    PG_CONF_DIR="/etc/postgresql/${PG_VERSION}/main"
    
    # 停止服务
    systemctl stop postgresql@${PG_VERSION}-main
    
    # 备份原配置
    if [ -f "${PG_CONF_DIR}/postgresql.conf" ]; then
        cp "${PG_CONF_DIR}/postgresql.conf" "${PG_CONF_DIR}/postgresql.conf.backup.$(date +%Y%m%d)"
    fi
    
    # 优化配置
    cat > "${PG_CONF_DIR}/postgresql.conf" << EOF
# PostgreSQL ${PG_VERSION} 优化配置
# 自动生成于 $(date)

# 连接设置
listen_addresses = '*'
port = ${PG_PORT}
max_connections = 200

# 内存设置
shared_buffers = 256MB
effective_cache_size = 1GB
maintenance_work_mem = 256MB
work_mem = 4MB

# WAL 设置
wal_buffers = 16MB
min_wal_size = 1GB
max_wal_size = 4GB
checkpoint_completion_target = 0.9

# 查询规划器
random_page_cost = 1.1
effective_io_concurrency = 200
default_statistics_target = 100

# 日志
log_destination = 'stderr'
logging_collector = on
log_directory = '/var/log/postgresql'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = 1d
log_rotation_size = 100MB
log_min_duration_statement = 100
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
log_statement = 'ddl'

# 扩展
shared_preload_libraries = 'pg_trgm'

# 性能
autovacuum = on
autovacuum_max_workers = 3
autovacuum_naptime = 1min
EOF

    # 配置 pg_hba.conf
    cat > "${PG_CONF_DIR}/pg_hba.conf" << EOF
# PostgreSQL Client Authentication Configuration
# 自动生成于 $(date)

# 本地连接
type      database    user        address           method
local     all         postgres                      peer
local     all         all                           md5

# IPv4 本地连接
host      all         all         127.0.0.1/32      md5
host      all         all         10.0.0.0/8        md5
host      all         all         172.16.0.0/12     md5
host      all         all         192.168.0.0/16    md5

# IPv6 本地连接
host      all         all         ::1/128           md5
EOF

    log_info "PostgreSQL 配置完成"
}

# 创建数据库和用户
setup_database() {
    log_info "设置数据库和用户..."
    
    # 启动 PostgreSQL
    systemctl start postgresql@${PG_VERSION}-main
    systemctl enable postgresql@${PG_VERSION}-main
    
    # 等待 PostgreSQL 启动
    sleep 3
    
    # 创建用户
    su - postgres -c "psql -c \"CREATE USER ${PG_USER} WITH PASSWORD '${PG_PASSWORD}';\"" 2>/dev/null || \
        su - postgres -c "psql -c \"ALTER USER ${PG_USER} WITH PASSWORD '${PG_PASSWORD}';\""
    
    # 创建数据库
    su - postgres -c "psql -c \"CREATE DATABASE ${PG_DB} OWNER ${PG_USER} ENCODING 'UTF8' LC_COLLATE 'C' LC_CTYPE 'C' TEMPLATE template0;\"" 2>/dev/null || \
        log_warn "数据库 ${PG_DB} 已存在"
    
    # 授予权限
    su - postgres -c "psql -c \"GRANT ALL PRIVILEGES ON DATABASE ${PG_DB} TO ${PG_USER};\""
    
    # 创建扩展
    su - postgres -c "psql -d ${PG_DB} -c \"CREATE EXTENSION IF NOT EXISTS pg_trgm;\""
    su - postgres -c "psql -d ${PG_DB} -c \"CREATE EXTENSION IF NOT EXISTS uuid-ossp;\""
    
    log_info "数据库和用户设置完成"
}

# 安装 Redis
install_redis() {
    log_info "安装 Redis..."
    
    apt-get install -y redis-server
    
    # 配置 Redis
    cat > /etc/redis/redis.conf << 'REDISCONF'
# Redis 配置文件
bind 127.0.0.1
port 6379
tcp-backlog 511
timeout 0
tcp-keepalive 300

# 持久化
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec

# 内存管理
maxmemory 256mb
maxmemory-policy allkeys-lru

# 快照
save 900 1
save 300 10
save 60 10000

# 日志
loglevel notice
logfile /var/log/redis/redis-server.log

# 守护进程
daemonize yes
supervised systemd
pidfile /run/redis/redis-server.pid
dir /var/lib/redis
REDISCONF

    # 重启 Redis
    systemctl restart redis-server
    systemctl enable redis-server
    
    log_info "Redis 安装完成"
}

# 主函数
main() {
    log_info "开始安装 PostgreSQL ${PG_VERSION} 和 Redis..."
    
    check_root
    install_postgres
    configure_postgres
    setup_database
    install_redis
    
    log_info "安装完成！"
    log_info "PostgreSQL 版本: $(su - postgres -c 'psql --version')"
    log_info "Redis 版本: $(redis-server --version | head -1)"
    log_info ""
    log_info "连接信息:"
    log_info "  主机: localhost"
    log_info "  端口: ${PG_PORT}"
    log_info "  数据库: ${PG_DB}"
    log_info "  用户: ${PG_USER}"
    log_info ""
    log_info "管理命令:"
    log_info "  systemctl status postgresql@${PG_VERSION}-main"
    log_info "  systemctl status redis-server"
    log_info "  sudo -u postgres psql -d ${PG_DB}"
}

main "$@"
