#!/usr/bin/env bash
# reasonix-herdr 初始化安装脚本
#
# 用法:
#   ./install.sh                    # 交互式安装（会询问配置目标）
#   ./install.sh --global           # 安装到全局 Reasonix 配置 (~/.reasonix/settings.json)
#   ./install.sh --project          # 安装到当前项目 .reasonix/settings.json
#   ./install.sh --project-dir /path/to/project  # 安装到指定项目
#
# 选项:
#   --global       配置全局 Reasonix hooks（推荐，所有项目生效）
#   --project      配置当前工作区项目级 hooks
#   --project-dir  配置指定目录的项目级 hooks
#   --skip-build   跳过构建步骤（假设已构建）
#   --dry-run      仅预览将要执行的操作，不做实际修改
#   -h, --help     显示此帮助信息

set -euo pipefail

# ── 颜色 ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ── 默认值 ──
SCOPE=""          # global | project
PROJECT_DIR=""    # 仅 SCOPE=project 时使用
SKIP_BUILD=false
DRY_RUN=false
HOOK_BINARY_NAME="herdr-agent-state"

# ── 解析参数 ──
while [[ $# -gt 0 ]]; do
  case "$1" in
    --global)
      SCOPE="global"
      shift
      ;;
    --project)
      SCOPE="project"
      shift
      ;;
    --project-dir)
      SCOPE="project"
      PROJECT_DIR="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      cat << 'EOF'
reasonix-herdr 初始化安装脚本

用法:
  ./install.sh [选项]

选项:
  --global         配置全局 Reasonix hooks (~/.reasonix/settings.json)
  --project        配置当前工作区项目级 hooks (.reasonix/settings.json)
  --project-dir DIR  配置指定目录的项目级 hooks
  --skip-build     跳过构建步骤（假设已构建）
  --dry-run        仅预览，不做实际修改
  -h, --help       显示此帮助信息

安装步骤:
  1. 检测前置条件 (bun / npm + node)
  2. 安装依赖 (bun install)
  3. 编译二进制 (bun run build)
  4. 将 hook 配置写入目标 settings.json
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

# ── 前置检查 ──

check_prerequisites() {
  step "1/4 检测前置条件"

  # 优先检测 bun
  if command -v bun &>/dev/null; then
    local bun_ver
    bun_ver=$(bun --version 2>/dev/null || echo "unknown")
    success "bun ${bun_ver} 已就绪"
    PKG_MGR="bun"
    return 0
  fi

  # 回退到 npm + node
  if command -v node &>/dev/null && command -v npm &>/dev/null; then
    local node_ver npm_ver
    node_ver=$(node --version 2>/dev/null || echo "unknown")
    npm_ver=$(npm --version 2>/dev/null || echo "unknown")
    warn "未检测到 bun，使用 node ${node_ver} + npm ${npm_ver}"
    warn "注意: 使用 node 构建将不会生成独立二进制，npm run build 不可用"
    warn "推荐安装 bun: https://bun.sh"
    PKG_MGR="npm"
    return 0
  fi

  error "未检测到 bun 或 node。请安装 bun (推荐) 或 Node.js"
  error "  bun:  https://bun.sh"
  error "  node: https://nodejs.org"
  exit 1
}

# ── 安装依赖 ──

install_dependencies() {
  step "2/4 安装依赖"

  if $SKIP_BUILD; then
    info "跳过依赖安装 (--skip-build)"
    return 0
  fi

  if [ "$PKG_MGR" = "bun" ]; then
    run bun install
  else
    run npm install
  fi
  success "依赖安装完成"
}

# ── 构建 ──

build() {
  step "3/4 构建二进制"

  if $SKIP_BUILD; then
    info "跳过构建 (--skip-build)"
    if [ ! -f "$PROJECT_ROOT/dist/$HOOK_BINARY_NAME" ]; then
      error "二进制文件不存在: dist/$HOOK_BINARY_NAME"
      error "请先运行构建，或去掉 --skip-build 选项"
      exit 1
    fi
    success "检测到已有二进制: dist/$HOOK_BINARY_NAME"
    return 0
  fi

  if [ "$PKG_MGR" = "bun" ]; then
    run bun run build
    success "构建完成: dist/$HOOK_BINARY_NAME"
  else
    warn "当前使用 node/npm，run build 需要 bun。跳过二进制编译。"
    warn "运行时需要 node 来执行 src/index.ts"
    HOOK_BINARY_NAME=""  # 标记为未构建
  fi
}

# ── 确定 hook 命令路径 ──

get_hook_command() {
  if [ -n "${HOOK_BINARY_NAME:-}" ]; then
    # 有编译的二进制
    echo "$PROJECT_ROOT/dist/$HOOK_BINARY_NAME"
  else
    # 回退到 node 运行
    echo "node $PROJECT_ROOT/dist/index.js"
  fi
}

# ── JSON 合并逻辑（python3） ──

