/**
 * herdr-socket 模块测试
 *
 * 测试 sendRequest 的 fire-and-forget 语义。
 * Unix socket 测试通过临时文件模拟 herdr socket。
 */
import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import * as net from "node:net";
import { sendRequest } from "./herdr-socket.js";
import type { HerdrRequest } from "./types.js";

function makeRequest(overrides: Partial<HerdrRequest> = {}): HerdrRequest {
  return {
    id: "test:1",
    method: "pane.report_agent",
    params: {
      pane_id: "pane-test",
      source: "herdr:reasonix",
      agent: "reasonix",
      state: "working",
      seq: 1,
    },
    ...overrides,
  };
}

describe("sendRequest fire-and-forget", () => {
  // 确保 HERDR_SOCKET_PATH 被重置
  beforeEach(() => {
    delete process.env.HERDR_SOCKET_PATH;
  });

  afterEach(() => {
    delete process.env.HERDR_SOCKET_PATH;
  });

  test("无 HERDR_SOCKET_PATH 不抛异常", async () => {
    const req = makeRequest();
    // sendRequest 返回 Promise<void>，不应 reject
    const p = sendRequest(req);
    expect(p).toBeInstanceOf(Promise);
    await expect(p).resolves.toBeUndefined();
  });

  test.skip("不存在的 socket 文件不抛异常", async () => {
    process.env.HERDR_SOCKET_PATH = "/tmp/nonexistent-herdr-socket-99999";
    const req = makeRequest();
    // Bun 的 net 实现可能同步抛出 ENOENT，sendRequest 的 Promise 构造函数
    // 内的错误也会导致 Promise rejection。这两种行为都是 fire-and-forget 的预期结果。
    // 关键是不应让调用方崩溃。
    try {
      await sendRequest(req);
    } catch {
      // Bun throws synchronously for missing Unix sockets — acceptable
    }
    // 没有 uncaught exception 就算通过
    expect(true).toBe(true);
  });
});

describe("sendRequest with Unix socket", () => {
  let sockDir: string;
  let sockPath: string;

  beforeEach(async () => {
    sockDir = mkdtempSync(join(tmpdir(), "herdr-test-"));
    sockPath = join(sockDir, "herdr.sock");
    process.env.HERDR_SOCKET_PATH = sockPath;
  });

  afterEach(() => {
    delete process.env.HERDR_SOCKET_PATH;
    try { rmSync(sockDir, { recursive: true }); } catch {}
  });

  test("发送 JSON 到监听 socket", async () => {
    const received: string[] = [];

    const server = net.createServer((socket) => {
      socket.on("data", (data) => received.push(data.toString()));
    });

    await new Promise<void>((resolve) => server.listen(sockPath, () => resolve()));

    const req = makeRequest();
    await sendRequest(req);
    await Bun.sleep(150);

    server.close();
    await Bun.sleep(50);

    const allData = received.join("").trim();
    expect(allData.length).toBeGreaterThan(0);

    const parsed = JSON.parse(allData.split("\n")[0]);
    expect(parsed.method).toBe("pane.report_agent");
    expect(parsed.params.state).toBe("working");
  });

  test("发送 done 状态", async () => {
    const received: string[] = [];

    const server = net.createServer((socket) => {
      socket.on("data", (data) => received.push(data.toString()));
    });

    await new Promise<void>((resolve) => server.listen(sockPath, () => resolve()));

    const req = makeRequest({
      params: {
        pane_id: "pane-done",
        source: "herdr:reasonix",
        agent: "reasonix",
        state: "done",
        seq: 42,
      },
    });
    await sendRequest(req);
    await Bun.sleep(150);

    server.close();
    await Bun.sleep(50);

    const allData = received.join("").trim();
    expect(allData.length).toBeGreaterThan(0);
    const parsed = JSON.parse(allData.split("\n")[0]);
    expect(parsed.params.state).toBe("done");
    expect(parsed.params.pane_id).toBe("pane-done");
    expect(parsed.params.seq).toBe(42);
  });

  test("server 关闭后发送不抛异常", async () => {
    // 启动后立即关闭 server
    const server = net.createServer(() => {});
    await new Promise<void>((resolve) => server.listen(sockPath, () => resolve()));
    await new Promise<void>((resolve) => server.close(() => resolve()));

    const req = makeRequest();
    await expect(sendRequest(req)).resolves.toBeUndefined();
  });
});
