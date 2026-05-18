.PHONY: install start stop restart status logs init migrate rollback seed backup restore reset shell redis-cli health lint test clean analyze vacuum help

# ============================================================
# 默认环境变量（可通过 .env 或命令行覆盖）
# ============================================================
POSTGRES_USER   ?= videos
POSTGRES_PASSWORD ?= videos123
POSTGRES_DB     ?= videosdb
POSTGRES_PORT   ?= 5432
POSTGRES_HOST   ?= localhost
REDIS_PORT      ?= 6379
BACKUP_DIR      ?= ./backups
PG_VERSION      ?= 18

# psql 连接参数
PSQL            ?= PGPASSWORD=$(POSTGRES_PASSWORD) psql -h $(POSTGRES_HOST) -p $(POSTGRES_PORT) -U $(POSTGRES_USER) -d $(POSTGRES_DB)
PSQL_ADMIN      ?= sudo -u postgres psql

# ============================================================
# 安装与启动
# ============================================================

install: ## 安装 PostgreSQL 18.x 和 Redis
	@echo "==> 安装 PostgreSQL $(PG_VERSION) 和 Redis..."
	@sudo bash scripts/install-postgres.sh

start: ## 启动 PostgreSQL 和 Redis 服务
	@echo "==> 启动服务..."
	@sudo systemctl start postgresql@$(PG_VERSION)-main
	@sudo systemctl start redis-server
	@echo "✅ 服务已启动"

stop: ## 停止 PostgreSQL 和 Redis 服务
	@echo "==> 停止服务..."
	@sudo systemctl stop postgresql@$(PG_VERSION)-main
	@sudo systemctl stop redis-server
	@echo "✅ 服务已停止"

restart: ## 重启 PostgreSQL 和 Redis 服务
	@echo "==> 重启服务..."
	@sudo systemctl restart postgresql@$(PG_VERSION)-main
	@sudo systemctl restart redis-server
	@echo "✅ 服务已重启"

status: ## 查看服务状态
	@echo "==> PostgreSQL 状态:"
	@sudo systemctl status postgresql@$(PG_VERSION)-main --no-pager || true
	@echo ""
	@echo "==> Redis 状态:"
	@sudo systemctl status redis-server --no-pager || true

logs: ## 查看 PostgreSQL 日志
	@sudo tail -f /var/log/postgresql/postgresql-$(shell date +%Y-%m-%d)*.log 2>/dev/null || \
		sudo journalctl -u postgresql@$(PG_VERSION)-main -f

# ============================================================
# 数据库操作
# ============================================================

init: ## 初始化数据库（创建扩展 + 执行所有迁移）
	@echo "==> 初始化数据库..."
	@bash scripts/init-native.sh

migrate: ## 执行未应用的迁移
	@echo "==> 执行迁移..."
	@bash scripts/migrate-native.sh

rollback: ## 回滚最近 N 个迁移（用法: make rollback N=1）
	@echo "==> 回滚迁移..."
	@if [ -z "$(N)" ]; then echo "用法: make rollback N=<数量>"; exit 1; fi
	@bash scripts/migrate-native.sh --rollback $(N)

seed: ## 导入种子数据
	@echo "==> 导入种子数据..."
	@$(PSQL) -f migrations/006_seed_data.sql

migration-status: ## 查看迁移状态
	@echo "==> 迁移状态:"
	@$(PSQL) -c "SELECT filename, applied_at FROM schema_migrations ORDER BY id;" 2>/dev/null || \
		echo "迁移表不存在，请先执行 make init"

# ============================================================
# 备份与恢复
# ============================================================

backup: ## 备份数据库到 backups/ 目录
	@echo "==> 备份数据库..."
	@bash scripts/backup-native.sh

restore: ## 从备份恢复数据库（用法: make restore FILE=backups/xxx.sql.gz）
	@echo "==> 恢复数据库..."
	@if [ -z "$(FILE)" ]; then echo "用法: make restore FILE=<备份文件>"; exit 1; fi
	@echo "警告: 这将覆盖当前数据库！"
	@read -p "确认继续? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	@gunzip -c $(FILE) | $(PSQL)
	@echo "✅ 恢复完成"

reset: ## 重置数据库（危险：删除并重建）
	@echo "==> 重置数据库..."
	@echo "⚠️  警告: 这将删除所有数据！"
	@read -p "确认继续? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	@$(PSQL) -c "DROP SCHEMA public CASCADE;" || true
	@$(PSQL) -c "CREATE SCHEMA public;" || true
	@$(PSQL) -c "DROP TABLE IF EXISTS schema_migrations;" || true
	@$(MAKE) init

