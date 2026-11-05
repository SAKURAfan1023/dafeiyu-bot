# @sakurafan1023/qq

QQ 独立模块：复用大肥鱼现有 Swift 引擎，提供本机客户端和共享后台。文字回复、群聊规则、人设、记忆、表情及图片工具沿用原实现。

`0.3.0-preview.2` 的 npm 原生后台针对 macOS Apple Silicon（arm64，macOS 14 以上）与 Windows x64，需要 Node.js 22 以上和 npm。版本为预览版，外部 QQ / NapCat、模型与图片服务需要自行配置，换机和长期运行仍需验收。发布状态见[发布说明](https://github.com/SAKURAfan1023/dafeiyu-bot/blob/main/docs/NPM_RELEASE.md)。

## 推荐安装

```sh
npx --yes @sakurafan1023/cli@0.3.0-preview.2 setup qq
npx --yes @sakurafan1023/cli@0.3.0-preview.2 qq panel
```

向导只下载 QQ 和本机架构后台。Windows x64 需要 Windows 10/11、Visual C++ x64 运行库；图片分析另需 Python 与 Pillow，可通过 DAFEIYU_PYTHON 指定 python.exe。打开面板后，先保存 OneBot 本机地址和预期账号，再输入凭证、连接核对、添加会话、保存范围，最后按需要启动回复。接入环境部署见[Mac 快速开始](https://github.com/SAKURAfan1023/dafeiyu-bot/blob/main/docs/QUICKSTART.md)。

本模块不包含 QQ 客户端、NapCat、虚拟机、微信或社交浏览器，不会因为安装或打开面板就登录或回复。

## 自行安装到项目

```sh
npm install @sakurafan1023/qq@0.3.0-preview.2
npx dafeiyu-qq panel
```

请保留可选依赖，平台后台通过它安装；不要在普通 npm 安装时加 `--omit=optional`。同时显式安装本地平台 tarball 的离线测试流程另见仓库文档。

`dafeiyu-qq` 支持 `panel`、`status`、`connect`、`pause`、`disconnect`、`stop`。`connect` 只使用已保存配置；令牌和模型密钥在面板输入，也可从 `DAFEIYU_ONEBOT_TOKEN` / `DAFEIYU_MODEL_KEY` 环境变量读取，不接受命令行令牌参数。

## 后台与数据

客户端和 [`@sakurafan1023/mcp`](https://github.com/SAKURAfan1023/dafeiyu-bot/tree/main/packages/mcp) 通过私有发现记录共用一个后台，版本、账号与配置发生变化时会拒绝旧操作。发送结果未知时不自动重试。

macOS 默认数据目录为 `~/Library/Application Support/WeChatAIBot`。如需隔离，设置 `DAFEIYU_DATA_DIR` 为专用私有目录。已有较旧客户端时先退出再使用新版入口，避免同时运行两套执行者。后台退出不重放历史任务，重启不会自动连接或开始回复。

Intel Mac、Linux 和 Windows ARM64 不在本版 npm 发布范围内。Windows x64 的构建与安装结果见发布记录，不把 Mac 通过写成 Windows 验收。内置表情和第三方组件遵循各自许可，详见平台包内第三方声明。

[分包说明](https://github.com/SAKURAfan1023/dafeiyu-bot/blob/main/docs/QQ_MODULES.md) · [测试边界](https://github.com/SAKURAfan1023/dafeiyu-bot/blob/main/docs/VALIDATION.md) · [反馈](https://github.com/SAKURAfan1023/dafeiyu-bot/issues)
