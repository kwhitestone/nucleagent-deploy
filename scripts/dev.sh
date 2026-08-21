#!/usr/bin/env bash
# nucleagent-deploy/scripts/dev.sh
# 一键启动/停止全部本地 dev 服务。
#
# 用法：
#   ./scripts/dev.sh start [服务名...]   # 启动（无参数=全部；可指定多个服务名）
#   ./scripts/dev.sh stop  [服务名...]   # 停止（无参数=全部；可指定多个服务名）
#   ./scripts/dev.sh restart [服务名...] # 重启（无参数=全部；可指定多个服务名）
#   ./scripts/dev.sh status              # 查看运行状态
#
# 支持的服务名（infra 也算）：
#   infra  mysql  redis
#   auth  storage  core  executor
#   shell  auth-web  core-web  executor-web
#
# start / restart 支持「停旧起新」——重复跑会先杀掉旧进程再起新的，不会报端口占用。
#
# 示例：
#   ./scripts/dev.sh start executor             # 只启动 executor
#   ./scripts/dev.sh start core executor        # 同时启动 core 和 executor
#   ./scripts/dev.sh stop executor              # 只停 executor
#   ./scripts/dev.sh restart executor           # 只重启 executor
#   ./scripts/dev.sh restart                    # 重启全部
#
# 服务清单：
#   infra:    MySQL(26606) + Redis(26679)  via docker compose
#   backends: auth(26670) storage(26610) core(26680) executor(26690)  via go run
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
# executor 不在此列 —— 它走容器方式（见 start_executor）。hermes 及其完整运行时
# （Python/Playwright/浏览器）只在容器里有：裸跑 go run 缺 hermes 二进制，且宿主机
# 的 hermes(v0.18.2) 落后于 submodule(v0.19.1)，附件/模型选择这些按新协议开发的
# 功能只在容器版上验证过。
BACKENDS=(
  "auth:nucleagent-auth/app/src/server:26670"
  "storage:nucleagent-storage/app/src/server:26610"
  "core:nucleagent-core/app/src/server:26680"
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
  export STORAGE_URL="http://localhost:${STORAGE_PORT:-26610}"
  # core 前端直连 storage 上传附件（浏览器直传 CS，core 不代理字节流）。
  # 必须是浏览器可达地址，不能是 docker service 名。
  export VITE_STORAGE_URL="${VITE_STORAGE_URL:-http://localhost:${STORAGE_PORT:-26610}}"
  # storage 的 LocalProvider 签发的上传/下载 URL 必须是宿主机可达地址。
  export STORAGE_LOCAL_BASE_URL="${STORAGE_LOCAL_BASE_URL:-http://localhost:${STORAGE_PORT:-26610}}"

  # ---- 存储 ----
  # storage 走 LocalProvider（本地磁盘），本机开发开箱即用。
  export STORAGE_PROVIDER="${STORAGE_PROVIDER:-local}"

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
  # 停旧起新：若端口已被占用，先停掉旧进程，确保可以重复启动
  if port_running "$port"; then
    stop_port "$port" "$name"
    sleep 1
  fi
  mkdir -p "$LOG_DIR"
  cd "$STACK_DIR/$dir"
  nohup go run . > "$LOG_DIR/$name.log" 2>&1 &
  echo $! > "$LOG_DIR/$name.pid"
  ok "$name 启动 (PID $!, :$port, log: .dev-logs/$name.log)"
}

# ---- executor：容器方式 ----
# hermes + 完整运行时（Python/Playwright/浏览器）只在镜像里有。
# Go 代码更新后需先 cd nucleagent-executor && ./build.sh --skip-hermes 重建镜像。
EXECUTOR_CONTAINER="nucleagent-executor-dev"
EXECUTOR_VOLUME="nucleagent-executor-data"   # hermes 的 /opt/data（session 状态，跨重启保留）

executor_image_exists() {
  docker image inspect nucleagent-executor >/dev/null 2>&1
}

start_executor() {
  # 已在跑则先删掉（停旧起新，与其它服务一致）
  docker rm -f "$EXECUTOR_CONTAINER" >/dev/null 2>&1 || true
  if ! executor_image_exists; then
    warn "镜像 nucleagent-executor 不存在，正在构建（首次较慢，hermes 层已缓存则 ~1min）..."
    (cd "$STACK_DIR/nucleagent-executor" && ./build.sh --skip-hermes) || {
      warn "镜像构建失败；executor 未启动。可手动构建: cd nucleagent-executor && ./build.sh"
      return 1
    }
  fi
  local token="${EXECUTOR_TOKEN:-}"
  if [ -z "$token" ]; then
    warn "EXECUTOR_TOKEN 未配置（应写入 nucleagent-deploy/.env）；executor 未启动"
    return 1
  fi
  docker volume inspect "$EXECUTOR_VOLUME" >/dev/null 2>&1 || docker volume create "$EXECUTOR_VOLUME" >/dev/null
  docker run -d --name "$EXECUTOR_CONTAINER" \
    --add-host=host.docker.internal:host-gateway \
    -v "${EXECUTOR_VOLUME}:/opt/data" \
    -e CORE_URL="http://host.docker.internal:${CORE_PORT:-26680}" \
    -e EXECUTOR_TOKEN="$token" \
    nucleagent-executor >/dev/null
  ok "executor 启动 (容器 $EXECUTOR_CONTAINER, log: docker logs $EXECUTOR_CONTAINER)"
}

