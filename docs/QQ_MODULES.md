# QQ 按需安装与客户端 / MCP 双入口

本轮预览版本为 `0.3.0-preview.1`，macOS arm64 的四个 npm 包已公开发布，具体状态见[发布记录](NPM_RELEASE.md)。Windows 原生 NapCat 按用户确认的可用前提接入，不把社区使用情况写成这台机器的实测结果。原有 macOS 客户端、Linux/WSL 路线继续保留。

## 包的边界

| 包 | 内容 | 安装行为 |
| --- | --- | --- |
| `@sakurafan1023/cli` | 按需安装向导、客户端启动命令 | 基础包不下载其他功能 |
| `@sakurafan1023/qq` | 本机 QQ 后台管理与固定操作接口、Node WebSocket 传输依赖 | 选择当前系统/架构的原生后台 |
| `@sakurafan1023/qq-<平台>-<架构>` | QQ 专用 Swift 可执行文件、所需资源和运行库 | 不含微信、社交浏览器、NapCat、QQ 或虚拟机 |
| `@sakurafan1023/mcp` | MCP SDK stdio 入口 | 只调用已安装 QQ；不自动装全套功能 |

当前构建产物只对应构建机器的平台。已定义 macOS arm64/x64、Windows x64、Linux x64/arm64 的命名；不能据此声称所有架构都已构建或验收。首批 npm 候选仅提供 macOS arm64，使用 `@sakurafan1023` 作用域与 `next` 通道，详见[发布清单](NPM_RELEASE.md)。Windows ARM64 暂未开放。

QQ 包通过 `qq-sources.json` 从原始 Swift 文件生成独立构建目标，避免复制一套业务代码。原有文字、群真实 @ / 主动接话、工作时段、额度、记忆、表情、识图、生图、搜图、插画和定时发送仍使用原 QQ 引擎。QQ 资源中不包含 SocialBrowser、SocialControl 或微信执行代码。

## Windows 原生运行

目标是 Windows x64 的本机 QQ + NapCat + 大肥鱼后台，不依赖 WSL 或虚拟机。

1. 自行安装匹配的 Windows QQ / NapCat，并启用本机 OneBot 11 正向 WebSocket。
2. 安装 Node.js 22 以上。图片功能另需 Python 与 Pillow，把 `DAFEIYU_PYTHON` 设置为 python.exe 的完整路径。文本连接不依赖 Python。
3. 准备与系统匹配的四个 npm tarball；本预览暂用本地构建或后续经过验证的 CI 产物。
4. Windows 分包包含从 PE 导入表收集的 Swift DLL 依赖；Microsoft Visual C++ x64 运行库作为系统前置条件。Windows CI 会清除 Swift 工具链 PATH 后再安装和启动 tarball，此门槛尚未在当前 Mac 执行。

数据默认位于 `%LOCALAPPDATA%\DaFeiYu`。Windows 使用当前用户 SID 的受保护 ACL，控制记录不允许其他主体读取；自定义数据目录必须独占使用，不能指定公共共享目录。OneBot 和模型凭证只在后台进程内保留，不明文持久化。后台退出后需重新输入。

## 从源码生成本地安装包

开发机需要 Swift；普通用户使用预构建 tarball 不需要 Swift 编译工具。

```sh
npm ci --ignore-scripts
python3 scripts/build-qq.py
npm run pack:qq
```

Windows 将 `python3` 改为 `python`。当前架构的后台在 `dist/qq`，四个 tarball 在 `dist/npm`。包内包含版本清单、文件 SHA-256、MIT 及相关第三方许可；启动已安装包前校验清单和哈希。`DAFEIYU_QQ_ROOT` 仅用于显式本地源码调试，会跳过安装包哈希验证。

Windows PowerShell 本地预览安装示例：

```powershell
$modules = Join-Path $env:LOCALAPPDATA 'DaFeiYuModules'
$archives = (Get-ChildItem dist/npm/*.tgz).FullName
npm install --prefix $modules --ignore-scripts --omit=optional $archives
$env:DAFEIYU_MODULES_DIR = $modules
node "$modules/node_modules/@sakurafan1023/cli/bin/dafeiyu.mjs" qq panel
```

`--omit=optional` 只用于同时显式安装本机平台 tarball 的离线产物组合，避免请求尚未发布的其他平台包。新增 npm 平台前需逐平台验证并准备对应包；当前公共版本只提供 macOS arm64。

在支持的 Mac 上运行：

```sh
npx --yes @sakurafan1023/cli@0.3.0-preview.1 setup qq
npx --yes @sakurafan1023/cli@0.3.0-preview.1 qq panel
```

向导固定版本、使用稳定用户模块目录并禁用安装脚本，不会安装 QQ、NapCat、虚拟机或自动开始回复。全局安装 CLI 时，可自行把 QQ 模块装入指定稳定目录；安装向导要求从 npm exec / npx 启动。Windows 原生仍通过本地产物验证，不使用这组 Mac 发布命令。

