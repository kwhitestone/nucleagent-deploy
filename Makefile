.PHONY: help up down build logs ps

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