stop_executor() {
  if docker rm -f "$EXECUTOR_CONTAINER" >/dev/null 2>&1; then
    ok "executor 已停止 (容器 $EXECUTOR_CONTAINER)"
  else
    warn "executor 容器未在运行"
  fi
}

start_frontend() {
  local name="$1" dir="$2" port="$3"
  # 停旧起新：若端口已被占用，先停掉旧进程，确保可以重复启动
  if port_running "$port"; then
    stop_port "$port" "$name"
    sleep 1
  fi
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
  info "启动 executor（容器）..."
  start_executor
  echo ""
  info "启动前端服务..."
  for entry in "${FRONTENDS[@]}"; do
    IFS=':' read -r name dir port <<< "$entry"
    start_frontend "$name" "$dir" "$port"
  done
  echo ""
  ok "全部启动完成。访问 http://localhost:26600"
  echo "  日志: 后端/前端在 .dev-logs/<name>.log；executor 用 docker logs $EXECUTOR_CONTAINER"
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
  stop_executor
  echo ""
  info "停止基础设施..."
  cd "$DEPLOY_DIR"
  docker compose down 2>/dev/null
  ok "已停止"
}

# ---- 单服务名 → 类型/dir/port 解析 ----
# 回显: backend|frontend|infra  dir(后端/前端)  port   ；infra 只回显 infra
# 未找到返回非 0
resolve_service() {
  local svc="$1"
  case "$svc" in
    infra)  echo "infra"; return 0 ;;
    mysql)  echo "infra-mysql"; return 0 ;;
    redis)  echo "infra-redis"; return 0 ;;
    executor) echo "executor-container"; return 0 ;;
  esac
  for entry in "${BACKENDS[@]}"; do
    IFS=':' read -r name dir port <<< "$entry"
    if [ "$name" = "$svc" ]; then echo "backend $dir $port"; return 0; fi
  done
  for entry in "${FRONTENDS[@]}"; do
    IFS=':' read -r name dir port <<< "$entry"
    if [ "$name" = "$svc" ]; then echo "frontend $dir $port"; return 0; fi
  done
  return 1
}

start_one() {
  local svc="$1"
  local resolved; resolved=$(resolve_service "$svc") || {
    warn "未知服务: $svc（可用: infra mysql redis auth storage core executor shell auth-web core-web executor-web）"
    return 1
  }
  case "$resolved" in
    infra)        start_infra ;;
    infra-mysql)  info "启动 MySQL..."; cd "$DEPLOY_DIR"; docker compose up -d mysql; sleep 3; ok "MySQL(26606) 启动" ;;
    infra-redis)  info "启动 Redis..."; cd "$DEPLOY_DIR"; docker compose up -d redis; sleep 1; ok "Redis(26679) 启动" ;;
    executor-container) start_executor ;;
    backend*)     read -r type dir port <<< "$resolved"; start_backend "$svc" "$dir" "$port" ;;
    frontend*)    read -r type dir port <<< "$resolved"; start_frontend "$svc" "$dir" "$port" ;;
  esac
}

stop_one() {
  local svc="$1"
  local resolved; resolved=$(resolve_service "$svc") || {
    warn "未知服务: $svc（可用: infra mysql redis auth storage core executor shell auth-web core-web executor-web）"
    return 1
  }
  case "$resolved" in
    infra)
      info "停止基础设施..."; cd "$DEPLOY_DIR"; docker compose down 2>/dev/null; ok "基础设施已停止" ;;
    infra-mysql)
      info "停止 MySQL..."; cd "$DEPLOY_DIR"; docker compose stop mysql 2>/dev/null; ok "MySQL 已停止" ;;
    infra-redis)
      info "停止 Redis..."; cd "$DEPLOY_DIR"; docker compose stop redis 2>/dev/null; ok "Redis 已停止" ;;
    executor-container)
      stop_executor ;;
    # resolve_service 回显的是 "backend <dir> <port>"，必须用 * 通配，
    # 否则 `stop <单个后端服务>` 永远匹配不上（原写法 backend|frontend 是死分支）。
    backend*|frontend*)
      read -r type dir port <<< "$resolved"
      stop_pid "$LOG_DIR/$svc.pid" "$svc"
      stop_port "$port" "$svc" ;;
  esac
}

restart_one() {
  stop_one "$1" && sleep 1 && start_one "$1"
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
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${EXECUTOR_CONTAINER}$"; then
    echo -e "    executor (容器) ${GREEN}✓ 运行${NC}"
  else
    echo -e "    executor (容器) ${RED}✗ 未运行${NC}"
  fi
  echo -e "  前端:"
  for entry in "${FRONTENDS[@]}"; do
    IFS=':' read -r name dir port <<< "$entry"
    if port_running "$port"; then echo -e "    $name (:$port) ${GREEN}✓ 运行${NC}"; else echo -e "    $name (:$port) ${RED}✗ 未运行${NC}"; fi
  done
}

case "${1:-}" in
  start)
    shift
    load_env
    if [ $# -eq 0 ]; then
      start_all
    else
      for svc in "$@"; do start_one "$svc"; done
    fi ;;
  stop)
    shift
    if [ $# -eq 0 ]; then
      stop_all
    else
      for svc in "$@"; do stop_one "$svc"; done
    fi ;;
  restart)
    shift
    load_env
    if [ $# -eq 0 ]; then
      stop_all && sleep 2 && start_all
    else
      for svc in "$@"; do restart_one "$svc"; done
    fi ;;
  status) status_all ;;
  *) echo "用法: $0 {start|stop|restart|status} [服务名...]"; exit 1 ;;
esac
