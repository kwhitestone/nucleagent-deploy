#!/usr/bin/env bash
# nucleagent-deploy/scripts/bootstrap.sh
# 新机器一键引导：clone 全部 8 个 repo + 初始化环境。
#
# 用法（新机器上）：
#   git clone git@github.com:kwhitestone/nucleagent-deploy.git
#   cd nucleagent-deploy
#   ./scripts/bootstrap.sh
#
# 脚本会：
#   1. 在上一级目录（nucleagent-stack/）clone 其余 7 个 repo
#   2. 复制 .env.example -> .env
#   3. 调用 update.sh 同步依赖 + 构建验证
#   4. 提示下一步（make dev）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STACK_DIR="$(cd "$DEPLOY_DIR/.." && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}▶${NC} $1"; }
ok()    { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}!${NC} $1"; }
fail()  { echo -e "${RED}✗${NC} $1"; exit 1; }

# 所有 repo（remote:本地目录名）
ALL_REPOS=(
  "git@github.com:kwhitestone/prism-fusion.git:prism-fusion"
  "git@github.com:kwhitestone/nucleagent-shared.git:nucleagent-shared"
  "git@github.com:kwhitestone/nucleagent-core.git:nucleagent-core"
  "git@github.com:kwhitestone/nucleagent-auth.git:nucleagent-auth"
  "git@github.com:kwhitestone/nucleagent-executor.git:nucleagent-executor"
  "git@github.com:kwhitestone/nucleagent-web.git:nucleagent-web"
  "git@github.com:kwhitestone/nucleagent-docs.git:nucleagent-docs"
)

echo ""
echo "======================================"
echo "  Nucleagent 一键引导"
echo "======================================"
echo "  stack 目录: $STACK_DIR"
echo ""

# 前置检查
info "前置检查..."
command -v git >/dev/null || fail "未安装 git"
command -v go >/dev/null || fail "未安装 go (1.25+)"
command -v node >/dev/null || fail "未安装 node (22+)"
command -v npm >/dev/null || fail "未安装 npm"
command -v docker >/dev/null || warn "未安装 docker（基础设施 MySQL/Redis 需要）"
ok "git/go/node/npm 就绪"

# 1. Clone 所有 repo
info "Clone 全部 repo 到 $STACK_DIR/..."
for entry in "${ALL_REPOS[@]}"; do
  remote="${entry%:*}"
  name="${entry##*:}"
  target="$STACK_DIR/$name"
  if [ -d "$target/.git" ]; then
    ok "$name 已存在，跳过"
  else
    printf "  %-22s " "$name"
    if git clone --quiet "$remote" "$target" 2>/dev/null; then
      ok "clone 完成"
    else
      warn "clone 失败（检查 SSH key 或网络）"
    fi
  fi
done

# 2. 配置 .env
echo ""
info "配置环境变量..."
if [ ! -f "$DEPLOY_DIR/.env" ]; then
  cp "$DEPLOY_DIR/.env.example" "$DEPLOY_DIR/.env"
  ok "已从 .env.example 创建 .env（请按需修改密钥）"
  warn "JWT_SECRET / EXECUTOR_TOKEN 当前为默认值，生产环境务必修改！"
else
  ok ".env 已存在，跳过"
fi

# 3. 同步依赖 + 构建
echo ""
info "同步依赖 + 构建验证..."
cd "$DEPLOY_DIR"
./scripts/update.sh --deps
echo ""
./scripts/update.sh --build

# 4. 完成
echo ""
echo "======================================"
ok "引导完成！"
echo "======================================"
echo ""
echo "下一步："
echo "  cd $DEPLOY_DIR"
echo "  make dev          # 启动全部服务（infra + 3 后端 + 4 前端）"
echo "  # 访问 http://localhost:26600"
echo ""
echo "  make dev-stop     # 停止全部"
echo "  make update       # 以后更新代码"
echo ""
