/**
 * eventToState 映射测试
 *
 * 验证 Reasonix hook 事件名到 herdr agent 状态的映射关系。
 * 这个映射是状态桥接的核心契约——任何变更都需要通过测试。
 */
import { describe, expect, test } from "bun:test";
import { eventToState } from "./types.js";

describe("eventToState", () => {
  // ── working 状态：agent 正在执行任务 ──

  test("SessionStart → working", () => {
    expect(eventToState("SessionStart")).toBe("working");
  });

  test("UserPromptSubmit → working", () => {
    expect(eventToState("UserPromptSubmit")).toBe("working");
  });

  test("PreToolUse → working", () => {
    expect(eventToState("PreToolUse")).toBe("working");
  });

  // ── blocked 状态：agent 被阻塞（等待用户审批等） ──

  test("Notification → blocked", () => {
    expect(eventToState("Notification")).toBe("blocked");
  });

  // ── idle 状态：会话暂停/结束，agent 空闲 ──

  test("Stop → idle", () => {
    expect(eventToState("Stop")).toBe("idle");
  });

  test("StopFailure → idle", () => {
    expect(eventToState("StopFailure")).toBe("idle");
  });

  // ── 未知事件 ──

  test("unknown event → null", () => {
    expect(eventToState("UnknownEvent")).toBeNull();
    expect(eventToState("PreToolUseFail")).toBeNull();
    expect(eventToState("")).toBeNull();
  });

  // ── 大小写敏感 ──

  test("case-sensitive: 'stop' ≠ 'Stop'", () => {
    expect(eventToState("stop")).toBeNull();
    expect(eventToState("sessionstart")).toBeNull();
  });

  // ── 覆盖所有已知事件 ──

  test("all known events have non-null mapping", () => {
    const known = [
      "SessionStart",
      "UserPromptSubmit",
      "PreToolUse",
      "Notification",
      "Stop",
      "StopFailure",
    ];
    for (const event of known) {
      expect(eventToState(event)).not.toBeNull();
    }
  });
});
