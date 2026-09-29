# macOS 安装与快速开始

**Windows 用户请阅读 [Windows / WSL2 教程](WINDOWS.md)**。Windows 使用同一引擎和 Web 面板，下面的 `.app`、Xcode、Lima 命令仅适用于 Mac。

## 支持范围

- 控制端：macOS 14+。建议安装 Xcode / Command Line Tools 的 **Swift 6** 工具链（测试使用 Swift Testing），Python 3 用于合成接口测试和配置工具。
- 已验证部署形态：Apple Silicon Mac + 独立 ARM64 Ubuntu VM + Docker + NapCat / QQ。Intel Mac 原生源码尚未单独验收，附带 VM 定义只面向 ARM64。
- 必需：DeepSeek API Key、自己可登录的 QQ、NapCat 提供的 OneBot 11 正向 WebSocket。
- 可选：智谱视觉/生图 Key、Cloudflare Account ID / Workers AI Token、Google Cloud Vision 凭证。不要在首次接通前把所有功能一起开启。

## 1. 获取和构建

```sh
git clone https://github.com/SAKURAfan1023/dafeiyu-bot.git
cd dafeiyu-bot
swift --version
python3 --version
bash scripts/test.sh
bash scripts/build.sh
```

产物 `dist/WeChat AI Bot.app` 是本机临时签名的源码构建，不是已公证安装包。可以 `open 'dist/WeChat AI Bot.app'` 打开原生界面，并在 QQ 页或菜单栏点击“在浏览器打开 QQ 面板”，两端控制同一个运行实例。也可退出客户端，使用下文命令独立启动 Web 后台；不要同时启动两个活动引擎。

## 2. 选择 QQ 桥接方式

### 已有 NapCat（最短路径）

