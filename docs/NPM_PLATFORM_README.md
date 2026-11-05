# {{PACKAGE_NAME}}

大肥鱼 QQ 的 {{PLATFORM}} 原生后台，版本 `0.3.0-preview.2`。

这个包由 `@sakurafan1023/qq` 按平台选择。需要客户端或 MCP 时安装对应入口，不直接运行本包：

```sh
npx --yes @sakurafan1023/cli@0.3.0-preview.2 setup qq
npx --yes @sakurafan1023/cli@0.3.0-preview.2 qq panel
```

本次预览针对 macOS Apple Silicon（arm64，macOS 14 以上）与 Windows x64；发布前需完成对应平台构建和安装验证。QQ / NapCat 由用户单独准备，本包不包含它们或虚拟机，也不自动连接、扫码登录或开始回复。

包含 QQ 可执行文件、QQ 控制页与示例表情资源、版本清单、SHA-256 清单及许可证。不包含微信、社交浏览器、账号配置、聊天、记忆或令牌。

代码采用 MIT；图片与第三方运行库分别遵循包内 `THIRD_PARTY_NOTICES.md`、`Resources/` 与 `licenses/` 中的许可，不因本项目 MIT 而改变。

[完整使用说明](https://github.com/SAKURAfan1023/dafeiyu-bot/blob/main/docs/QQ_MODULES.md) · [问题反馈](https://github.com/SAKURAfan1023/dafeiyu-bot/issues)
