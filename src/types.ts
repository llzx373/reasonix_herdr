/**
 * Reasonix Hook 载荷类型定义
 *
 * Reasonix 通过 stdin 向 hook 脚本发送一行 JSON payload，
 * 公共字段为 event / sessionId / cwd，各事件有各自的扩展字段。
 */

// ── 公共字段 ──

export interface HookPayloadBase {
  event: string;
  sessionId: string;
  cwd: string;
}

// ── 各事件载荷 ──

export interface SessionStartPayload extends HookPayloadBase {
  event: "SessionStart";
}

export interface UserPromptSubmitPayload extends HookPayloadBase {
  event: "UserPromptSubmit";
  prompt: string;
  turn: number;
}

export interface PreToolUsePayload extends HookPayloadBase {
  event: "PreToolUse";
  toolName: string;
  toolArgs: Record<string, unknown>;
}

export interface NotificationPayload extends HookPayloadBase {
  event: "Notification";
  message: string;
  notificationType: string;
  isInterrupt: boolean;
}

export interface StopPayload extends HookPayloadBase {
  event: "Stop";
  lastAssistantText: string;
  turn: number;
}

/** 所有已知 hook 载荷的联合类型 */
export type HookPayload =
  | SessionStartPayload
  | UserPromptSubmitPayload
  | PreToolUsePayload
  | NotificationPayload
  | StopPayload;

// ── herdr 状态 ──

/**
 * herdr agent 状态枚举
 *
 * - idle:    agent 空闲，等待用户输入
 * - working: agent 正在执行任务
 * - blocked: agent 被阻塞（如等待用户审批）
 * - done:    agent 任务完成（终端状态）
 */
export type AgentState = "idle" | "working" | "blocked" | "done";

// ── herdr Socket API ──

export interface HerdrRequest {
  id: string;
  method: "pane.report_agent" | "pane.report_agent_session";
  params: HerdrReportAgentParams | HerdrReportSessionParams;
}

export interface HerdrReportAgentParams {
  pane_id: string;
  source: string;
  agent: string;
  state: AgentState;
  seq: number;
  agent_session_id?: string;
}

export interface HerdrReportSessionParams {
  pane_id: string;
  source: string;
  agent: string;
  agent_session_id: string;
  seq: number;
  session_start_source?: string;
}

// ── 事件到状态的映射 ──

/**
 * 将 Reasonix hook 事件名映射为 herdr agent 状态
 */
export function eventToState(event: string): AgentState | null {
  switch (event) {
    case "SessionStart":
    case "UserPromptSubmit":
    case "PreToolUse":
      return "working";
    case "Notification":
      return "blocked";
    case "Stop":
    case "StopFailure":
      return "idle";
    default:
      return null;
  }
}
