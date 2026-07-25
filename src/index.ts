/**
 * reasonix-herdr — Reasonix → herdr Agent 状态桥接
 *
 * 作为 Reasonix hook 脚本运行，通过 stdin 接收 hook payload (JSON)，
 * 将 AI agent 生命周期事件转换为 herdr agent 状态报告，
 * 通过 herdr Unix Socket API 发送。
 *
 * 使用方式 (在 .reasonix/settings.json 中配置):
 *   "command": "node /path/to/herdr-agent-state.mjs"
 *
 * 环境变量 (由 herdr 注入):
 *   HERDR_ENV=1            — 标识在 herdr 环境中运行
 *   HERDR_SOCKET_PATH      — herdr Unix socket 路径
 *   HERDR_PANE_ID          — 当前 pane 的 ID
 */

import { readFileSync } from "node:fs";
import { eventToState } from "./types.js";
import type { HookPayload } from "./types.js";
import { reportSession, reportState } from "./reporter.js";

// ── 环境检查 ──

function isHerdrEnv(): boolean {
  return (
    process.env.HERDR_ENV === "1" &&
    !!process.env.HERDR_SOCKET_PATH &&
    !!process.env.HERDR_PANE_ID
  );
}

// ── stdin 读取 ──

function readPayload(): HookPayload | null {
  try {
    const raw = readFileSync(0, "utf8").trim(); // fd 0 = stdin
    if (!raw) return null;
    return JSON.parse(raw) as HookPayload;
  } catch {
    return null;
  }
}

// ── 主逻辑 ──

async function main(): Promise<void> {
  // 非 herdr 环境静默退出
  if (!isHerdrEnv()) {
    process.exit(0);
  }

  // 读取并解析 stdin hook payload
  const payload = readPayload();
  if (!payload) {
    process.exit(0);
  }

  const { event, sessionId } = payload;

  // 确定目标状态
  const state = eventToState(event);
  if (state === null) {
    process.exit(0);
  }

  // SessionStart 时先报告 session
  if (event === "SessionStart") {
    await reportSession(sessionId, "new");
  }

  // 报告状态
  await reportState(state, sessionId);

  // 总是成功退出 —— hook 不应阻断 Reasonix 工作流
  process.exit(0);
}

main().catch(() => {
  // 任何异常都静默退出，不阻断 Reasonix
  process.exit(0);
});
