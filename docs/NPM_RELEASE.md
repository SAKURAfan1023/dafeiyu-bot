# npm 发布记录 · 0.3.0-preview.1

## Windows 发布候选 · 0.3.0-preview.2

本批包含 macOS arm64、Windows x64 两个平台后台和同版本 CLI、QQ、MCP，共五个包，正在执行正式上传。旧版 `0.3.0-preview.1` 和其核验记录保留；未合并 main 或部署服务。

[Windows 原生 CI](https://github.com/SAKURAfan1023/dafeiyu-bot/actions/runs/42057072204)、[macOS CI](https://github.com/SAKURAfan1023/dafeiyu-bot/actions/runs/42057072338)、[Linux CI](https://github.com/SAKURAfan1023/dafeiyu-bot/actions/runs/42057072223) 全部通过。Windows 包通过 169 项原生测试、9 项 Node 测试、OneBot 合成通信、控制页、真实 SDK MCP、清除 Swift PATH 后的 tarball 和实际 npx 安装。测试未登录真实 QQ，也未调用真实模型。

Windows 修复包括 Swift SDK 编译差异、原子文件保存、私有 ACL、客户端从 PowerShell 7 / npm 环境调用系统 Windows PowerShell 时的模块加载。权限限制和发送规则保留，额外读取者必须被拒绝。并发场景在测试内部保留，Windows 集成测试按顺序执行，避免无关夹具占用主线程。

最终五包位于 `dist/npm-release-preview.2`，匿名 dry-run 和内容预检见其中的 `verification.json`。Windows 仅补充原始依赖许可及完整性清单；可执行文件和 15 个 DLL 与通过测试的产物字节一致，证据为 `windows-runtime-parity.json`。通用脚本使用 LF 换行；Windows 与 Mac 生成版本除换行外内容一致。发布后再核对公共下载哈希，并用全新缓存复验公共安装。

以下记录保留已经公开的第一版。

2026-11-05，以下四个 `0.3.0-preview.1` 包已公开发布，并逐包确认公共下载文件与审阅过的本地 tarball 完全一致。包使用用户确认的 `@sakurafan1023` 个人作用域；不使用 `@dafeiyu` 组织，也不使用已有其他维护者的无作用域包 `dafeiyu`。

## 首批范围与版本

- 版本：`0.3.0-preview.1`。
- 通道：`next`；可见性：`public`；registry：`https://registry.npmjs.org/`。
- 原生平台：macOS Apple Silicon（arm64，macOS 14+）。
- 运行前置：Node.js 22+ 和 npm，以及用户单独准备的 QQ / NapCat 接入环境和模型凭证。
- Windows、Intel Mac、Linux npm 原生包不在首批发布名单；源码和验证入口继续保留。

根目录 `release-plan.json` 是这批候选的包名、版本、通道与平台清单。QQ 的可选依赖只声明本次提供的原生平台，不把未发布的平台写进依赖表。发布 `next` 后，使用文档里的固定版本，或显式选择 `@next`；不执行无作用域的 `npx dafeiyu`。

| 发布顺序 | 包名 | 内容 |
| --- | --- | --- |
| 1 | `@sakurafan1023/qq-darwin-arm64` | 原生后台、QQ 控制页与资源、完整性清单和许可 |
| 2 | `@sakurafan1023/qq` | QQ 模块接口、后台发现及原生包依赖 |
| 3 | `@sakurafan1023/cli` | 按需安装和客户端启动入口 |
| 4 | `@sakurafan1023/mcp` | MCP stdio 及受限的测试 HTTP 入口 |

根工作区始终为 `private:true`，不上传整个仓库，也不把 Mac 测试 ZIP 或安装后的运行数据放进 npm 包。

## 安装和使用

以下命令使用已公开的固定预览版本，也可显式选择 `@next`。本版仍为预览版本。

```sh
npx --yes @sakurafan1023/cli@0.3.0-preview.1 setup qq
npx --yes @sakurafan1023/cli@0.3.0-preview.1 qq panel
```

接入 Codex：

```sh
codex mcp add dafeiyu -- npx --yes @sakurafan1023/mcp@0.3.0-preview.1 --modules qq
```

其他本地 Host 的配置、凭证和后台生命周期见[QQ 模块说明](QQ_MODULES.md)及[包内 MCP README](../packages/mcp/README.md)。浏览器客户端和 MCP 共用同一后台。关闭 Host 不会结束后台；可先断开，再执行 `qq stop`。

## 当前核验状态

| 项目 | 当前结果 |
| --- | --- |
| 发布身份 | 官方网页登录与用户本机通行密钥授权完成，`npm whoami` 返回 `sakurafan1023` |
| 作用域 | 四个包均位于 `@sakurafan1023`，依次完成各自的发布验证 |
| registry 版本 | 四个公共包均已包含 `0.3.0-preview.1`，`next` 指向该版本；下载文件 SHA-256 与本地审阅产物一致 |
| 默认标签 | registry 首次发布同时添加了 `latest`；原生包移除 `latest` 的请求在授权后返回 E400，重新读取确认未变。未对其他包重复尝试同一失败操作；使用固定版本或显式 `@next`，不把默认标签视为稳定性承诺 |
| 内容及 dry-run | 四个实际 tarball 已执行匿名 `npm publish --dry-run`；详见生成的 `dist/npm-release/verification.json` |
| 安装闭环 | 本地 fixture 与公共 registry 两条链路均通过实际 `npx @next`、按需安装、原生可选依赖、MCP stdio、客户端共享后台与停止检查；公共链路使用全新匿名缓存 |
| 源码与文档 | 本地 README 和发布候选已准备；尚未提交或推送本轮改动，新文档公开链接需随对应源码同步 |
| Windows 原生 | 未完成本轮原生编译与运行测试，不列入本次 npm 已支持平台 |

`--dry-run` 不上传包，也不能证明账号拥有发布权限或已完成 2FA。认证、作用域和首次版本检查必须在正式上传前重新核对。现有版本一旦发布不能覆盖；若 registry 已有同一版本，应准备新版本。

公共下载核验在 `dist/npm-release/publication.json`，原始匿名打包预检保留在 `verification.json`。npm 首次接收上传后曾短暂只显示 `0.0.0-stage` 占位版本；等待异步处理后才核对真实版本，未重复上传同一版本。

公开包：[CLI](https://www.npmjs.com/package/@sakurafan1023/cli)、[QQ](https://www.npmjs.com/package/@sakurafan1023/qq)、[MCP](https://www.npmjs.com/package/@sakurafan1023/mcp)、[macOS arm64 后台](https://www.npmjs.com/package/@sakurafan1023/qq-darwin-arm64)。

## 构建与本地预检

在 Apple Silicon Mac 上执行：

```sh
npm ci --ignore-scripts
python3 scripts/build-qq.py --output dist/npm-native
npm run pack:qq -- --runtime dist/npm-native --output dist/npm-release
npm run check:npm-release
npm run test:npm-install
# 已发布版本：从公共 registry 和全新匿名缓存检查安装
npm run test:npm-install -- --public
```

预检检查版本、registry、tag、README/许可、QQ-only 资源、敏感文件、构建路径及 release 配置，并对确切 tarball 做 dry-run。`test:npm-install` 默认使用临时无凭证 npm 配置和本机 fixture registry；`--public` 改为公共 registry。两者都使用临时模块、数据与缓存目录，不连接真实 QQ 或模型。

不要把其他测试目录里的 tarball 混入 `dist/npm-release`。预检要求这批目录只有四个与计划一致的 tarball；其他作用域或旧版本会被拒绝。

## 正式上传前与上传后

以后发布新版本时，完成网页登录后先执行 `npm whoami`，确认账号；对四个名称查询已有版本和访问状态。核对源码、文档与候选内容后，再对明确的四个 tarball 逐个上传，使用 `--access public --tag next`。本轮由用户明确授权后逐包上传，没有增加自动上传脚本。

上传后逐包核对 registry 的版本、`next` 指向和 tarball 完整性，再用全新缓存、默认公共 registry 重跑安装流程。只有这一步通过，才能把 README 的“尚未上传”改成已发布；本地 fixture 的成功不能代替公共 registry 首次安装。

如果流程要求 2FA，通过 npm 官方认证页面完成，不在聊天、命令参数或仓库中保存密码、验证码或 token。

参考：[npm scoped 公共包发布](https://docs.npmjs.com/creating-and-publishing-scoped-public-packages/)、[npm publish 与 dry-run](https://docs.npmjs.com/cli/v11/commands/npm-publish/)。
