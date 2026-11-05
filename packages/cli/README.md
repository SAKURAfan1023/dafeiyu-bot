# @sakurafan1023/cli

大肥鱼的按需安装与客户端入口。基础包只带启动命令，选择 QQ 后才下载 QQ 模块和匹配平台的后台。

`0.3.0-preview.2` 为首批预览版本，计划发布 macOS Apple Silicon（arm64，macOS 14 以上）与 Windows x64。需要 Node.js 22 以上和 npm。发布进度见[仓库发布说明](https://github.com/SAKURAfan1023/dafeiyu-bot/blob/main/docs/NPM_RELEASE.md)。

## 安装 QQ，再打开客户端

```sh
npx --yes @sakurafan1023/cli@0.3.0-preview.2 setup qq
npx --yes @sakurafan1023/cli@0.3.0-preview.2 qq panel
```

安装向导使用固定版本、禁用安装脚本，默认将模块放在 `~/.local/share/dafeiyu/modules`。它不会安装 QQ、NapCat、微信、社交浏览器或虚拟机，也不会登录账号或开始回复。运行向导请使用上面的 npx 命令；全局安装后直接执行 `dafeiyu setup qq` 不属于本版安装流程。

注意：`dafeiyu` 是安装后的命令名。请使用完整的 `@sakurafan1023/cli` 包名，不要运行 `npx dafeiyu`，后者会解析到另一个 npm 包。

## 常用操作

```sh
npx --yes @sakurafan1023/cli@0.3.0-preview.2 qq status
npx --yes @sakurafan1023/cli@0.3.0-preview.2 qq pause
npx --yes @sakurafan1023/cli@0.3.0-preview.2 qq disconnect
npx --yes @sakurafan1023/cli@0.3.0-preview.2 qq stop
```

`status` 查看状态；`pause` 暂停回复；`disconnect` 断开 QQ；`stop` 仅在后台已断开且空闲时退出。关闭网页或 MCP Host 不会退出共享后台。

`DAFEIYU_MODULES_DIR` 可指定稳定模块目录；`DAFEIYU_DATA_DIR` 可指定私有数据目录。不要将用户数据放进 npx 缓存或安装包。macOS 默认数据与现有大肥鱼客户端一致，位于 `~/Library/Application Support/WeChatAIBot`；独立 Mac 测试 ZIP 使用另一份测试目录。

需要 MCP 时，在装好 QQ 后使用同版本的 [`@sakurafan1023/mcp`](https://github.com/SAKURAfan1023/dafeiyu-bot/tree/main/packages/mcp)。其他平台可参考源码构建说明，尚未作为本版 npm 支持平台发布。

[完整安装与功能说明](https://github.com/SAKURAfan1023/dafeiyu-bot/blob/main/docs/QQ_MODULES.md) · [反馈问题](https://github.com/SAKURAfan1023/dafeiyu-bot/issues)