merge_hooks_json() {
  # 将 reasonix-herdr 的 hook 条目合并到目标 settings.json
  # $1: 目标 settings.json 路径
  # $2: hook command 字符串
  local target="$1"
  local hook_cmd="$2"
  local template="$PROJECT_ROOT/.reasonix/settings.json"

  python3 - "$target" "$hook_cmd" "$template" << 'PYEOF'
import json, sys, os

target_path = sys.argv[1]
hook_cmd    = sys.argv[2]
template_path = sys.argv[3]

# 读取模板中的 hooks
with open(template_path, 'r') as f:
    template = json.load(f)

# 替换占位符
template_hooks = json.loads(
    json.dumps(template.get("hooks", {}))
    .replace("{{HOOK_PATH}}", hook_cmd)
)

# 读取目标配置（如果存在）
if os.path.exists(target_path):
    with open(target_path, 'r') as f:
        try:
            target = json.load(f)
        except json.JSONDecodeError:
            print(f"警告: {target_path} 不是合法的 JSON，将重新创建", file=sys.stderr)
            target = {}
else:
    target = {}

# 确保有 hooks 键
if "hooks" not in target:
    target["hooks"] = {}

target_hooks = target["hooks"]

# 合并: 对于每个 hook 事件，追加 herdr hook 条目（避免重复）
added = 0
for event, entries in template_hooks.items():
    if event not in target_hooks:
        target_hooks[event] = []
    existing_cmds = {e.get("command", "") for e in target_hooks[event]}
    for entry in entries:
        if entry.get("command", "") not in existing_cmds:
            target_hooks[event].append(entry)
            added += 1

# 写回
target_dir = os.path.dirname(target_path)
if target_dir and not os.path.exists(target_dir):
    os.makedirs(target_dir, exist_ok=True)

with open(target_path, 'w') as f:
    json.dump(target, f, indent=2, ensure_ascii=False)
    f.write('\n')

print(f"已添加 {added} 个 hook 条目到 {target_path}")
PYEOF
}

remove_hooks_json() {
  # 从目标 settings.json 中移除 reasonix-herdr 的 hook 条目
  # $1: 目标 settings.json 路径
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

# 移除 source 为 herdr:reasonix 的条目 — 通过 command 包含 herdr-agent-state 来判断
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

# 清理空的 hooks 键
if not target["hooks"]:
    del target["hooks"]

with open(target_path, 'w') as f:
    json.dump(target, f, indent=2, ensure_ascii=False)
    f.write('\n')

print(f"已从 {target_path} 移除 {removed} 个 hook 条目")
PYEOF
}

# ── 配置 hooks ──

configure_global() {
  step "4/4 配置全局 Reasonix hooks"

  local target="$HOME/.reasonix/settings.json"
  local hook_cmd
  hook_cmd=$(get_hook_command)

  info "目标: $target"
  info "Hook 命令: $hook_cmd"

  if $DRY_RUN; then
    dry "将把 hook 配置写入 $target"
    return 0
  fi

  merge_hooks_json "$target" "$hook_cmd"
  success "全局 hooks 配置完成"
}

configure_project() {
  step "4/4 配置项目级 Reasonix hooks"

  local project_dir="${PROJECT_DIR:-$PWD}"
  local target="$project_dir/.reasonix/settings.json"
  local hook_cmd
  hook_cmd=$(get_hook_command)

  info "项目目录: $project_dir"
  info "目标: $target"
  info "Hook 命令: $hook_cmd"

  if $DRY_RUN; then
    dry "将把 hook 配置写入 $target"
    return 0
  fi

  merge_hooks_json "$target" "$hook_cmd"
  success "项目级 hooks 配置完成"
}

# ── 交互式选择 ──

choose_scope() {
  if [ -n "$SCOPE" ]; then
    return 0
  fi

  echo ""
  echo -e "${BOLD}选择安装目标:${NC}"
  echo "  [1] 全局配置  (~/.reasonix/settings.json) — 所有项目生效 (推荐)"
  echo "  [2] 项目级配置 (.reasonix/settings.json) — 仅当前工作区生效"
  echo ""
  read -r -p "请输入 [1/2] (默认: 1): " choice
  choice="${choice:-1}"

  case "$choice" in
    1) SCOPE="global" ;;
    2) SCOPE="project" ;;
    *) error "无效选择: $choice"; exit 1 ;;
  esac
}

# ── 主流程 ──

main() {
  echo -e "${BOLD}${CYAN}"
  echo "╔══════════════════════════════════════╗"
  echo "║  reasonix-herdr  初始化安装         ║"
  echo "║  Reasonix → Herdr 状态桥接         ║"
  echo "╚══════════════════════════════════════╝"
  echo -e "${NC}"

  if $DRY_RUN; then
    warn "** DRY RUN 模式 ** — 不会做任何实际修改"
  fi

  check_prerequisites
  install_dependencies
  build
  choose_scope

  case "$SCOPE" in
    global)  configure_global ;;
    project) configure_project ;;
    *)       error "内部错误: SCOPE 未设置"; exit 1 ;;
  esac

  echo ""
  echo -e "${BOLD}${GREEN}╔══════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${GREEN}║  安装完成！                        ║${NC}"
  echo -e "${BOLD}${GREEN}╚══════════════════════════════════════╝${NC}"
  echo ""
  echo -e "下一步: ${BOLD}重启 Reasonix 桌面端${NC} 使配置生效（/new 不够）"
  echo ""
}

main
