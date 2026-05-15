.PHONY: up down init migrate rollback seed backup restore reset shell status logs help

# ============================================================
# 默认环境变量（可通过 .env 或命令行覆盖）
# ============================================================
POSTGRES_USER  ?= videos
POSTGRES_PASSWORD ?= videos123
POSTGRES_DB    ?= videosdb
POSTGRES_PORT  ?= 5432
POSTGRES_HOST  ?= localhost
REDIS_PORT     ?= 6379
BACKUP_DIR     ?= ./backups

# Docker 容器名
PG_CONTAINER   ?= videosdb-postgres
REDIS_CONTAINER ?= videosdb-redis

# psql 连接参数
PSQL           ?= docker exec -i $(PG_CONTAINER) psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

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
# 开发工具
# ============================================================

shell: ## 进入 psql 交互式终端
	docker exec -it $(PG_CONTAINER) psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

redis-cli: ## 进入 Redis CLI
	docker exec -it $(REDIS_CONTAINER) redis-cli

# ============================================================
# 帮助
# ============================================================

help: ## 显示帮助信息
	@echo "videosdb - xvideos 影视聚合系统数据库"
	@echo ""
	@echo "用法: make [target]"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
