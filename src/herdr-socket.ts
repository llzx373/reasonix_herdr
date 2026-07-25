/**
 * herdr Unix Socket 客户端
 *
 * 通过 HERDR_SOCKET_PATH 环境变量指定的 Unix domain socket
 * 向 herdr server 发送 agent 状态报告。
 *
 * 通信协议：每行一个 JSON 请求，无响应解析（fire-and-forget）。
 */

import * as net from "node:net";
import type { HerdrRequest } from "./types.js";

/** Socket 连接超时 (ms) */
const SOCKET_TIMEOUT = 500;

/** 平台相关的 socket 端点前缀 */
function socketEndpoint(socketPath: string): string {
  if (process.platform === "win32") {
    return `\\\\.\\pipe\\${socketPath}`;
  }
  return socketPath;
}

/**
 * 向 herdr server 发送单个 JSON-RPC 风格的请求。
 * 采用 fire-and-forget 模式：连接 → 写入 → 等待响应或超时 → 断开。
 * 无论成功与否均静默处理（herdr 不是关键路径，不应阻断 Reasonix 的工作流）。
 */
export function sendRequest(request: HerdrRequest): Promise<void> {
  const socketPath = process.env.HERDR_SOCKET_PATH;
  if (!socketPath) {
    return Promise.resolve();
  }

  return new Promise<void>((resolve) => {
    const endpoint = socketEndpoint(socketPath);

    const client = net.createConnection(endpoint, () => {
      client.write(`${JSON.stringify(request)}\n`);
    });

    const finish = () => {
      client.destroy();
      resolve();
    };

    client.setTimeout(SOCKET_TIMEOUT, finish);
    client.on("data", finish);
    client.on("error", finish);
    client.on("end", finish);
    client.on("close", resolve);
  });
}
