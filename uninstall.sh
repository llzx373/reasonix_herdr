#!/usr/bin/env bash
# reasonix-herdr 卸载脚本
#
# 用法:
#   ./uninstall.sh                  # 交互式卸载（会询问清理范围）
#   ./uninstall.sh --global         # 仅清理全局 hooks
#   ./uninstall.sh --project        # 仅清理当前项目 hooks
#   ./uninstall.sh --all            # 清理全部（hooks + 构建产物 + 依赖）
#   ./uninstall.sh --dry-run        # 仅预览
#   -h, --help                      # 显示此帮助信息

set -euo pipefail

# ── 颜色 ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── 默认值 ──
CLEAN_GLOBAL=false
CLEAN_PROJECT=false
CLEAN_BUILD=false
CLEAN_DEPS=false
DRY_RUN=false
SCOPE=""

# ── 解析参数 ──
while [[ $# -gt 0 ]]; do
  case "$1" in
    --global)
      CLEAN_GLOBAL=true
      SCOPE="global"
      shift
      ;;
    --project)
      CLEAN_PROJECT=true
      SCOPE="project"
      shift
      ;;
    --all)
      CLEAN_GLOBAL=true
      CLEAN_PROJECT=true
      CLEAN_BUILD=true
      CLEAN_DEPS=true
      SCOPE="all"
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      cat << 'EOF'
reasonix-herdr 卸载脚本

用法:
  ./uninstall.sh [选项]

选项:
  --global     清理全局 Reasonix hooks (~/.reasonix/settings.json)
  --project    清理当前工作区项目级 hooks (.reasonix/settings.json)
  --all        清理全部: hooks + 构建产物 + 依赖
  --dry-run    仅预览，不做实际修改
  -h, --help   显示此帮助信息

卸载内容:
  - 从 settings.json 中移除 reasonix-herdr 的 hook 条目
  - (--all) 删除 dist/ 构建产物
  - (--all) 删除 node_modules/ 依赖目录
EOF
      exit 0
      ;;
    *)
      echo -e "${RED}未知选项: $1${NC}"
      echo "使用 -h 查看帮助"
      exit 1
      ;;
  esac
done

# ── 检测项目根目录 ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
PROJECT_ROOT="$SCRIPT_DIR"

# ── 工具函数 ──

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*"; }
dry()     { echo -e "${YELLOW}[DRY]${NC}  $*"; }
step()    { echo -e "\n${BOLD}${CYAN}==>${NC} ${BOLD}$*${NC}"; }

run() {
  if $DRY_RUN; then
    dry "would run: $*"
    return 0
  fi
  "$@"
}

# ── JSON 清理逻辑（python3） ──

remove_hooks_json() {
  local target="$1"

  python3 - "$target" << 'PYEOF'
import json, sys, os

target_path = sys.argv[1]

if not os.path.exists(target_path):
    print(f"{target_path} 不存在，无需清理")
    sys.exit(0)

with open(target_path, 'r') as f:
    target = json.load(f)

if "hooks" not in target:
    print(f"{target_path} 中无 hooks 配置，无需清理")
    sys.exit(0)

removed = 0
for event in list(target["hooks"].keys()):
    entries = target["hooks"][event]
    new_entries = [
        e for e in entries
        if "herdr-agent-state" not in e.get("command", "")
    ]
    if len(new_entries) < len(entries):
        removed += len(entries) - len(new_entries)
    if new_entries:
        target["hooks"][event] = new_entries
    else:
        del target["hooks"][event]

if removed == 0:
    print(f"{target_path} 中未找到 reasonix-herdr hook 条目")
    sys.exit(0)

if not target["hooks"]:
    del target["hooks"]

with open(target_path, 'w') as f:
    json.dump(target, f, indent=2, ensure_ascii=False)
    f.write('\n')

print(f"已从 {target_path} 移除 {removed} 个 hook 条目")
PYEOF
}

# ── 清理 hooks ──

clean_global_hooks() {
  step "清理全局 Reasonix hooks"
  local target="$HOME/.reasonix/settings.json"
  info "目标: $target"

  if $DRY_RUN; then
    dry "将从 $target 中移除 reasonix-herdr hook 条目"
    return 0
  fi

  remove_hooks_json "$target"
  success "全局 hooks 清理完成"
}