## 客户端与后台生命周期

`dafeiyu-qq panel` / `dafeiyu qq panel` 打开本机 Web 客户端，支持现有完整 QQ 设置。`status` 只读取状态，`pause` 暂停，`disconnect` 断开，`stop` 在断开且空闲后退出独立后台。`dafeiyu-qq connect` 使用已保存配置；凭证通过面板输入，或从 `DAFEIYU_ONEBOT_TOKEN`、`DAFEIYU_MODEL_KEY` 环境变量读取，不接受令牌命令行参数。

客户端与 MCP 通过私有 `qq-worker.json` 发现同一个后台。`qq-worker.lock` 确保每份数据只有一个发现服务；原 `qq-engine.lock` 继续排除并发连接/配置写入。记录包括版本、进程号、代次和私有控制地址，Node 会实际请求并核对返回身份。发现存活但无响应的后台时不会启动第二个引擎。进程退出后锁由系统释放；重启不自动连接或启动回复，不重放历史任务。

原生 macOS 客户端先启动时，MCP 接入客户端持有的 QQ 引擎。手动网页入口和共享 MCP 入口分别鉴权，关闭手动网页不会关闭 MCP 服务。独立后台先启动时，原生客户端通过嵌入本机面板连接；不新建写入引擎。共享服务注册失败时 QQ 操作禁用，避免另起执行者。微信和社交入口仍使用原实现。

MCP Host 退出不杀共享后台。独立后台用 `disconnect` 后 `stop` 退出；原生客户端持有的服务随客户端退出而结束。后台不管理外部 NapCat 的进程生命周期。

## 独立 macOS MCP 测试版

`npm run build:macos-mcp` 单独生成带 Node 和依赖的 release 测试 ZIP，使用隔离数据目录，不覆盖 Windows 或通用打包输出。支持 stdio，以及供 ChatGPT 连接验收的本机 Streamable HTTP 入口。使用方式和实际 Host 验收边界见 [Mac MCP 测试版](MACOS_MCP_TEST.md)。

## MCP 配置

本地安装后，Host 使用真实 Node 路径和 MCP 脚本的绝对路径：

```json
{
  "mcpServers": {
    "dafeiyu": {
      "command": "node",
      "args": ["<模块目录>/node_modules/@sakurafan1023/mcp/bin/mcp.mjs", "--modules", "qq"],
      "env": { "DAFEIYU_MODULES_DIR": "<模块目录>" }
    }
  }
}
```

Windows 的 JSON 路径使用正斜杠或转义反斜杠。Node 进程 stdout 仅用于 MCP 协议，后台静默启动。Host 接入不会自动连接 QQ 或启动回复。

提供 7 个工具：`qq_status`、`qq_contacts`、`qq_run_control`、`qq_save_connection`、`qq_manage_target`、`qq_settings`、`qq_memory`。运行控制只提供暂停、断开和启动已保存范围；没有任意 OneBot、任意脚本或直接发送接口。连接及工具密钥由本机面板/CLI 配置。

写操作携带最近状态中的账号、后台代次和配置版本；首次保存连接时允许原账号为空。启动回复前必须明确确认用户意图，默认运行 15 分钟。提交后超时按结果未知处理，不自动重试。记忆只在用户明确要求时通过专门工具读取，默认状态响应不含记忆正文。

## 验证与边界

```sh
bash scripts/test.sh
bash scripts/build.sh
python3 scripts/check-public.py
python3 scripts/test-control-panel.py 'dist/WeChat AI Bot.app/Contents/MacOS/WeChatAIBot'
python3 scripts/build-qq.py --configuration debug
python3 scripts/test-control-panel.py dist/qq/dafeiyu-qq --qq-only
DAFEIYU_QQ_ROOT="$PWD/dist/qq" npm test
npm run pack:qq
npm run test:distribution
```

另有 `--test-node-transport` 构建开关，可在 Mac 上实际运行 Windows 使用的 Swift → Node WebSocket 传输链。它不能替代 Windows API、ACL、DLL、图片 Job 的原生验证。

macOS 和 Linux CI 增加独立包验证；新增 Windows CI 执行原生构建、引擎/图片测试、QQ HTTP、OneBot 合成通信、npm 和 MCP、清除 Swift PATH 后的 tarball 安装。所有自动化使用临时数据和合成账号，不访问真实 QQ 或模型。

当前已通过的本机测试记录见 `docs/VALIDATION.md`，npm 发布及公共下载验证见[发布记录](NPM_RELEASE.md)。Windows 原生 CI 已通过完整引擎、控制页、MCP 与清除 Swift PATH 后的安装验证，`0.3.0-preview.2` 正在上传；Windows QQ 真实账号收发未在本机验收；发布过程没有更改现有真实账号和服务。
