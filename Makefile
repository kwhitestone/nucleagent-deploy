.PHONY: help up down build logs ps clean update update-pull update-deps update-build dev dev-stop

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

up: ## Start MySQL + Redis
	docker compose up -d mysql redis

down: ## Stop all services
	docker compose down

logs: ## Tail logs
	docker compose logs -f

ps: ## Show running services
	docker compose ps

clean: ## Stop and remove volumes (WARNING: deletes all data)
	docker compose down -v

update: ## 一键更新所有 repo（pull + 依赖 + 构建）
	@./scripts/update.sh --all

update-pull: ## 只 git pull 所有 repo
	@./scripts/update.sh --pull

update-deps: ## 只同步依赖（go mod tidy + npm install）
	@./scripts/update.sh --deps

update-build: ## 只构建验证
	@./scripts/update.sh --build

dev: ## 启动全部本地 dev 服务（MySQL/Redis + 3 后端 + 4 前端）
	@./scripts/dev.sh start

dev-stop: ## 停止全部本地 dev 服务
	@./scripts/dev.sh stop