clean_project_hooks() {
  step "清理项目级 Reasonix hooks"
  local target="$PROJECT_ROOT/.reasonix/settings.json"
  info "目标: $target"

  if $DRY_RUN; then
    dry "将从 $target 中移除 reasonix-herdr hook 条目"
    return 0
  fi

  remove_hooks_json "$target"
  success "项目级 hooks 清理完成"
}

# ── 清理构建产物 ──

clean_build() {
  step "清理构建产物"
  local dist_dir="$PROJECT_ROOT/dist"

  if [ -d "$dist_dir" ]; then
    info "删除 $dist_dir/"
    run rm -rf "$dist_dir"
    success "构建产物已清理"
  else
    info "dist/ 不存在，跳过"
  fi

  # 清理 bun 构建临时文件
  local bun_tmp
  bun_tmp=$(find "$PROJECT_ROOT" -maxdepth 1 -name '.bun-build' -o -name '*.bun-build' 2>/dev/null || true)
  if [ -n "$bun_tmp" ]; then
    info "删除 bun 临时构建文件"
    run rm -f "$PROJECT_ROOT"/*.bun-build
  fi
}

# ── 清理依赖 ──

clean_deps() {
  step "清理依赖"
  local node_modules="$PROJECT_ROOT/node_modules"

  if [ -d "$node_modules" ]; then
    info "删除 node_modules/"
    run rm -rf "$node_modules"
    success "依赖目录已清理"
  else
    info "node_modules/ 不存在，跳过"
  fi
}

# ── 交互式选择 ──

choose_scope() {
  if [ -n "$SCOPE" ]; then
    return 0
  fi

  echo ""
  echo -e "${BOLD}选择清理范围:${NC}"
  echo "  [1] 仅清理全局 hooks (~/.reasonix/settings.json)"
  echo "  [2] 仅清理项目级 hooks (.reasonix/settings.json)"
  echo "  [3] 清理全局 + 项目 hooks"
  echo "  [4] 全部清理 (hooks + 构建产物 + 依赖)"
  echo ""
  read -r -p "请输入 [1/2/3/4] (默认: 3): " choice
  choice="${choice:-3}"

  case "$choice" in
    1) CLEAN_GLOBAL=true ;;
    2) CLEAN_PROJECT=true ;;
    3) CLEAN_GLOBAL=true; CLEAN_PROJECT=true ;;
    4) CLEAN_GLOBAL=true; CLEAN_PROJECT=true; CLEAN_BUILD=true; CLEAN_DEPS=true ;;
    *) error "无效选择: $choice"; exit 1 ;;
  esac
}

# ── 确认 ──

confirm() {
  if $DRY_RUN; then
    return 0
  fi

  echo ""
  echo -e "${YELLOW}${BOLD}即将执行以下操作:${NC}"
  $CLEAN_GLOBAL  && echo "  • 清理全局 hooks (~/.reasonix/settings.json)"
  $CLEAN_PROJECT && echo "  • 清理项目级 hooks (.reasonix/settings.json)"
  $CLEAN_BUILD   && echo "  • 删除构建产物 (dist/)"
  $CLEAN_DEPS    && echo "  • 删除依赖目录 (node_modules/)"

  echo ""
  read -r -p "确认继续? [y/N] " confirm
  if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "已取消"
    exit 0
  fi
}

# ── 主流程 ──

main() {
  echo -e "${BOLD}${RED}"
  echo "╔══════════════════════════════════════╗"
  echo "║  reasonix-herdr  卸载               ║"
  echo "╚══════════════════════════════════════╝"
  echo -e "${NC}"

  if $DRY_RUN; then
    warn "** DRY RUN 模式 ** — 不会做任何实际修改"
  fi

  choose_scope
  confirm

  $CLEAN_GLOBAL  && clean_global_hooks
  $CLEAN_PROJECT && clean_project_hooks
  $CLEAN_BUILD   && clean_build
  $CLEAN_DEPS    && clean_deps

  echo ""
  echo -e "${BOLD}${GREEN}╔══════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${GREEN}║  卸载完成！                        ║${NC}"
  echo -e "${BOLD}${GREEN}╚══════════════════════════════════════╝${NC}"
  echo ""
  echo -e "提示: 如果已清理 hooks，${BOLD}重启 Reasonix 桌面端${NC} 使变更生效"
  echo ""
}

main
