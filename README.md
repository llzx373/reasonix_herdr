# reasonix-herdr

> Reasonix → Herdr agent 状态桥接

在 Reasonix 中通过 hook 机制感知 AI agent 的生命周期事件（开始对话、使用工具、等待审批、完成工作），实时将状态同步到 herdr 终端界面，让你能够在 herdr 的工作区中直观地观察 Reasonix agent 的当前状态。

## 目录

- [新手入门](#新手入门)
- [工作原理](#工作原理)
- [Agent 状态映射](#agent-状态映射)
- [快速开始](#快速开始)
- [安装脚本](#安装脚本)
- [卸载](#卸载)
- [验证安装](#验证安装)
- [项目结构](#项目结构)
- [环境变量](#环境变量)
- [开发](#开发)
- [故障排查](#故障排查)
- [License](#license)

## 新手入门

### 这是什么？

`reasonix-herdr` 是一个轻量级中间件，让你在使用 Reasonix AI agent 时，herdr 终端能够实时显示 agent 的工作状态：

- 🟢 **idle** — agent 空闲，等待你的指令
- 🟡 **working** — agent 正在思考或执行工具
- 🔴 **blocked** — agent 需要你的审批（如工具调用确认）

### 我需要什么？

| 组件 | 最低版本 | 作用 |
|------|---------|------|
| [Reasonix](https://reasonix.ai) | 支持 hook | AI agent 平台 |
| [Herdr](https://herdr.io) | 0.7+ | 终端工作区管理 |
| [Bun](https://bun.sh) | 1.3+ | 构建工具（运行时零依赖） |

> **提示：** 如果你还没有 Bun，安装只需一行：`curl -fsSL https://bun.sh/install | bash`

### 三步上手

```bash
# 1. 克隆仓库
git clone git@github.com:llzx373/reasonix_herdr.git
cd reasonix_herdr

# 2. 一键安装（交互式）
./install.sh

# 3. 重启 Reasonix 桌面端，然后在 herdr 中启动 Reasonix 即可
```

安装脚本会自动完成：前置检查 → 安装依赖 → 编译二进制 → 配置 hook。你只需在提示时选择全局安装（推荐，所有 Reasonix 项目生效）或项目级安装。

详细说明见下方各节。

## 工作原理

```
┌──────────────┐    hook event     ┌───────────────────┐   Unix Socket   ┌─────────┐
│   Reasonix   │ ─── stdin JSON ──>│ herdr-agent-state  │ ── JSON-RPC ──>│  herdr  │
│   Agent      │                   │   (binary)         │                │  server │
└──────────────┘                   └───────────────────┘                └─────────┘
```

1. Reasonix 在 agent 生命周期关键节点触发 hook，通过 **stdin** 传入 JSON 格式的事件 payload
2. `herdr-agent-state` 二进制解析事件，将其映射为 agent 状态
3. 通过 **Unix Domain Socket** 向 herdr server 发送 JSON-RPC 风格的状态报告
4. herdr 终端界面实时更新显示 agent 状态

**关键设计原则：**
- **静默失败** — 任何异常都不会阻断 Reasonix 的正常工作流，所有错误静默处理
- **去重优化** — 连续相同状态不会重复报告，减少通信开销
- **零运行时依赖** — 构建产物是嵌入 Bun 运行时的独立二进制

## Agent 状态映射

| Reasonix Hook 事件   | Herdr 状态   | 说明                 |
|----------------------|-------------|---------------------|
| `SessionStart`       | `working`   | Agent 会话启动        |
| `UserPromptSubmit`   | `working`   | 用户提交了新提示词     |
| `PreToolUse`         | `working`   | Agent 正在使用工具     |
| `Notification`       | `blocked`   | Agent 等待用户审批     |
| `Stop` / `StopFailure` | `idle`    | 对话轮次结束          |

## 快速开始

### 前置条件

- [Reasonix](https://reasonix.ai)（支持 hook 功能）
- [Herdr](https://herdr.io) 0.7+（在 herdr 管理的 pane 中启动 Reasonix）
- [Bun](https://bun.sh) 1.3+（仅用于构建，运行时零依赖）

### 方式一：使用安装脚本（推荐）

```bash
# 交互式安装（会询问全局还是项目级）
./install.sh

# 或直接指定目标
./install.sh --global     # 全局安装，所有 Reasonix 项目生效
./install.sh --project    # 项目级安装，仅当前工作区生效
```

安装脚本会完成：
1. 检测前置条件（bun 或 node）
2. 安装依赖
3. 编译为独立二进制
4. 将 hook 配置写入对应的 `settings.json`

### 方式二：手动构建和配置

#### 1. 构建

```bash
git clone git@github.com:llzx373/reasonix_herdr.git
cd reasonix_herdr
bun install
bun run build
```

构建产物：`dist/herdr-agent-state`（原生 arm64 二进制，约 59MB，嵌入 bun 运行时，零外部依赖）。

#### 2. 配置 Reasonix Hook

将 `.reasonix/settings.json` 复制到你的 Reasonix 配置目录，并将 `{{HOOK_PATH}}` 替换为构建产物的实际路径。

**全局配置**（推荐，所有项目生效） — 编辑 `~/.reasonix/settings.json`：

```json
{
  "hooks": {
    "SessionStart": [
      { "command": "/path/to/reasonix_herdr/dist/herdr-agent-state", "timeout": 3000 }
    ],
    "UserPromptSubmit": [
      { "command": "/path/to/reasonix_herdr/dist/herdr-agent-state", "timeout": 3000 }
    ],
    "PreToolUse": [
      { "command": "/path/to/reasonix_herdr/dist/herdr-agent-state", "timeout": 3000 }
    ],
    "Notification": [
      { "command": "/path/to/reasonix_herdr/dist/herdr-agent-state", "timeout": 3000 }
    ],
    "Stop": [
      { "command": "/path/to/reasonix_herdr/dist/herdr-agent-state", "timeout": 3000 }
    ],
    "StopFailure": [
      { "command": "/path/to/reasonix_herdr/dist/herdr-agent-state", "timeout": 3000 }
    ]
  }
}
```

**项目级配置** — 将上述内容放入你的项目 `<workspace>/.reasonix/settings.json`。

#### 3. 重启 Reasonix

配置生效需要**重启 Reasonix 桌面端**（仅 `/new` 重新加载会话是不够的）。

## 安装脚本

### 用法

```bash
./install.sh [选项]
```

### 选项

| 选项 | 说明 |
|------|------|
| `--global` | 配置全局 Reasonix hooks（`~/.reasonix/settings.json`） |
| `--project` | 配置当前工作区项目级 hooks |
| `--project-dir <路径>` | 配置指定目录的项目级 hooks |
| `--skip-build` | 跳过构建步骤（假设已构建） |
| `--dry-run` | 仅预览将要执行的操作，不做实际修改 |
| `-h, --help` | 显示帮助信息 |

### 示例

```bash
# 预览安装步骤（不实际执行）
./install.sh --dry-run

# 全局安装，跳过构建（已手动构建过）
./install.sh --global --skip-build

# 为新项目配置 hook
./install.sh --project-dir /path/to/my-reasonix-project
```

## 卸载

```bash
# 交互式卸载（会询问清理范围）
./uninstall.sh

# 完全清理（hooks + 构建产物 + 依赖）
./uninstall.sh --all
```

卸载脚本会自动从你的 `settings.json` 中移除 herdr hook 条目，不会影响其他 hook 配置。

## 验证安装

安装完成后，在 herdr 终端中启动 Reasonix，验证状态同步是否正常：

```bash
# 查看 agent 列表
herdr agent list

# 查看实时快照
herdr api snapshot
```

正常工作时，你会看到 agent 状态在 `idle`、`working`、`blocked` 之间切换。

## 项目结构

```
reasonix_herdr/
├── src/
│   ├── index.ts           # 入口：stdin 解析 + 事件分发 + 主逻辑
│   ├── types.ts           # 类型定义 + 事件→状态映射
│   ├── herdr-socket.ts    # herdr Unix Socket 客户端 (fire-and-forget)
│   └── reporter.ts        # 状态报告器（去重、序列号、session 管理）
├── .reasonix/
│   └── settings.json      # Reasonix hook 配置模板 (含 {{HOOK_PATH}} 占位符)
├── dist/
│   └── herdr-agent-state  # 构建产物：独立二进制
├── install.sh             # 安装脚本
├── uninstall.sh           # 卸载脚本
├── package.json           # 项目配置与构建脚本
├── tsconfig.json          # TypeScript 配置
├── reasonix.toml          # Reasonix 项目权限配置
└── README.md
```

### 源文件职责

| 文件 | 职责 |
|------|------|
| `index.ts` | 入口点：解析 stdin JSON payload，检测 herdr 环境，调用事件映射和报告。异常全部静默处理，绝不阻断 Reasonix 工作流 |
| `types.ts` | `HookPayload` 联合类型（6 种事件）、`AgentState` 枚举、`eventToState()` 映射函数 |
| `herdr-socket.ts` | Unix Domain Socket 客户端：500ms 超时、fire-and-forget 模式 |
| `reporter.ts` | 状态报告器：全局序列号、重复状态去重、session 变化检测 |

## 环境变量

Hook 脚本依赖 herdr 自动注入的环境变量：

| 变量 | 说明 |
|------|------|
| `HERDR_ENV` | 必须为 `"1"` 才激活此桥接器；非 herdr 环境静默退出（退出码 0） |
| `HERDR_SOCKET_PATH` | herdr Unix socket 路径 |
| `HERDR_PANE_ID` | 当前 pane ID |

这些变量由 herdr 在启动终端 pane 中的进程时自动注入，无需手动设置。

## 开发

```bash
# 安装依赖
bun install

# TypeScript 类型检查
bun run typecheck

# 构建为独立二进制
bun run build

# 清理构建产物
bun run clean
```

### 技术栈

| 层面 | 技术 |
|------|------|
| 语言 | TypeScript (ES2022, strict mode) |
| 运行时 | Bun 1.3+（构建为原生二进制） |
| 构建 | `bun build --compile` → 独立 arm64 二进制 |
| 类型检查 | `tsc --noEmit` |
| 通信协议 | stdin JSON + Unix Domain Socket (JSON-RPC) |

## 故障排查

### hook 未生效，herdr 中看不到 agent 状态

1. **确认已重启 Reasonix 桌面端** — 仅 `/new` 重新加载会话不会重新加载 hook 配置，必须完全退出并重启桌面端
2. **检查 HERDR_ENV** — 确保在 herdr 的 pane 中启动 Reasonix，而非系统终端
3. **验证 hook 路径** — 检查 `settings.json` 中的 `command` 路径是否正确指向 `dist/herdr-agent-state`。可以手动运行 `ls -la /path/to/dist/herdr-agent-state` 确认文件存在且可执行
4. **检查 socket** — 确认 `HERDR_SOCKET_PATH` 指向的 socket 文件存在：`ls -la $HERDR_SOCKET_PATH`

### 构建失败

```bash
# 确保 bun 版本 >= 1.3
bun --version

# 如果版本过低，更新 bun
bun upgrade

# 清理后重新构建
bun run clean
bun install
bun run build
```

### 安装脚本报错

```bash
# 先用 dry-run 预览，确认没有意外
./install.sh --dry-run

# 如果遇到 JSON 合并错误，检查目标 settings.json 是否合法
python3 -m json.tool ~/.reasonix/settings.json
```

### 手动测试 hook 脚本

```bash
# 模拟 herdr 环境运行 hook 二进制
HERDR_ENV=1 HERDR_SOCKET_PATH=/tmp/herdr.sock HERDR_PANE_ID=test \
  echo '{"hook_event_name":"SessionStart","session_id":"test"}' | \
  ./dist/herdr-agent-state
```

如果没有报错（静默退出），说明 hook 脚本本身工作正常。

## License

MIT
