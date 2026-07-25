/**
 * 状态报告器
 *
 * 将 Reasonix hook 事件转换为 herdr agent 状态报告，
 * 管理 session ID 和序列号，去重连续重复状态。
 */

import { sendRequest } from "./herdr-socket.js";
import type {
  AgentState,
  HerdrReportAgentParams,
  HerdrReportSessionParams,
} from "./types.js";

/** 集成标识 */
const SOURCE = "herdr:reasonix";
const AGENT = "reasonix";

/** 全局序列号（单调递增，基于启动时间戳） */
let reportSeq = Date.now() * 1000;

/** 最近一次报告的状态，用于去重 */
let lastReportedState: AgentState | null = null;

/** 最近一次报告的 session ID，用于检测 session 切换 */
let lastReportedSessionId: string | null = null;

function nextSeq(): number {
  reportSeq += 1;
  return reportSeq;
}

function paneId(): string | undefined {
  return process.env.HERDR_PANE_ID;
}

/**
 * 报告 agent session ID 到 herdr。
 * 当 session 发生变化时调用。
 */
export async function reportSession(
  sessionId: string,
  sessionStartSource?: "new",
): Promise<void> {
  const pid = paneId();
  if (!pid) return;

  if (sessionId === lastReportedSessionId) return;
  lastReportedSessionId = sessionId;

  const params: HerdrReportSessionParams = {
    pane_id: pid,
    source: SOURCE,
    agent: AGENT,
    agent_session_id: sessionId,
    seq: nextSeq(),
  };
  if (sessionStartSource) {
    params.session_start_source = sessionStartSource;
  }

  await sendRequest({
    id: `${SOURCE}:${Date.now()}:${Math.random().toString(36).slice(2, 8)}`,
    method: "pane.report_agent_session",
    params,
  });
}

/**
 * 报告 agent 状态到 herdr。
 * 自动去重：连续相同的状态不会重复发送。
 */
export async function reportState(
  state: AgentState,
  sessionId?: string,
): Promise<void> {
  const pid = paneId();
  if (!pid) return;

  // 去重连续重复状态
  if (state === lastReportedState && sessionId === lastReportedSessionId) return;
  lastReportedState = state;

  const params: HerdrReportAgentParams = {
    pane_id: pid,
    source: SOURCE,
    agent: AGENT,
    state,
    seq: nextSeq(),
  };
  if (sessionId) {
    params.agent_session_id = sessionId;
  }

  await sendRequest({
    id: `${SOURCE}:${Date.now()}:${Math.random().toString(36).slice(2, 8)}`,
    method: "pane.report_agent",
    params,
  });
}

/**
 * 重置内部状态（用于测试或重新初始化）
 */
export function reset(): void {
  lastReportedState = null;
  lastReportedSessionId = null;
}
