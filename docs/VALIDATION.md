# 验证记录与边界

公开源码版本本地检查日期：2026-09-28。控制端为 Apple Silicon macOS；新安装 QQ 或新账号需自行完成受控验收。

| 层级 | 结果 | 能证明什么 |
| --- | --- | --- |
| Swift 自动化测试 | 127 项通过：QQEngine 55 + BotCore 72 | 规则、上下文、记忆、人格、图片和工具等合成输入的回归结果 |
| release 构建与本机签名 | 通过 | 本机可生成 macOS 应用；不是公证或多平台安装验收 |
| OneBot 本机合成传输 | 成功、账号不符、离线、断线四个场景均通过 | 真实 Swift WebSocket 传输与失败处理；未访问 QQ / AI |
| 新配置初始化 | 权限0700/0600、独立随机令牌、自身消息开关、拒绝覆盖与仓库内配置均核对 | 初始配置工具的行为；不等于上游 NapCat 当前账号配置已生效 |
| 真实 QQ 基础私聊和群@ | 历史运行中用户确认收到正常回复 | 已有基础链路证据，不代表公开包换机即免配置可用 |
| 真实对话片段 | 原文及机器人发送记录已核对，公开版仅匿名重排 | 一个实际样本；见 CHAT_EXAMPLE.md |
| 微信 | 测试中 | 未完成稳定自动回复验收 |
| 长时间运行 | 存在中断、重启与版本变更 | 不宣称连续三天无故障 |
| 识图/生图/搬图 | 各功能有合成与接口边界测试 | 不保证所有外部模型/图源/账号权限在任何时候可用 |

## 复核命令

```sh
python3 scripts/check-public.py
bash scripts/test.sh
bash scripts/build.sh
python3 scripts/test-onebot-transport.py 'dist/WeChat AI Bot.app/Contents/MacOS/WeChatAIBot'
```

传输测试使用合成的本机 WebSocket 服务，不会登录 QQ、发送聊天或调用付费模型。真实操作须使用自己的账号、凭证和明确授权会话；自动测试通过不能代替对端确认。公开版未带作者的聊天数据库、记忆、运行日志、凭证、会话白名单或第三方私人表情包集合。

## Windows / WSL2 兼容增量

2026-09-29，新增同一 QQ 引擎的 Linux 入口、本机 Web 传输、内存凭证、Swift Crypto / Pillow 图像适配与完整 Windows 教程。macOS 的 SwiftUI / 微信窗口操作未迁移到 Windows，暂无原生 exe 安装包。

验证源码为 `12f327e`，通过 [PR #1](https://github.com/SAKURAfan1023/dafeiyu-bot/pull/1) 合并到主分支；后续状态标注只修改文档。

| 检查 | 结果与证据 |
| --- | --- |
| macOS 回归与构建 | 127 项测试、release 构建和签名检查通过；[macOS CI](https://github.com/SAKURAfan1023/dafeiyu-bot/actions/runs/36450117176) |
| Linux 共享引擎回归 | Ubuntu 24.04 x86_64、Swift 6.1.3，128 项测试通过；[Linux CI](https://github.com/SAKURAfan1023/dafeiyu-bot/actions/runs/36450117166) |
| 真实本机 HTTP 下载 | 正常下载、声明长度超限、流式超限、取消、拒绝重定向均通过；采用合成本机服务，不只依赖 URLProtocol 模拟 |
| Pillow 图像处理 | 静态图、GIF 时间采样与帧预算、透明背景、清晰度、尺寸、损坏输入和元数据清理通过 |
| Linux release 产物 | 构建通过；从打包资源目录启动面板，资源、Token、Origin、Host、重复请求头、超大 Content-Length、Transfer-Encoding 拒绝与暂停均通过 |
| OneBot 合成传输 | Linux debug / release 的成功、账号不符、离线、断线四个场景均通过 |
| 隐私与文档 | 104 个公开文件的工作区/暂存扫描无命中；相对链接完整，提交采用 GitHub no-reply 邮箱 |

兼容过程中修复了系统 libcurl 不支持 WebSocket、Linux 自定义 URLProtocol 下载文件行为不一致的问题；Linux 使用 NIO WebSocket 和有界 HTTP 数据接收。取消夹具等待 URLSession 确认后再检查旧结果，辅助 HTTP 进程在测试结束时可靠回收，没有删除暂停或取消覆盖来让检查通过。

本次检查没有连接真实 QQ、调用付费模型、重启原有机器人或修改生产配置。Windows 实机 WSL 安装、跨系统浏览器访问、扫码与对端收发，以及 Linux ARM64 尚未验收；不能用上述 x86_64 CI 代替。微信和长期运行边界保持上表所述。
