# @sakurafan1023/mcp

大肥鱼 MCP 入口，适用于支持本地 stdio MCP 的 Host，例如 Codex。它与本机 QQ 客户端共用后台、配置和运行状态。

`0.3.0-preview.2` 配套 QQ npm 后台针对 macOS Apple Silicon（arm64，macOS 14 以上）与 Windows x64，需要 Node.js 22 以上和 npm；Windows 还需 Microsoft Visual C++ x64 运行库。安装 MCP 本身不会自动下载全套平台模块。发布进度见[发布说明](https://github.com/SAKURAfan1023/dafeiyu-bot/blob/main/docs/NPM_RELEASE.md)。

## 先安装 QQ 模块

```sh
npx --yes @sakurafan1023/cli@0.3.0-preview.2 setup qq
```

然后注册本地 MCP：

```sh
codex mcp add dafeiyu -- npx --yes @sakurafan1023/mcp@0.3.0-preview.2 --modules qq
```

其他本地 Host 可使用：

```json
{
  "mcpServers": {
    "dafeiyu": {
      "command": "npx",
      "args": ["--yes", "@sakurafan1023/mcp@0.3.0-preview.2", "--modules", "qq"]
    }
  }
}
```

Host 需要能找到 Node/npm。默认从 `~/.local/share/dafeiyu/modules` 加载已安装 QQ，可通过 `DAFEIYU_MODULES_DIR` 指定同一个稳定模块目录。用户数据不放在 npx 缓存；升级或清理缓存不应删除配置。

不希望依赖系统 Node 时，可使用仓库单独生成的[Mac 测试 ZIP](https://github.com/SAKURAfan1023/dafeiyu-bot/blob/main/docs/MACOS_MCP_TEST.md)。ChatGPT 网页不能直接使用本地 stdio 命令，远程连接另见该文档，不属于这条默认安装流程。

## 可用工具

| 工具 | 用途 |
| --- | --- |
| `qq_status` | 查看账号、连接、运行、额度和发送状态，默认不含记忆正文 |
| `qq_contacts` | 查看已核对账号的联系人及已配置会话 |
| `qq_save_connection` | 保存本机 OneBot 地址和预期账号，不连接 |
| `qq_manage_target` | 管理已知会话及人设 |
| `qq_settings` | 保存现有回复、记忆及图片工具设置 |
| `qq_run_control` | 暂停、断开，或按用户明确指令启动已保存范围 |
| `qq_memory` | 仅在用户要求时读取当前账号已保存的机器人记忆 |

写操作携带最近 `qq_status` 返回的账号、代次和配置版本。首次保存连接允许旧账号为空。旧配置在提交前被拒绝时返回 `QQ_STATE_CHANGED`、`submitted:false`；未确认的提交不能自动重试。

模型和 OneBot 凭证在本机面板配置，不传给 MCP Tool。接入 Host 不会连接 QQ 或开始回复；启动回复需要明确用户指令，默认 15 分钟。Host 退出不会杀共享后台或外部 NapCat，可在客户端断开后执行 `stop`。

不提供任意 OneBot 调用、脚本执行或直接发消息接口。

[完整使用说明](https://github.com/SAKURAfan1023/dafeiyu-bot/blob/main/docs/QQ_MODULES.md) · [反馈问题](https://github.com/SAKURAfan1023/dafeiyu-bot/issues)
