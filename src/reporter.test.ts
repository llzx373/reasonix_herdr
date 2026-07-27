/**
 * reporter 模块测试
 *
 * 验证状态报告的发送逻辑：去重、session 切换、序列号递增。
 * 使用 spyOn 监视 sendRequest 调用。
 */
import { afterEach, beforeEach, describe, expect, spyOn, test } from "bun:test";
import { reportSession, reportState, reset } from "./reporter.js";
import * as socket from "./herdr-socket.js";

// Spy sendRequest 但不阻止实际调用（无 HERDR_SOCKET_PATH 时静默）
const sendSpy = spyOn(socket, "sendRequest");

beforeEach(() => {
  process.env.HERDR_PANE_ID = "pane-test-001";
  // 确保无 socket 路径，避免真实连接
  delete process.env.HERDR_SOCKET_PATH;
  reset();
  sendSpy.mockClear();
});

afterEach(() => {
  delete process.env.HERDR_PANE_ID;
});

describe("reportState", () => {
  test("发送 working 状态（参数正确）", async () => {
    await reportState("working", "session-1");

    expect(sendSpy).toHaveBeenCalledTimes(1);
    const req = sendSpy.mock.calls[0][0];
    expect(req.method).toBe("pane.report_agent");
    expect(req.params.state).toBe("working");
    expect(req.params.agent_session_id).toBe("session-1");
    expect(req.params.pane_id).toBe("pane-test-001");
  });

  test("去重：连续相同状态不重复发送", async () => {
    await reportState("working", "session-1");
    await reportState("working", "session-1");
    await reportState("working", "session-1");

    expect(sendSpy).toHaveBeenCalledTimes(1);
  });

  test("状态变化时发送", async () => {
    await reportState("idle", "session-1");
    await reportState("working", "session-1");
    await reportState("blocked", "session-1");
    await reportState("idle", "session-1");

    expect(sendSpy).toHaveBeenCalledTimes(4);
  });

  test("相同状态但不同 session 时发送", async () => {
    await reportState("working", "session-1");
    await reportState("working", "session-2");

    expect(sendSpy).toHaveBeenCalledTimes(2);
  });

  test("seq 单调递增", async () => {
    await reportState("idle", "s1");
    await reportState("working", "s1");
    await reportState("blocked", "s2");
    await reportState("idle", "s2");

    const seqs = sendSpy.mock.calls.map((c) => (c[0] as any).params.seq);
    for (let i = 1; i < seqs.length; i++) {
      expect(seqs[i]).toBeGreaterThan(seqs[i - 1]);
    }
  });

  test("无 HERDR_PANE_ID 时静默跳过", async () => {
    delete process.env.HERDR_PANE_ID;
    reset();

    await reportState("working", "s1");
    expect(sendSpy).toHaveBeenCalledTimes(0);
  });
});

describe("reportSession", () => {
  test("发送新 session", async () => {
    await reportSession("session-new", "new");

    expect(sendSpy).toHaveBeenCalledTimes(1);
    const req = sendSpy.mock.calls[0][0];
    expect(req.method).toBe("pane.report_agent_session");
    expect(req.params.agent_session_id).toBe("session-new");
  });

  test("相同 session 去重", async () => {
    await reportSession("s1");
    await reportSession("s1");
    await reportSession("s1");

    expect(sendSpy).toHaveBeenCalledTimes(1);
  });

  test("session 切换时发送", async () => {
    await reportSession("s1");
    await reportSession("s2");
    await reportSession("s3");

    expect(sendSpy).toHaveBeenCalledTimes(3);
  });
});
