#!/usr/bin/env bash
# nucleagent-deploy/scripts/sync-design-tokens.sh
#
# 从设计稿提取 Aurora 设计系统（tokens + 动画库）并分发到 4 个前端。
#
# 为什么需要这个脚本：
#   重构前，同一套 token 在 shell(39行)/auth(240行)/core(461行)/
#   executor(113行) 的 global.css 里各有一份**手抄**副本，内容已互相漂移
#   （比如 core 有 --na-grad-mesh，shell 没有）。手抄必然再次漂移，因此
#   改为「单一来源 + 机械提取 + 分发」。
#
# 数据流：
#   nucleagent-docs/design/nucleagent-design.html  (设计稿 = 唯一真源)
#        │  <style> 第 11–221 行：:root tokens / reset / 动画库
#        ▼
#   nucleagent-web/src/styles/aurora.css           (提取产物 + --na-* 兼容层)
#        │  复制
#        ▼
#   {auth,core,executor}/app/src/web/src/styles/aurora.css
#
# 用法：
#   ./scripts/sync-design-tokens.sh          # 提取 + 分发
#   ./scripts/sync-design-tokens.sh --check  # 只校验是否同步（CI 用，不写文件）
#
# 改设计的正确顺序：先改 nucleagent-design.html，再跑本脚本。
# 不要手改 aurora.css —— 会在下次同步时被覆盖。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${BLUE}▶${NC} $1"; }
ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }

SRC="$STACK_DIR/nucleagent-docs/design/nucleagent-design.html"
PRIMARY="$STACK_DIR/nucleagent-web/src/styles/aurora.css"

# 设计稿 <style> 内的前置段行号（tokens + reset + 动画库，App Shell 之前）。
# 若设计稿结构调整需同步更新这两个数字——脚本会先做哨兵校验。
EXTRACT_START=11
EXTRACT_END=220

# 分发目标（子应用）
TARGETS=(
  "nucleagent-auth/app/src/web/src/styles/aurora.css"
  "nucleagent-core/app/src/web/src/styles/aurora.css"
  "nucleagent-executor/app/src/web/src/styles/aurora.css"
)

MODE="${1:-sync}"

[ -f "$SRC" ] || fail "找不到设计稿: $SRC"

# --- 哨兵校验：确认提取范围仍然正确 -------------------------------------
# 起始行应是设计系统标题注释；结束行应是动画工具类 .delay-9。
head_line=$(sed -n "$((EXTRACT_START + 1))p" "$SRC")
tail_line=$(sed -n "${EXTRACT_END}p" "$SRC")
case "$head_line" in
  *'NucleAgent Design System'*) ;;
  *) fail "提取起始行($((EXTRACT_START + 1)))不是设计系统标题，设计稿结构可能已变：[$head_line]" ;;
esac
case "$tail_line" in
  *'.delay-9'*) ;;
  *) fail "提取结束行($EXTRACT_END)不是 .delay-9，设计稿结构可能已变：[$tail_line]" ;;
esac

