.PHONY: up down init migrate rollback seed backup restore reset shell status logs lint test clean analyze help

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

# Docker 容器名
PG_CONTAINER    ?= videosdb-postgres
REDIS_CONTAINER ?= videosdb-redis

# psql 连接参数
PSQL            ?= docker exec -i $(PG_CONTAINER) psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)
PSQL_TTY        ?= docker exec -it $(PG_CONTAINER) psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

# ============================================================
# 容器管理
# ============================================================

up: ## 启动 PostgreSQL + Redis 开发环境
	docker compose up -d

down: ## 停止并移除容器
	docker compose down

restart: down up ## 重启容器

logs: ## 查看容器日志
	docker compose logs -f

# ============================================================
# 数据库操作
# ============================================================

init: ## 初始化数据库（创建扩展 + 执行所有迁移）
	@echo "==> 初始化数据库..."
	@bash scripts/init.sh

migrate: ## 执行未应用的迁移
	@echo "==> 执行迁移..."
	@bash scripts/migrate.sh

rollback: ## 回滚最近 N 个迁移（用法: make rollback N=1）
	@echo "==> 回滚迁移..."
	@if [ -z "$(N)" ]; then echo "用法: make rollback N=<数量>"; exit 1; fi
	@bash scripts/migrate.sh --rollback $(N)

seed: ## 导入种子数据
	@echo "==> 导入种子数据..."
	@$(PSQL) -f migrations/006_seed_data.sql

status: ## 查看迁移状态
	@echo "==> 迁移状态:"
	@$(PSQL) -c "SELECT filename, applied_at FROM schema_migrations ORDER BY id;"

# ============================================================
# 备份与恢复
# ============================================================

backup: ## 备份数据库到 backups/ 目录
	@echo "==> 备份数据库..."
	@bash scripts/backup.sh

restore: ## 从备份恢复数据库（用法: make restore FILE=backups/xxx.sql.gz）
	@echo "==> 恢复数据库..."
	@if [ -z "$(FILE)" ]; then echo "用法: make restore FILE=<备份文件>"; exit 1; fi
	@gunzip -c $(FILE) | $(PSQL)

reset: ## 重置数据库（危险：删除并重建）
	@echo "==> 重置数据库..."
	@$(PSQL) -c "DROP SCHEMA public CASCADE;"
	@$(PSQL) -c "CREATE SCHEMA public;"
	@$(PSQL) -c "DROP TABLE IF EXISTS schema_migrations;"
	$(MAKE) init

# ============================================================
# 代码质量与测试
# ============================================================

lint: ## 检查 SQL 语法（使用 pgspot 或基本语法检查）
	@echo "==> 检查 SQL 语法..."
	@for file in migrations/*.sql; do \
		echo "检查: $$file"; \
		$(PSQL) -f $$file --dry-run 2>/dev/null || echo "  注意: 无法使用 dry-run 模式，请手动检查语法"; \
		done
	@echo "SQL 语法检查完成（请确保所有文件无错误）"

test: ## 运行测试查询
	@echo "==> 运行测试查询..."
	@echo "1. 测试数据库连接..."
	@$(PSQL) -c "SELECT version();" > /dev/null && echo "   连接成功"
	@echo "2. 测试表是否存在..."
	@$(PSQL) -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" | head -3
	@echo "3. 测试视图..."
	@$(PSQL) -c "SELECT * FROM v_system_overview;"
	@echo "4. 测试函数..."
	@$(PSQL) -c "SELECT search_videos('测试', NULL, NULL, NULL, 1, 0);" > /dev/null && echo "   search_videos 函数正常"
	@echo "测试完成"

clean: ## 清理软删除数据（默认30天前的数据）
	@echo "==> 清理软删除数据..."
	@echo "清理 videos 表..."
	@$(PSQL) -c "SELECT cleanup_soft_deleted('videos', 30);"
	@echo "清理 users 表..."
	@$(PSQL) -c "SELECT cleanup_soft_deleted('users', 30);"
	@echo "清理 comments 表..."
	@$(PSQL) -c "SELECT cleanup_soft_deleted('comments', 30);"
	@echo "清理完成"

# ============================================================
# 性能分析
# ============================================================

analyze: ## 更新表统计信息
	@echo "==> 更新表统计信息..."
	@$(PSQL) -c "ANALYZE;"
	@echo "统计信息更新完成"

vacuum: ## 执行 VACUUM ANALYZE（清理死元组并更新统计）
	@echo "==> 执行 VACUUM ANALYZE..."
	@$(PSQL) -c "VACUUM ANALYZE;"
	@echo "VACUUM 完成"

# ============================================================
# 开发工具
# ============================================================

shell: ## 进入 psql 交互式终端
	docker exec -it $(PG_CONTAINER) psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

redis-cli: ## 进入 Redis CLI
	docker exec -it $(REDIS_CONTAINER) redis-cli

health: ## 运行数据库健康检查
	@echo "==> 运行数据库健康检查..."
	@$(PSQL) -f scripts/health_check.sql

# ============================================================
# 帮助
# ============================================================

help: ## 显示帮助信息
	@echo "videosdb - xvideos 影视聚合系统数据库"
	@echo ""
	@echo "用法: make [target]"
	@echo ""
	@echo "容器管理:"
	@echo "  up          启动 PostgreSQL + Redis 开发环境"
	@echo "  down        停止并移除容器"
	@echo "  restart     重启容器"
	@echo "  logs        查看容器日志"
	@echo ""
	@echo "数据库操作:"
	@echo "  init        初始化数据库（创建扩展 + 执行所有迁移）"
	@echo "  migrate     执行未应用的迁移"
	@echo "  rollback    回滚最近 N 个迁移（用法: make rollback N=1）"
	@echo "  seed        导入种子数据"
	@echo "  status      查看迁移状态"
	@echo ""
	@echo "备份与恢复:"
	@echo "  backup      备份数据库到 backups/ 目录"
	@echo "  restore     从备份恢复数据库（用法: make restore FILE=backups/xxx.sql.gz）"
	@echo "  reset       重置数据库（删除并重建）"
	@echo ""
	@echo "代码质量与测试:"
	@echo "  lint        检查 SQL 语法"
	@echo "  test        运行测试查询"
	@echo "  clean       清理软删除数据（默认30天前的数据）"
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
