#!/usr/bin/env bash
# nucleagent-deploy/scripts/dev.sh
# 一键启动/停止全部本地 dev 服务。
#
# 用法：
#   ./scripts/dev.sh start   # 启动全部（docker infra + 3 后端 + 4 前端）
#   ./scripts/dev.sh stop    # 停止全部
#   ./scripts/dev.sh status  # 查看运行状态
#
# 服务清单：
#   infra:    MySQL(26606) + Redis(26679)  via docker compose
#   backends: auth(26670) core(26680) executor(26690)  via go run
#   frontends: shell(26600) auth-web(26678) core-web(26688) executor-web(26698)  via npm run dev

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEPLOY_DIR="$STACK_DIR/nucleagent-deploy"
LOG_DIR="$DEPLOY_DIR/.dev-logs"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}▶${NC} $1"; }
ok()    { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}!${NC} $1"; }

# 后端服务: name:dir:port
BACKENDS=(
  "auth:nucleagent-auth/app/src/server:26670"
  "core:nucleagent-core/app/src/server:26680"
  "executor:nucleagent-executor/app/src/server:26690"
)
# 前端服务: name:dir:port
FRONTENDS=(
  "shell:nucleagent-web:26600"
  "auth-web:nucleagent-auth/app/src/web:26678"
  "core-web:nucleagent-core/app/src/web:26688"
  "executor-web:nucleagent-executor/app/src/web:26698"
)

load_env() {
  # 加载 .env（如果存在）
  if [ -f "$DEPLOY_DIR/.env" ]; then
    set -a; . "$DEPLOY_DIR/.env"; set +a
  fi

  # .env 里的 DB_HOST/DB_PORT/REDIS_ADDR/CORE_URL/EXECUTOR_URL 是「容器内」视角
  # （供 docker-compose 用，主机名为 service 名）：
  #   DB_HOST=mysql  CORE_URL=http://nucleagent-core:26680  EXECUTOR_URL=http://nucleagent-executor:26690
  # 但 dev.sh 用 `go run` 在**宿主机**跑后端：宿主机解析不了这些 service 主机名。
  # 因此本地 dev 一律改写为 127.0.0.1 + 宿主端口，否则：
  #   - DB 为 nil → SeedAdminUser panic
  #   - executor 注册 core → 502（DNS 解析失败）
  #   - core 调 executor → 同理
  export DB_HOST=127.0.0.1
  export DB_PORT="${MYSQL_HOST_PORT:-26606}"
  export REDIS_ADDR="127.0.0.1:${REDIS_HOST_PORT:-26679}"
  export CORE_URL="http://localhost:${CORE_PORT:-26680}"
  export EXECUTOR_URL="http://localhost:${EXECUTOR_PORT:-26690}"

  # 宿主机若有系统代理（HTTP_PROXY 等），Go 的 http.Client 默认会走代理，
  # 导致服务间 localhost 互调被发到代理端口 → 502。本地 dev 一律关闭代理。
  unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy
}

port_running() {
  lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
}

start_infra() {
  info "启动基础设施 (MySQL + Redis)..."
  cd "$DEPLOY_DIR"
  docker compose up -d mysql redis
  sleep 3
  ok "MySQL(26606) + Redis(26679) 启动"
}

start_backend() {
  local name="$1" dir="$2" port="$3"
  if port_running "$port"; then warn "$name(:$port) 已在运行，跳过"; return; fi
  mkdir -p "$LOG_DIR"
  cd "$STACK_DIR/$dir"
  nohup go run . > "$LOG_DIR/$name.log" 2>&1 &
  echo $! > "$LOG_DIR/$name.pid"
  ok "$name 启动 (PID $!, :$port, log: .dev-logs/$name.log)"
}

start_frontend() {
  local name="$1" dir="$2" port="$3"
  if port_running "$port"; then warn "$name(:$port) 已在运行，跳过"; return; fi
  mkdir -p "$LOG_DIR"
  cd "$STACK_DIR/$dir"
  nohup npm run dev > "$LOG_DIR/$name.log" 2>&1 &
  echo $! > "$LOG_DIR/$name.pid"
  ok "$name 启动 (PID $!, :$port, log: .dev-logs/$name.log)"
}

start_all() {
  load_env
  start_infra
  echo ""
  info "启动后端服务..."
  for entry in "${BACKENDS[@]}"; do
    IFS=':' read -r name dir port <<< "$entry"
    start_backend "$name" "$dir" "$port"
  done
  echo ""
  info "启动前端服务..."
  for entry in "${FRONTENDS[@]}"; do
    IFS=':' read -r name dir port <<< "$entry"
    start_frontend "$name" "$dir" "$port"
  done
  echo ""
  ok "全部启动完成。访问 http://localhost:26600"
  echo "  日志: nucleagent-deploy/.dev-logs/<name>.log"
  echo "  停止: ./scripts/dev.sh stop"
}

stop_pid() {
  local pidfile="$1" name="$2"
  if [ -f "$pidfile" ]; then
    local pid=$(cat "$pidfile")
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null && ok "$name 已停止 (PID $pid)"
    else
      warn "$name 进程已不存在"
    fi
    rm -f "$pidfile"
  fi
}

stop_port() {
  local port="$1" name="$2"
  local pids=$(lsof -ti:"$port" 2>/dev/null || true)
  if [ -n "$pids" ]; then
    echo "$pids" | xargs kill 2>/dev/null || true
    ok "$name (:$port) 已停止"
  fi
}

stop_all() {
  info "停止全部服务..."
  for entry in "${FRONTENDS[@]}"; do
    IFS=':' read -r name dir port <<< "$entry"
    stop_pid "$LOG_DIR/$name.pid" "$name"
    stop_port "$port" "$name"
  done
  for entry in "${BACKENDS[@]}"; do
    IFS=':' read -r name dir port <<< "$entry"
    stop_pid "$LOG_DIR/$name.pid" "$name"
    stop_port "$port" "$name"
  done
  echo ""
  info "停止基础设施..."
  cd "$DEPLOY_DIR"
  docker compose down 2>/dev/null
  ok "已停止"
}

status_all() {
  info "服务状态:"
  echo -e "  基础设施:"
  cd "$DEPLOY_DIR"; docker compose ps 2>/dev/null | tail -n +1 | sed 's/^/    /'
  echo -e "  后端:"
  for entry in "${BACKENDS[@]}"; do
    IFS=':' read -r name dir port <<< "$entry"
    if port_running "$port"; then echo -e "    $name (:$port) ${GREEN}✓ 运行${NC}"; else echo -e "    $name (:$port) ${RED}✗ 未运行${NC}"; fi
  done
  echo -e "  前端:"
  for entry in "${FRONTENDS[@]}"; do
    IFS=':' read -r name dir port <<< "$entry"
    if port_running "$port"; then echo -e "    $name (:$port) ${GREEN}✓ 运行${NC}"; else echo -e "    $name (:$port) ${RED}✗ 未运行${NC}"; fi
  done
}

case "${1:-}" in
  start)  start_all ;;
  stop)   stop_all ;;
  status) status_all ;;
  *) echo "用法: $0 {start|stop|status}"; exit 1 ;;
esac
