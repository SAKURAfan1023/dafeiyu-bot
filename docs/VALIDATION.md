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


## QQ 分包与双入口本地自测（2026-11-05）

### 测试环境

未提交工作区，版本 `0.3.0-preview.1`；macOS arm64，Swift 6.4、Node.js 24、Python 3.9。原生应用为 release 构建，QQ 独立包为 debug 构建。使用临时数据目录、合成 QQ 身份和本机 OneBot/模型夹具；没有操作真实账号、NapCat、虚拟机或线上服务。

### 测试方法与结果

| 检查 | 实际结果 | 证明范围 |
| --- | --- | --- |
| `bash scripts/test.sh` | 107 项 QQ/社交测试 + 77 项 BotCore 测试通过 | 原有规则、发送约束、媒体/记忆、暂停/取消回归；新增 OS 锁与共享服务生命周期 |
| `bash scripts/build.sh` | release 构建、签名及严格签名检查通过 | macOS 应用可生成；不代表 Windows 可执行文件通过 |
| 原有应用 HTTP 检查 | 通过，包括独立社交路由和 QQ 队列取消 | 保留现有平台隔离与控制页行为 |
| 独立 QQ HTTP 检查 | 原生 Mac 传输及 Windows 所用 Node 传输均通过 | 鉴权、Origin/Host、畸形请求、版本冲突、配置/图片设置持久化、错误账号/离线拒绝、十条合成事件暂停后不继续；均未发送真实消息 |
| Swift → Node → 合成 WebSocket | 成功、账号不符、离线、断线四场景通过 | 使用真实传输、Bearer 认证、逆序 echo 响应与事件穿插；非 Windows OS API 验收 |
| `npm test` | 7 项通过，Windows ACL 负向检查 1 项因平台不符跳过 | SDK 初始化、固定操作范围、并发复用后台、陈旧配置拒绝；200 KB/900 KB 慢读保持连接，超 1 MiB 帧拒绝 |
| tarball 安装及真实 MCP stdio | 四包在中文/空格临时路径安装通过；首次空账号配置、CLI 状态、共享 PID、Host 退出保留后台、空闲退出和完整性篡改拒绝均通过 | 仅使用实际 npm 打包产物和 SDK 子进程，无源码路径替代；平台为 macOS arm64 |
| QQ 包边界 | 独立源码清单和产物检查通过 | 不含微信/社交执行器和 SocialBrowser；复用原 QQ 引擎 |
| 公开文件检查 | 358 个已跟踪及新增公开文件，命中 0；diff 空白检查通过 | 已检查文本和运行文件边界；不扩大到发布、提交元数据或 Windows 二进制验收 |
| Windows CI / DLL 闭包 | 工作流与脚本已加入，YAML 语法通过；PE 解析器读取官方 distlib x64 启动器导入表通过（未执行该文件） | Windows 原生编译、ACL、图片 Job、DLL 闭包及清除 Swift PATH 后安装尚未在本轮执行 |

### 测试结论

本机可构建独立 QQ 包，客户端与实际 MCP 进程能共用后台，原有 Mac/Linux 代码路径和功能保留。Windows 源码适配及自动检查入口已具备；当前环境没有 Windows 主机，不能宣称 Windows 原生运行或真实 QQ 收发已验收。上游 Windows NapCat 可用是用户接受的方案前提。

本轮没有提交、推送、部署或发布 npm；没有触发云端 CI。后续须在 Windows 执行新增工作流，确认原生编译和纯运行环境安装，再做受控账号收发验收。微信、外部图片/模型服务与长期稳定性仍沿用既有边界。


## Mac 独立测试包与 Codex 原生 MCP 验收（2026-11-05）

### 测试环境

macOS arm64，本地未提交工作区，`0.3.0-preview.1` release QQ 后台与独立原生测试窗口，内置 Node.js 24.21.0 和 MCP 依赖。使用独立 `DaFeiYuMCPTest` 数据目录；真实账号及原客户端不参与验收。

### 测试方法与结果

| 测试项 | 方法与实际结果 |
| --- | --- |
| 独立安装包 | 通过：生成约 56 MiB ZIP，解压到中文/空格路径、清除开发者 PATH 后，使用包内 Node 完成 stdio/HTTP MCP、客户端接口、配置持久化、退出/重启和签名检查。原生应用也单独签名验证。 |
| 原生客户端 | 通过：独立应用标识的原生窗口已实际显示连接、范围与回复、图片工具、记忆记录四页；应用移到用户 Applications 后加载正常。没有操作已有客户端。 |
| QQ 包边界 | 通过：独立包隐藏未安装的社交和微信导航，完整客户端保留原有入口；两种 HTTP 测试均通过。 |
| Codex 原生 MCP | 通过：单独验收窗口实际调用 `qq_status`、`qq_save_connection` 和 `qq_run_control(pause)`；首次空账号成功保存为合成账号 12345。 |
| 双入口同步 | 通过：主窗口从原生 MCP 和客户端接口核对同一后台 PID 72399；原生客户端实际显示 `12345`、`ws://127.0.0.1:30123`、QQ 已暂停，模型调用与发送确认均为 0。 |
| 过期配置错误 | 已修复、SDK 通过：过去只返回笼统的未确认提示；现在 POST 前冲突返回 `QQ_STATE_CHANGED`、`submitted:false` 和“本次操作未提交”。真实分包 SDK 检查通过；旧 Codex 会话仍缓存旧子进程，新窗口原生复验待宿主确认。 |
| 回归及公开文件 | 通过：107 项 QQ/社交 + 77 项 BotCore；8 项 npm 检查通过，Windows ACL 1 项跳过；完整应用与 QQ 专用 HTTP 检查、release 构建签名、370 文件公开扫描和 diff 检查通过。 |

### 测试结论

Mac 客户端与 Codex 原生 MCP 的状态、首次配置和暂停链路已实际使用，测试包可独立运行。没有连接真实 QQ 或调用模型。ChatGPT 浏览器访问仍被 Work 设置阻止，用户已改为 Codex 验收；computer-use 明确禁止访问 Codex 本身，不能由代理代点其确认按钮。新版冲突提示的原生复验仍保留这一限制，SDK 结果不替代它。

Windows 云端测试未获明确许可且本机无 Windows 主机，Windows 原生编译/运行仍未执行。没有推送、合并、部署或发布 npm；Codex 的 `dafeiyu_mac_test` 仅注册到本机独立安装目录。
