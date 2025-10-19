# 企业微信群聊天记录存档系统 Makefile
# 提供便捷的开发、测试和部署命令

.PHONY: help build test lint format clean dev prod deploy backup logs status

# 默认目标
.DEFAULT_GOAL := help

# 颜色定义
GREEN  := \033[32m
YELLOW := \033[33m
RED    := \033[31m
BLUE   := \033[34m
RESET  := \033[0m

# 项目配置
PROJECT_NAME := wechat-work-archive
DOCKER_COMPOSE := docker-compose
DOCKER_COMPOSE_DEV := docker-compose -f docker/docker-compose.dev.yml
DOCKER_COMPOSE_TEST := docker-compose -f docker/docker-compose.test.yml
DOCKER_COMPOSE_PROD := docker-compose -f docker/docker-compose.yml

# 检查环境文件
check-env:
	@if [ ! -f .env ]; then \
		echo "$(RED)错误: .env 文件不存在$(RESET)"; \
		echo "$(YELLOW)请复制 .env.example 为 .env 并填入配置$(RESET)"; \
		echo "cp .env.example .env"; \
		exit 1; \
	fi

# 显示帮助信息
help: ## 显示帮助信息
	@echo "$(BLUE)企业微信群聊天记录存档系统 - 可用命令:$(RESET)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "$(GREEN)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)使用示例:$(RESET)"
	@echo "  make setup          # 初始化项目环境"
	@echo "  make dev            # 启动开发环境"
	@echo "  make test           # 运行所有测试"
	@echo "  make deploy-prod    # 部署到生产环境"

# ================================================================================
# 项目初始化
# ================================================================================

setup: ## 初始化项目环境
	@echo "$(BLUE)正在初始化项目环境...$(RESET)"
	@if [ ! -f .env ]; then cp .env.example .env; echo "$(GREEN)已创建 .env 文件$(RESET)"; fi
	@echo "$(YELLOW)请编辑 .env 文件并填入正确的配置值$(RESET)"

install: ## 安装开发依赖
	@echo "$(BLUE)正在安装开发依赖...$(RESET)"
	pip install -r api/requirements-dev.txt
	@echo "$(GREEN)开发依赖安装完成$(RESET)"

# ================================================================================
# 构建和镜像
# ================================================================================

build: ## 构建Docker镜像
	@echo "$(BLUE)正在构建Docker镜像...$(RESET)"
	docker build -t $(PROJECT_NAME):latest ./api
	@echo "$(GREEN)镜像构建完成$(RESET)"

build-dev: ## 构建开发环境镜像
	@echo "$(BLUE)正在构建开发环境镜像...$(RESET)"
	docker build --target development -t $(PROJECT_NAME):dev ./api
	@echo "$(GREEN)开发环境镜像构建完成$(RESET)"

build-prod: ## 构建生产环境镜像
	@echo "$(BLUE)正在构建生产环境镜像...$(RESET)"
	docker build --target production -t $(PROJECT_NAME):prod ./api
	@echo "$(GREEN)生产环境镜像构建完成$(RESET)"

# ================================================================================
# 开发环境
# ================================================================================

dev: check-env ## 启动开发环境
	@echo "$(BLUE)正在启动开发环境...$(RESET)"
	$(DOCKER_COMPOSE_DEV) up -d
	@echo "$(GREEN)开发环境已启动$(RESET)"
	@echo "$(YELLOW)API地址: http://localhost:8001$(RESET)"
	@echo "$(YELLOW)API文档: http://localhost:8001/docs$(RESET)"

dev-build: check-env ## 重新构建并启动开发环境
	@echo "$(BLUE)正在重新构建开发环境...$(RESET)"
	$(DOCKER_COMPOSE_DEV) up -d --build
	@echo "$(GREEN)开发环境已重新构建并启动$(RESET)"

dev-stop: ## 停止开发环境
	@echo "$(BLUE)正在停止开发环境...$(RESET)"
	$(DOCKER_COMPOSE_DEV) down
	@echo "$(GREEN)开发环境已停止$(RESET)"

dev-logs: ## 查看开发环境日志
	$(DOCKER_COMPOSE_DEV) logs -f

dev-shell: ## 进入开发环境容器
	$(DOCKER_COMPOSE_DEV) exec api bash

# ================================================================================
# 生产环境
# ================================================================================

prod: check-env ## 启动生产环境
	@echo "$(BLUE)正在启动生产环境...$(RESET)"
	$(DOCKER_COMPOSE_PROD) up -d
	@echo "$(GREEN)生产环境已启动$(RESET)"
	@echo "$(YELLOW)API地址: http://localhost:8000$(RESET)"
	@echo "$(YELLOW)监控面板: http://localhost:3000$(RESET)"

prod-build: check-env ## 重新构建并启动生产环境
	@echo "$(BLUE)正在重新构建生产环境...$(RESET)"
	$(DOCKER_COMPOSE_PROD) up -d --build
	@echo "$(GREEN)生产环境已重新构建并启动$(RESET)"

prod-stop: ## 停止生产环境
	@echo "$(BLUE)正在停止生产环境...$(RESET)"
	$(DOCKER_COMPOSE_PROD) down
	@echo "$(GREEN)生产环境已停止$(RESET)"

prod-logs: ## 查看生产环境日志
	$(DOCKER_COMPOSE_PROD) logs -f

# ================================================================================
# 测试
# ================================================================================

test: ## 运行所有测试
	@echo "$(BLUE)正在运行所有测试...$(RESET)"
	$(DOCKER_COMPOSE_TEST) up --abort-on-container-exit --exit-code-from api-test
	$(DOCKER_COMPOSE_TEST) down -v
	@echo "$(GREEN)测试完成$(RESET)"

test-unit: ## 运行单元测试
	@echo "$(BLUE)正在运行单元测试...$(RESET)"
	cd api && python -m pytest tests/unit -v

test-integration: ## 运行集成测试
	@echo "$(BLUE)正在运行集成测试...$(RESET)"
	cd api && python -m pytest tests/integration -v

test-e2e: ## 运行端到端测试
	@echo "$(BLUE)正在运行端到端测试...$(RESET)"
	cd api && python -m pytest tests/e2e -v

test-coverage: ## 生成测试覆盖率报告
	@echo "$(BLUE)正在生成测试覆盖率报告...$(RESET)"
	cd api && python -m pytest tests/ --cov=src --cov-report=html --cov-report=term-missing
	@echo "$(GREEN)覆盖率报告已生成: api/htmlcov/index.html$(RESET)"

# ================================================================================
# 代码质量
# ================================================================================

lint: ## 代码检查
	@echo "$(BLUE)正在进行代码检查...$(RESET)"
	cd api && flake8 src tests
	cd api && mypy src --ignore-missing-imports
	@echo "$(GREEN)代码检查完成$(RESET)"

format: ## 代码格式化
	@echo "$(BLUE)正在格式化代码...$(RESET)"
	cd api && black src tests
	cd api && isort src tests
	@echo "$(GREEN)代码格式化完成$(RESET)"

security: ## 安全检查
	@echo "$(BLUE)正在进行安全检查...$(RESET)"
	cd api && bandit -r src
	cd api && safety check
	@echo "$(GREEN)安全检查完成$(RESET)"

# ================================================================================
# 数据库操作
# ================================================================================

db-migrate: ## 运行数据库迁移
	@echo "$(BLUE)正在运行数据库迁移...$(RESET)"
	$(DOCKER_COMPOSE_PROD) exec api alembic upgrade head
	@echo "$(GREEN)数据库迁移完成$(RESET)"

db-downgrade: ## 回滚数据库迁移
	@echo "$(BLUE)正在回滚数据库迁移...$(RESET)"
	$(DOCKER_COMPOSE_PROD) exec api alembic downgrade -1
	@echo "$(GREEN)数据库回滚完成$(RESET)"

db-reset: ## 重置数据库
	@echo "$(RED)警告: 这将删除所有数据!$(RESET)"
	@read -p "确认要重置数据库吗? [y/N]: " confirm && [ "$$confirm" = "y" ]
	$(DOCKER_COMPOSE_PROD) exec postgres psql -U $$DB_USER -c "DROP DATABASE IF EXISTS $$DB_NAME;"
	$(DOCKER_COMPOSE_PROD) exec postgres psql -U $$DB_USER -c "CREATE DATABASE $$DB_NAME;"
	$(MAKE) db-migrate
	@echo "$(GREEN)数据库重置完成$(RESET)"

db-backup: ## 备份数据库
	@echo "$(BLUE)正在备份数据库...$(RESET)"
	./scripts/backup.sh --db-only
	@echo "$(GREEN)数据库备份完成$(RESET)"

# ================================================================================
# 部署操作
# ================================================================================

deploy-staging: ## 部署到测试环境
	@echo "$(BLUE)正在部署到测试环境...$(RESET)"
	./scripts/deploy.sh staging rolling
	@echo "$(GREEN)测试环境部署完成$(RESET)"

deploy-prod: ## 部署到生产环境
	@echo "$(BLUE)正在部署到生产环境...$(RESET)"
	@echo "$(RED)警告: 这将部署到生产环境!$(RESET)"
	@read -p "确认要部署到生产环境吗? [y/N]: " confirm && [ "$$confirm" = "y" ]
	./scripts/deploy.sh production blue-green
	@echo "$(GREEN)生产环境部署完成$(RESET)"

rollback: ## 回滚到上一个版本
	@echo "$(BLUE)正在回滚到上一个版本...$(RESET)"
	./scripts/rollback.sh
	@echo "$(GREEN)回滚完成$(RESET)"

# ================================================================================
# 备份和恢复
# ================================================================================

backup: ## 创建完整备份
	@echo "$(BLUE)正在创建完整备份...$(RESET)"
	./scripts/backup.sh
	@echo "$(GREEN)备份完成$(RESET)"

backup-compress: ## 创建压缩备份
	@echo "$(BLUE)正在创建压缩备份...$(RESET)"
	./scripts/backup.sh --compress
	@echo "$(GREEN)压缩备份完成$(RESET)"

backup-list: ## 列出所有备份
	@echo "$(BLUE)可用的备份:$(RESET)"
	./scripts/backup.sh --list-backups

# ================================================================================
# 监控和日志
# ================================================================================

logs: ## 查看应用日志
	$(DOCKER_COMPOSE_PROD) logs -f api

logs-db: ## 查看数据库日志
	$(DOCKER_COMPOSE_PROD) logs -f postgres

logs-redis: ## 查看Redis日志
	$(DOCKER_COMPOSE_PROD) logs -f redis

logs-worker: ## 查看Worker日志
	$(DOCKER_COMPOSE_PROD) logs -f worker

status: ## 查看服务状态
	@echo "$(BLUE)服务状态:$(RESET)"
	$(DOCKER_COMPOSE_PROD) ps
	@echo ""
	@echo "$(BLUE)健康检查:$(RESET)"
	./scripts/health_check.sh

health: ## 运行健康检查
	@echo "$(BLUE)正在运行健康检查...$(RESET)"
	./scripts/health_check.sh --check-all

monitoring: ## 打开监控面板
	@echo "$(BLUE)监控面板地址:$(RESET)"
	@echo "$(YELLOW)Grafana: http://localhost:3000$(RESET)"
	@echo "$(YELLOW)Prometheus: http://localhost:9090$(RESET)"

# ================================================================================
# 清理操作
# ================================================================================

clean: ## 清理未使用的Docker资源
	@echo "$(BLUE)正在清理Docker资源...$(RESET)"
	docker system prune -f
	docker volume prune -f
	@echo "$(GREEN)清理完成$(RESET)"

clean-all: ## 清理所有Docker资源(包括镜像)
	@echo "$(RED)警告: 这将删除所有未使用的Docker资源!$(RESET)"
	@read -p "确认要清理所有资源吗? [y/N]: " confirm && [ "$$confirm" = "y" ]
	docker system prune -af
	docker volume prune -f
	@echo "$(GREEN)全部清理完成$(RESET)"

clean-logs: ## 清理日志文件
	@echo "$(BLUE)正在清理日志文件...$(RESET)"
	find logs -name "*.log" -mtime +7 -delete 2>/dev/null || true
	@echo "$(GREEN)日志清理完成$(RESET)"

# ================================================================================
# 开发工具
# ================================================================================

shell: ## 进入API容器shell
	$(DOCKER_COMPOSE_PROD) exec api bash

shell-db: ## 进入数据库shell
	$(DOCKER_COMPOSE_PROD) exec postgres psql -U $$DB_USER $$DB_NAME

shell-redis: ## 进入Redis shell
	$(DOCKER_COMPOSE_PROD) exec redis redis-cli

docs: ## 生成API文档
	@echo "$(BLUE)正在生成API文档...$(RESET)"
	cd api && python -c "import src.app; print('API文档: http://localhost:8000/docs')"

update: ## 更新依赖包
	@echo "$(BLUE)正在更新依赖包...$(RESET)"
	pip install --upgrade -r api/requirements-dev.txt
	pip freeze > api/requirements.txt
	@echo "$(GREEN)依赖包更新完成$(RESET)"

# ================================================================================
# Git操作
# ================================================================================

git-hooks: ## 安装Git钩子
	@echo "$(BLUE)正在安装Git钩子...$(RESET)"
	cp scripts/git-hooks/pre-commit .git/hooks/
	chmod +x .git/hooks/pre-commit
	@echo "$(GREEN)Git钩子安装完成$(RESET)"

# ================================================================================
# 性能测试
# ================================================================================

benchmark: ## 运行性能测试
	@echo "$(BLUE)正在运行性能测试...$(RESET)"
	cd api && python -m pytest tests/performance/ -v
	@echo "$(GREEN)性能测试完成$(RESET)"

load-test: ## 运行负载测试
	@echo "$(BLUE)正在运行负载测试...$(RESET)"
	locust -f tests/load/locustfile.py --host=http://localhost:8000
	@echo "$(GREEN)负载测试完成$(RESET)"

# ================================================================================
# 信息显示
# ================================================================================

info: ## 显示项目信息
	@echo "$(BLUE)项目信息:$(RESET)"
	@echo "项目名称: $(PROJECT_NAME)"
	@echo "Docker Compose版本: $$(docker-compose --version)"
	@echo "Docker版本: $$(docker --version)"
	@echo "当前分支: $$(git branch --show-current 2>/dev/null || echo 'unknown')"
	@echo "最新提交: $$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"

version: ## 显示版本信息
	@echo "$(BLUE)版本信息:$(RESET)"
	@echo "API版本: $$(grep version api/src/__init__.py | cut -d'"' -f2)"
	@echo "数据库版本: $$(docker-compose exec postgres psql -U $$DB_USER -d $$DB_NAME -t -c 'SELECT version();' | head -1 | xargs 2>/dev/null || echo 'unknown')"