按 [NapCat 官方使用说明](https://napneko.github.io/guide/boot/Shell) 安装并完成 QQ 登录。在 NapCat 的网络配置中创建 **WebSocket Server / 正向 WebSocket**：

| 项目 | 设置 |
| --- | --- |
| 端口 | 示例3001，可自行调整 |
| 消息格式 | Array / 数组消息段 |
| Token | 随机强令牌；与控制面板 OneBot Token 完全一致 |
| 自身消息上报 | 开启 reportSelfMessage，主人群人工消息才能被计入上下文/计数 |
| 网络 | 控制端使用回环地址或可信隧道；不要把接口直接公开 |

本控制端要求回环 `ws://127.0.0.1:端口`。远端桥接应先通过 SSH 等方式转发至本机回环，不能直接填公开服务器地址。

### Apple Silicon 独立 VM 参考流程

本仓库不打包 QQ/NapCat 二进制。Lima 安装参考[官方文档](https://lima-vm.io/docs/installation/)，容器参考 [NapCat Docker](https://github.com/NapNeko/NapCat-Docker)。下面是附带脚本的调用顺序；可能需要系统允许虚拟化和网络访问。

```sh
brew install lima
limactl start --name=qq-ai deploy/qq-lima.yaml
python3 scripts/init-qq-config.py
limactl shell qq-ai mkdir -p qq-runtime/config
limactl copy "$HOME/.local/qq-runtime/config/onebot11.json" qq-ai:qq-runtime/config/onebot11.json
limactl copy "$HOME/.local/qq-runtime/config/webui.json" qq-ai:qq-runtime/config/webui.json
limactl copy "$HOME/.local/qq-runtime/config/napcat.json" qq-ai:qq-runtime/config/napcat.json
limactl copy deploy/qq-container-entrypoint.sh qq-ai:qq-runtime/qq-container-entrypoint.sh
limactl copy deploy/qq-container-create.sh qq-ai:qq-runtime/qq-container-create.sh
limactl shell qq-ai bash qq-runtime/qq-container-create.sh
bash scripts/qq-runtime.sh start
```

初始化脚本在仓库外生成权限受限的配置，拒绝覆盖已有文件，不打印 Token。用本机编辑器查看 `~/.local/qq-runtime/config/webui.json` 中的 WebUI Token，在 `http://127.0.0.1:6099/webui/` 登录 NapCat，使用手机 QQ 扫码。OneBot Token 在 `onebot11.json` 中，是另一枚令牌。

容器内部监听0.0.0.0，由 Docker + Lima 限制宿主仅127.0.0.1；不要更改为公网映射。镜像和系统镜像采用固定摘要；上游下载不可用时，核对官方发行版及摘要后再更新定义，不直接换不明镜像。不会创建开机托管，Docker restart=no。

首次扫码后再次在 NapCat WebUI 检查**当前账号生效的**网络配置：不同版本可能为账号生成独立配置文件，默认配置文件存在不能证明当前账号已经启用 OneBot 和自身消息上报。以面板连接和实际事件为准。

## 3. 启动大肥鱼面板

```sh
'dist/WeChat AI Bot.app/Contents/MacOS/WeChatAIBot' --qq-control-panel
```

打开终端输出的完整本机地址；不要转发这个地址，它带有本次控制凭证。

1. 核对 OneBot 地址（默认 `ws://127.0.0.1:3001`），填写实际机器人 QQ 号，必须与扫码登录账号一致。
2. 点击“保存地址与账号”；保存成功只代表配置落盘，尚未连接。
3. 展开“配置本次运行的凭证”，同时填写 OneBot Token（不是 NapCat WebUI Token）和 DeepSeek API Key；已有可用凭证时可留空。
4. 点击“连接并核对账号”，检查账号、在线状态与联系人。此时不会自动开始回复。

面板可使用仅本次运行有效的临时凭证；GUI 钥匙串提示需要在自己的 Mac 正常授权。不要用密码替代 API Key，不要把凭证写入仓库或命令行参数。

## 4. 单次验证再持续运行

从已核对的联系人中添加一个允许测试的好友或群，勾选该会话，然后点击“保存范围与回复设置（不启动）”。新增会话不等于启用，勾选后也需要保存。再点击“单次验收”，让好友发新文字，群内用 QQ 的 @ 选择器真正选中机器人。收到一次回复后单次模式自动暂停；核对对端收到再开始较长运行。只看到模型调用或接口发送确认不等于对端已收到。

调整日额度和冷却后再次保存，再选择下次运行时长，点击“按已保存配置开始回复”。如果提示有草稿，先保存或明确放弃。两阶段回复通常至少两次模型调用，1 秒冷却不代表 1 秒响应。关闭页面不会停止服务；先暂停，再在启动终端 Ctrl+C。可选 `bash scripts/qq-runtime.sh stop` 停止独立 QQ VM，会让桥接离线。

## 排障

| 现象 | 先检查 |
| --- | --- |
| 无法连接 | NapCat在线、正向WS已启用、端口转发、令牌是否混用、实际账号独立配置 |
| 已连接不回复 | 是否点开始、会话是否启用、运行是否到期、日额度、工作时段和错误提示 |
| 群消息不回复 | 是否真实@；主动接话是否开启；每N条只是评估，模型可沉默 |
| 主人消息没计数 | 当前账号 reportSelfMessage 是否打开；消息是否为人工且通过去重 |
| 很慢/费用高 | 草稿+校对、工具调用、思考、记忆与重试；先减少可选工具和主动接话 |
| 图片没有发送 | 素材哈希/大小、去重、语境匹配、图源权限/热度门槛、调用额度 |
| 发送结果未知后暂停 | 先确认对端是否收到，不能直接重复重发 |
| GUI / 钥匙串问题 | 本机正常授权；也可用Web临时凭证；不要开两个活动引擎 |
| 微信不稳定 | 当前仍在测试，未通过自动回复验收；先用QQ链路 |

排障前保留复现步骤，分享时脱敏。不要通过关闭认证、公开端口或复制账号登录数据来“修复连接”。