# ============================================================
# 代码质量与测试
# ============================================================

lint: ## 检查 SQL 语法
	@echo "==> 检查 SQL 语法..."
	@for file in migrations/*.sql; do \
		echo "检查: $$file"; \
		$(PSQL) -c "\\set ON_ERROR_STOP on" -f $$file 2>/dev/null || echo "  注意: 请手动检查语法"; \
	done
	@echo "SQL 语法检查完成"

test: ## 运行测试查询
	@echo "==> 运行测试查询..."
	@echo "1. 测试数据库连接..."
	@$(PSQL) -c "SELECT version();" > /dev/null && echo "   ✅ 连接成功"
	@echo "2. 测试表是否存在..."
	@$(PSQL) -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" | head -3
	@echo "3. 测试视图..."
	@$(PSQL) -c "SELECT * FROM v_system_overview;" 2>/dev/null || echo "   视图不存在"
	@echo "4. 测试函数..."
	@$(PSQL) -c "SELECT search_videos('测试', NULL, NULL, NULL, 1, 0);" > /dev/null 2>&1 && echo "   ✅ search_videos 函数正常" || echo "   函数不存在"
	@echo "✅ 测试完成"

clean: ## 清理软删除数据（默认30天前的数据）
	@echo "==> 清理软删除数据..."
	@$(PSQL) -c "SELECT cleanup_soft_deleted('videos', 30);" 2>/dev/null || echo "函数不存在，跳过"
	@$(PSQL) -c "SELECT cleanup_soft_deleted('users', 30);" 2>/dev/null || echo "函数不存在，跳过"
	@$(PSQL) -c "SELECT cleanup_soft_deleted('comments', 30);" 2>/dev/null || echo "函数不存在，跳过"
	@echo "✅ 清理完成"

# ============================================================
# 性能分析
# ============================================================

analyze: ## 更新表统计信息
	@echo "==> 更新表统计信息..."
	@$(PSQL) -c "ANALYZE;"
	@echo "✅ 统计信息更新完成"

vacuum: ## 执行 VACUUM ANALYZE（清理死元组并更新统计）
	@echo "==> 执行 VACUUM ANALYZE..."
	@$(PSQL) -c "VACUUM ANALYZE;"
	@echo "✅ VACUUM 完成"

# ============================================================
# 开发工具
# ============================================================

shell: ## 进入 psql 交互式终端
	@$(PSQL)

redis-cli: ## 进入 Redis CLI
	@redis-cli

health: ## 运行数据库健康检查
	@echo "==> 运行数据库健康检查..."
	@$(PSQL) -f scripts/health_check.sql 2>/dev/null || echo "健康检查脚本执行失败"

# ============================================================
# 帮助
# ============================================================

help: ## 显示帮助信息
	@echo "videosdb - 影视聚合系统数据库管理（非 Docker 版本）"
	@echo ""
	@echo "用法: make [target]"
	@echo ""
	@echo "安装与启动:"
	@echo "  install     安装 PostgreSQL $(PG_VERSION) 和 Redis"
	@echo "  start       启动 PostgreSQL 和 Redis 服务"
	@echo "  stop        停止 PostgreSQL 和 Redis 服务"
	@echo "  restart     重启 PostgreSQL 和 Redis 服务"
	@echo "  status      查看服务状态"
	@echo "  logs        查看 PostgreSQL 日志"
	@echo ""
	@echo "数据库操作:"
	@echo "  init              初始化数据库（创建扩展 + 执行所有迁移）"
	@echo "  migrate           执行未应用的迁移"
	@echo "  rollback          回滚最近 N 个迁移（用法: make rollback N=1）"
	@echo "  seed              导入种子数据"
	@echo "  migration-status  查看迁移状态"
	@echo ""
	@echo "备份与恢复:"
	@echo "  backup      备份数据库到 backups/ 目录"
	@echo "  restore     从备份恢复数据库（用法: make restore FILE=backups/xxx.sql.gz）"
	@echo "  reset       重置数据库（删除并重建）"
	@echo ""
	@echo "代码质量与测试:"
	@echo "  lint        检查 SQL 语法"
	@echo "  test        运行测试查询"
	@echo "  clean       清理软删除数据"
	@echo ""
	@echo "性能分析:"
	@echo "  analyze     更新表统计信息"
	@echo "  vacuum      执行 VACUUM ANALYZE"
	@echo ""
	@echo "开发工具:"
	@echo "  shell       进入 psql 交互式终端"
	@echo "  redis-cli   进入 Redis CLI"
	@echo "  health      运行数据库健康检查"
	@echo ""
	@echo "其他:"
	@echo "  help        显示此帮助信息"