# --- 生成 aurora.css ----------------------------------------------------
build_aurora() {
  cat <<'HEADER'
/* ============================================================
   Aurora — NucleAgent 权威设计系统（tokens + 动画库）
   ============================================================
   ⚠️ 本文件由脚本生成，请勿手改。

   生成方式：
     nucleagent-deploy/scripts/sync-design-tokens.sh
   来源：
     nucleagent-docs/design/nucleagent-design.html
     <style> 前置段（:root tokens / reset / 动画库）逐字提取

   为什么是「提取」而不是「手抄」：
     重构前 global.css 在 shell/auth/core/executor 各有一份手抄副本且
     内容已互相漂移。任何手抄都会再次漂移，因此保持与设计稿逐字一致。

   改设计的正确顺序：
     1. 改 nucleagent-design.html
     2. 跑 ./scripts/sync-design-tokens.sh
     不要在本文件里加业务样式——组件样式写各自 .vue 的 <style scoped>。

   兼容层：
     子应用历史上用 --na-* 前缀。文件末尾把 --na-* 映射到本体 token，
     因此旧样式无需改写即可继续工作。
   ============================================================ */

HEADER
  sed -n "${EXTRACT_START},${EXTRACT_END}p" "$SRC"
  cat <<'FOOTER'

/* ============================================
   --na-* 兼容别名
   ============================================
   子应用（auth/core/executor）现有 .vue 大量引用 --na-* 前缀。
   保留映射，避免为改前缀而全量重写子应用样式。新代码请直接用上面
   的本体 token（--bg / --text-primary / --grad-brand ...）。 */
:root {
  --na-bg: var(--bg);
  --na-bg-card: var(--bg-card);
  --na-bg-subtle: var(--bg-subtle);
  --na-bg-hover: var(--bg-hover);

  --na-text: var(--text-primary);
  --na-text-secondary: var(--text-secondary);
  --na-text-tertiary: var(--text-tertiary);

  --na-border: var(--border);
  --na-border-strong: var(--border-strong);
  --na-accent: var(--accent);
  --na-accent-hover: var(--accent-hover);

  --na-grad-brand: var(--grad-brand);
  --na-grad-brand-soft: var(--grad-brand-soft);
  --na-grad-teal-indigo: var(--grad-teal-indigo);
  --na-grad-indigo-violet: var(--grad-violet-fuchsia);
  --na-grad-aurora: var(--grad-aurora);
  --na-grad-mesh: var(--grad-mesh);

  --na-shadow-xs: var(--shadow-xs);
  --na-shadow-sm: var(--shadow-sm);
  --na-shadow-md: var(--shadow-md);
  --na-shadow-lg: var(--shadow-lg);
  --na-shadow-xl: var(--shadow-xl);
  --na-shadow-glow-teal: var(--shadow-glow-teal);
  --na-shadow-glow-indigo: var(--shadow-glow-indigo);
  --na-shadow-glow-violet: var(--shadow-glow-violet);

  --na-font-display: var(--font-display);
  --na-font-body: var(--font-body);
  --na-font-mono: var(--font-mono);

  --na-r-sm: var(--r-sm);
  --na-r-md: var(--r-md);
  --na-r-lg: var(--r-lg);
  --na-r-xl: var(--r-xl);
  --na-r-2xl: var(--r-2xl);
  --na-r-full: var(--r-full);
}
FOOTER
}

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
build_aurora > "$TMP"

# --- --check 模式：只比对，不写 -----------------------------------------
if [ "$MODE" = "--check" ]; then
  drift=0
  ALL=("$PRIMARY")
  for t in "${TARGETS[@]}"; do ALL+=("$STACK_DIR/$t"); done
  for f in "${ALL[@]}"; do
    rel="${f#"$STACK_DIR"/}"
    if [ ! -f "$f" ]; then
      warn "$rel 缺失"; drift=1
    elif ! cmp -s "$TMP" "$f"; then
      warn "$rel 与设计稿不同步"; drift=1
    else
      ok "$rel"
    fi
  done
  [ "$drift" -eq 0 ] || fail "设计 token 已漂移，运行 ./scripts/sync-design-tokens.sh 修复"
  ok "全部同步"
  exit 0
fi

# --- 同步模式 -----------------------------------------------------------
info "从设计稿提取 Aurora tokens（第 ${EXTRACT_START}–${EXTRACT_END} 行）..."
mkdir -p "$(dirname "$PRIMARY")"
cp "$TMP" "$PRIMARY"
ok "nucleagent-web/src/styles/aurora.css ($(wc -l < "$PRIMARY") 行)"

info "分发到子应用..."
for t in "${TARGETS[@]}"; do
  dest="$STACK_DIR/$t"
  if [ ! -d "$(dirname "$dest")" ]; then
    warn "跳过 $t（目录不存在）"
    continue
  fi
  cp "$TMP" "$dest"
  ok "$t"
done

echo ""
ok "设计 token 同步完成（1 个真源 → 4 个前端）"
echo "  校验: ./scripts/sync-design-tokens.sh --check"
