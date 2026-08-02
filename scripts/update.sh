#!/usr/bin/env bash
# nucleagent-deploy/scripts/update.sh
# 一键更新所有 nucleagent 子项目（git pull + 依赖同步 + 构建）。
#
# 用法：
#   ./scripts/update.sh          # 全量更新（pull + 依赖 + 构建）
#   ./scripts/update.sh --pull   # 只 git pull，不动依赖
#   ./scripts/update.sh --deps   # 只同步依赖（go mod tidy + npm install）
#   ./scripts/update.sh --build  # 只构建验证
#
# 前置：所有 repo 在 ../<name>/ 下（相对 deploy repo 根）。

set -euo pipefail

# 脚本在 nucleagent-deploy/scripts/ 下，stack 根是上两级
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}▶${NC} $1"; }
ok()    { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}!${NC} $1"; }
fail()  { echo -e "${RED}✗${NC} $1"; exit 1; }

# 需要更新的 repo 列表（name:相对路径）
REPOS=(
  "prism-fusion:prism-fusion"
  "nucleagent-shared:nucleagent-shared"
  "nucleagent-core:nucleagent-core"
  "nucleagent-auth:nucleagent-auth"
  "nucleagent-executor:nucleagent-executor"
  "nucleagent-web:nucleagent-web"
  "nucleagent-deploy:nucleagent-deploy"
  "nucleagent-docs:nucleagent-docs"
)

# 后端服务（含 Go 代码，需 go build）
GO_BACKENDS=(nucleagent-core nucleagent-auth nucleagent-executor)
# 前端目录（含 package.json，需 npm install）
WEB_DIRS=(
  "nucleagent-web"
  "nucleagent-auth/app/src/web"
  "nucleagent-core/app/src/web"
  "nucleagent-executor/app/src/web"
)

ACTION="${1:---all}"

do_pull() {
  info "Git pull 所有 repo..."
  cd "$STACK_DIR"
  for entry in "${REPOS[@]}"; do
    name="${entry%%:*}"
    path="${entry##*:}"
    if [ ! -d "$STACK_DIR/$path/.git" ]; then
      warn "跳过 $name（非 git repo）"
      continue
    fi
    cd "$STACK_DIR/$path"
    branch=$(git branch --show-current 2>/dev/null || echo "main")
    printf "  %-22s (%s) " "$name" "$branch"
    if git pull --ff-only --quiet 2>/dev/null; then
      behind=$(git rev-list --count @{upstream}..HEAD 2>/dev/null || echo "0")
      ok "已更新 (本地领先 $behind)"
    else
      warn "pull 失败或无 upstream"
    fi
  done
}

do_deps() {
  info "同步后端 Go 依赖..."
  for repo in "${GO_BACKENDS[@]}"; do
    local dir="$STACK_DIR/$repo/app/src/server"
    if [ ! -f "$dir/go.mod" ]; then continue; fi
    printf "  %-22s " "$repo"
    cd "$dir"
    if go mod tidy 2>/dev/null; then ok "go mod tidy"; else warn "go mod tidy 失败"; fi
  done

  info "同步前端依赖..."
  for webdir in "${WEB_DIRS[@]}"; do
    local dir="$STACK_DIR/$webdir"
    if [ ! -f "$dir/package.json" ]; then continue; fi
    printf "  %-40s " "$webdir"
    cd "$dir"
    if [ -d node_modules ]; then
      ok "node_modules 已存在（跳过 install）"
    else
      if npm install --no-audit --no-fund --silent 2>/dev/null; then ok "npm install"; else warn "npm install 失败"; fi
    fi
  done
}

do_build() {
  info "构建验证后端..."
  for repo in "${GO_BACKENDS[@]}"; do
    local dir="$STACK_DIR/$repo/app/src/server"
    if [ ! -f "$dir/go.mod" ]; then continue; fi
    printf "  %-22s " "$repo"
    cd "$dir"
    if go build ./... 2>/dev/null; then ok "go build"; else fail "$repo 构建失败"; fi
  done

  info "构建验证前端..."
  for webdir in "${WEB_DIRS[@]}"; do
    local dir="$STACK_DIR/$webdir"
    if [ ! -f "$dir/package.json" ]; then continue; fi
    printf "  %-40s " "$webdir"
    cd "$dir"
    if npm run build >/dev/null 2>&1; then ok "build"; else warn "build 失败（可能 dev 才需要）"; fi
  done
}

case "$ACTION" in
  --pull)  do_pull ;;
  --deps)  do_deps ;;
  --build) do_build ;;
  --all|"")
    do_pull
    echo ""
    do_deps
    echo ""
    do_build
    echo ""
    ok "更新完成。运行 'make up' 启动基础设施，再启动各服务。"
    ;;
  *)
    echo "用法: $0 [--pull|--deps|--build|--all]"
    exit 1
    ;;
esac
