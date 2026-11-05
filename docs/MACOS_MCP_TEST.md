# 大肥鱼 macOS MCP 独立测试版

版本 `0.3.0-preview.1`。这是单独生成的 Mac 测试包，包含 QQ 原生后台、Node.js、MCP SDK、客户端和所需 npm 依赖；运行时不需要 npm 下载，也不需要 Swift。当前构建针对 Apple Silicon arm64，不能代替 Intel Mac 或 Windows 的验证。

默认测试数据位于 `~/Library/Application Support/DaFeiYuMCPTest`，与原客户端、正式 QQ 配置分开。打开入口不会连接 QQ 或启动自动回复，环境中的 OneBot/模型密钥不会被启动脚本带入。不要在本测试包中配置真实账号，自动验收只使用本机合成夹具。

## 使用本地包

解压 `dafeiyu-macos-mcp-arm64-0.3.0-preview.1.zip`，保留整个 `dafeiyu-qq-macos-test` 文件夹。建议将它放入用户 Applications 目录，例如 `~/Applications/DaFeiYuMCPTest-0.3.0-preview.1`。目录可以包含中文或空格，不要只移动某个脚本或可执行文件。原生应用从桌面源码目录启动子程序时观察到加载受阻，移到 Applications 后可正常加载；无需为此扩大文件访问权限。

- 双击 `DaFeiYu MCP Test.app` 打开独立原生 QQ 窗口，应用标识与已有客户端分开。
- `bin/client.command` 提供浏览器入口，QQ 包只显示实际安装的 QQ 页面，不显示未安装的社交/微信入口。
- `/bin/bash "<测试包>/bin/client.command" status` 查看同一个后台。
- `/bin/bash "<测试包>/bin/client.command" disconnect` 断开，确认空闲后使用 `stop` 退出后台。
- `bin/mcp.sh` 为 stdio 入口，交给 MCP Host 启动，不要把其 stdout 当普通终端日志。

后台不随 MCP Host 退出而结束，客户端与 MCP 使用同一份测试配置和后台 PID。所有用户测试数据保存在上述独立目录，不进入插件 ZIP。

## 接入桌面 MCP Host

包内 `plugin.json` / `mcp.json` 使用 Agent Plugins 格式，stdio 命令为 `/bin/bash ${PLUGIN_ROOT}/bin/mcp.sh`。通过支持本地插件的桌面 Host 导入整个目录，或手动添加以下 MCP 配置（把路径替换为解压位置）：

```json
{
  "mcpServers": {
    "dafeiyu-qq-macos-test": {
      "command": "/bin/bash",
      "args": ["<测试包的绝对路径>/bin/mcp.sh"]
    }
  }
}
```

若使用 Codex CLI，可运行 `codex mcp add dafeiyu_mac_test -- /bin/bash "<测试包>/bin/mcp.sh"`。这只注册桌面 MCP 连接，不等于 ChatGPT 已完成工具调用。测试结束可用 `codex mcp remove dafeiyu_mac_test` 移除此测试连接。

ChatGPT 桌面本地插件能力取决于实际账号、客户端和工作区支持；公开本地插件提交另有上游权限要求，本测试不提交插件商店。

## 接入 ChatGPT 网页

ChatGPT 自定义 MCP 使用 Streamable HTTP / SSE，不能把 stdio 的本地文件路径直接填入 Server URL。

本包另提供 `bin/http.command`：只监听 `127.0.0.1`，使用随机私有路径，在 stderr/终端显示当次 MCP URL。无固定路径 `/mcp`；其他 Host/Origin 和大于 64 KiB 的请求会被拒绝。该入口仅供隔离测试，不能直接绑定公网或当作生产远程服务。

ChatGPT 网页需要经过受支持的远程连接，例如官方 Secure MCP Tunnel。官方 tunnel-client 也支持直接连接本包 stdio 入口，不必开启 HTTP。创建/关联隧道需要目标 OpenAI 组织和 ChatGPT 工作区权限；不要把本地路径或本机 127.0.0.1 地址当作已可被 ChatGPT 云端访问。

实际添加和调用需要可操作的 ChatGPT 会话。本轮 ChatGPT 浏览器操作仍被 Work 设置阻止，已按用户要求改为 Codex 新窗口原生 MCP 验收。Codex 新窗口已实际完成原生读状态、保存合成账号与暂停，客户端同步显示账号 `12345` 和测试地址。旧配置拒绝提示已增加 `QQ_STATE_CHANGED` / `submitted:false`，新包 SDK 复验通过；旧会话缓存原 MCP 子进程，新窗口的该错误分支原生复验仍需宿主写操作确认。SDK 通信检查与实际 Host 调用分别记录，不能互相替代。

官方说明：[自定义 MCP](https://developers.openai.com/api/docs/guides/custom-mcp-server)、[Secure MCP Tunnel](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels)、[桌面本地插件](https://developers.openai.com/plugins/deploy/desktop-only)。

## 建议的 ChatGPT 验收提示

“只使用大肥鱼 Mac 测试版，先调用 qq_status，报告后台 PID、账号、连接状态和运行状态；不要连接 QQ 或开始回复。”

随后用测试账号 `12345` 和本机合成 OneBot 地址保存连接配置，再次读取状态，最后暂停。必须使用最新状态里的账号、代次和配置版本。打开本机客户端，核对它显示相同测试账号与后台状态。不得把合成测试身份和模拟收发当成真实 QQ 消息验收。

## 从源码生成

```sh
npm ci --ignore-scripts
npm run build:macos-mcp
npm run test:macos-mcp
```

构建产物独立放在 `dist/macos-mcp-<架构>/`，ZIP 位于 `dist/`，不覆盖 `dist/qq`、`dist/npm` 或 Windows 产物。依赖的许可证随包保留。源码工作区无需提交或推送即可生成本地测试包。
