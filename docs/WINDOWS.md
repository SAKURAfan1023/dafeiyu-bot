# Windows 安装与使用（WSL2 + Web 面板）

Windows 版采用 WSL2 运行与 Mac 相同的 QQ 回复引擎，在 Windows 的 Edge / Chrome 中打开本机面板。WSL2 是 Windows 的 Linux 子系统；不需要拥有 Mac。当前提供源码构建方式，尚无原生 `.exe` / MSI 安装包。微信桌面自动化仍仅在 Mac 上测试，Windows 这条链路只接入 QQ。

> 2026-09-29：Ubuntu 24.04 x86_64 / Swift 6.1.3 的 128 项测试、发布构建、打包面板与 OneBot 传输检查已通过。Windows 实机 WSL 安装、浏览器访问与扫码/收发仍待验收；Linux CI 不能代替这些步骤。详见 [验证记录](VALIDATION.md)。

## 1. 准备 WSL2

建议 Windows 11，至少 8 GB 内存、15 GB 可用磁盘。Windows 10 需要满足微软 WSL2 安装条件并保持系统更新。安装前保存工作；启用虚拟化可能需要重启。

在**管理员 PowerShell**运行：

```powershell
wsl --install -d Ubuntu-24.04
```

重启后打开 Ubuntu，按提示创建 Linux 用户和密码。此密码由你自己保管，用于 `sudo`，不填写在机器人面板里。然后在 PowerShell 核对：

```powershell
wsl --list --verbose
```

Ubuntu-24.04 的 VERSION 应为 `2`，否则运行：

```powershell
wsl --set-version Ubuntu-24.04 2
```

详细系统条件及安装故障见 [微软官方 WSL 安装说明](https://learn.microsoft.com/windows/wsl/install)。下面标为 Bash 的命令都在 **Ubuntu 终端**运行，不是在 PowerShell 中运行。

## 2. 安装编译依赖

```bash
sudo apt-get update
sudo apt-get install -y git curl ca-certificates python3 python3-pil docker.io
sudo systemctl start docker
```

在 [Swift 官方 Ubuntu 24.04 安装页](https://www.swift.org/install/linux/ubuntu/24_04/) 安装 **Swift 6.1.3 或已验证的更新版本**，根据 `uname -m` 选择 x86_64 / aarch64，并遵循官方依赖与签名核验步骤。不要安装 Windows 版 Swift 到 WSL 中。

```bash
swift --version
python3 -c 'from PIL import Image; print(Image.__version__)'
sudo docker version
```

这里 Docker 只用于独立的 NapCat/QQ 环境；不需要另外购买或安装 Docker Desktop。初次下载 Swift、依赖和镜像较大，后续普通启动不需要重新编译。

## 3. 下载、测试和构建

```bash
cd ~
git clone https://github.com/SAKURAfan1023/dafeiyu-bot.git
cd dafeiyu-bot
bash scripts/test.sh
python3 scripts/test-linux-images.py
bash scripts/build-linux.sh
python3 scripts/test-control-panel.py dist/dafeiyu-linux/dafeiyu
python3 scripts/test-onebot-transport.py dist/dafeiyu-linux/dafeiyu
```

源码放在 WSL 的 `~/dafeiyu-bot`，避免放在 `/mnt/c` 的同步目录中导致编译和文件权限问题。产物为 `dist/dafeiyu-linux/dafeiyu` 和旁边的 `Resources`，两者要一起保留。

## 4. 安装独立 QQ 桥接并扫码

默认让 **QQ 桥接和回复引擎都在同一个 Ubuntu 中**，这样不需要开放 Windows 防火墙端口或猜测 WSL 地址。

```bash
cd ~/dafeiyu-bot
python3 scripts/init-qq-config.py --directory "$HOME/qq-runtime/config"
cp deploy/qq-container-entrypoint.sh "$HOME/qq-runtime/"
cp deploy/qq-container-create.sh "$HOME/qq-runtime/"
bash "$HOME/qq-runtime/qq-container-create.sh"
sudo docker start qq-ai
```

初始化工具拒绝覆盖已有配置；升级时不要重新生成令牌。脚本根据 `uname -m` 选择经记录的 amd64 / arm64 镜像摘要，只映射本机回环端口，不设置开机托管。

在 Windows 浏览器中打开 `http://127.0.0.1:6099/webui/`。用自己的编辑器查看 WSL 内 `~/qq-runtime/config/webui.json` 的 Token，登录 NapCat 后用手机 QQ 扫码。不要把二维码或 Token 上传到 Issue。

然后检查 NapCat 当前账号的网络配置：

| 项目 | 必须设置 |
| --- | --- |
| WebSocket 类型 | 正向 WebSocket Server |
| 端口 | 3001 |
| 消息格式 | Array / 数组 |
| Access Token | 与 `onebot11.json` 中预设值一致，稍后填写到机器人面板 |
| 自身消息上报 | `reportSelfMessage` 开启 |
| 心跳 | 开启 |

不同 NapCat 版本可能创建账号专用配置；三个默认 JSON 文件存在不等于当前账号配置已生效。以实际连接和消息事件为准。桥接安装说明参考 [NapCat 官方 Shell 指南](https://napneko.github.io/guide/boot/Shell)。

如果已经在 Windows 原生运行 NapCat：不要同时启动另一个相同 QQ 账号。Windows 11 22H2+ 的 WSL 镜像网络可让 WSL 访问 Windows 的回环服务，具体条件见 [微软网络说明](https://learn.microsoft.com/windows/wsl/networking)。默认 NAT 下不能直接假定 WSL 的 `127.0.0.1` 是 Windows；新用户优先采用本节同一 Ubuntu 的部署方式。

## 5. 启动大肥鱼并验证

```bash
cd ~/dafeiyu-bot
bash scripts/start-linux.sh
```

启动脚本会检查可执行文件与配套面板资源；资源缺失时先停止并提示重新构建，不输出可用面板的假象。保持该终端打开，复制输出的完整 `QQ_CONTROL_URL` 到 Windows 浏览器，包含 `#` 后面的本次凭证。普通复制使用 Ctrl+Shift+C；不要把此地址公开。

1. 核对 OneBot 地址（默认 `ws://127.0.0.1:3001`），填入与刚才扫码账号一致的机器人 QQ 号，点击“保存地址与账号”。
2. 展开“配置本次运行的凭证”，同时填写 **OneBot Token** 和自己的 **DeepSeek API Key**。这里不是 NapCat WebUI Token。
3. 点击“连接并核对账号”，确认实际账号、在线状态和联系人；此时仍未启动自动回复。
4. 从核对后的联系人中添加好友或群，只勾选允许回复的范围，然后点击“保存范围与回复设置（不启动）”。添加会话不代表启用；勾选但未保存也不会生效。
5. 点击“单次验收”，让获准好友发新消息，或在群内使用真正的 @ 选择器选中机器人；收到一次回复后自动暂停。
6. 对端确认后，调整模型调用额度、发送额度和冷却并再次保存；选择下次启动时长，再点击“按已保存配置开始回复”。有未保存草稿时先保存或明确放弃，不把开始按钮当成保存按钮。

Windows/Linux 版凭证仅在进程内保存，重新启动必须重新输入；生图/识图的“保存到钥匙串”选项自动禁用。聊天配置、计数和会话记忆保存在 WSL 的 `~/.local/share/dafeiyu`，目录 0700、文件 0600。此目录包含私人数据，不提交到 Git。

可从 PowerShell 启动已装好的版本：

```powershell
wsl -d Ubuntu-24.04 -- bash -lc 'cd ~/dafeiyu-bot && exec bash scripts/start-linux.sh'
```

## 6. 日常操作、停止和升级

- `/help` 查看命令；`/hot`、`/search 关键词`、`/next`、画师和性格命令见 [全部命令](COMMANDS.md)。命令分发不调用大模型；普通对话和主动接话会消耗模型额度。
- 生图、外置识图和 Google 搜图在同一个面板配置；账户开通条件和费用见 [操作指南](USER_GUIDE.md)。没有配置的可选服务保持关闭。
- 群主动接话按每 N 条**评估**是否加入，可以沉默；真实 @ 不重置累计计数。
- 先在面板暂停，再在运行终端 Ctrl+C。需要退出 QQ 桥接时运行 `sudo docker stop qq-ai`。
- 关闭浏览器不停止后台进程；关闭 WSL、电脑休眠、重启或网络断开可能中断服务。Windows 电源设置需要允许测试期间保持唤醒；锁屏与系统休眠是两件事。本项目不修改你的电源策略或增加开机托管。
- 升级前先暂停并退出引擎，备份 `~/.local/share/dafeiyu`、`~/qq-runtime/config` 及 Docker 的 `qq-ai-data` 卷；备份含账号/聊天隐私，应保存在私人目录。然后 `git pull --ff-only`、重新测试/构建，再启动。升级不会自动重新登录、发送消息或重置额度。

## 排障

| 问题 | 检查方法 |
| --- | --- |
| `wsl` 安装失败 / 虚拟化未启用 | 按微软官方错误码处理 BIOS 虚拟化、Windows 功能和系统版本 |
| `systemctl` 不可用 | 按 [微软 WSL systemd 说明](https://learn.microsoft.com/windows/wsl/systemd) 启用；保存工作后重启该 WSL 实例 |
| 启动提示 `Panel resources are missing` | 在源码目录重新执行 `bash scripts/build-linux.sh`，保留产物旁的完整 `Resources`；不要只复制一个可执行文件 |
| 页面打不开 | Ubuntu 和对应进程是否仍在运行；使用 `127.0.0.1`；代理对本机地址直连；不要用 `0.0.0.0` 替换监听地址 |
| 页面 403 | 重新复制当前进程输出的完整地址；旧地址的凭证已失效 |
| 6099 可访问但机器人无法连接 | 3001 正向 WS、当前账号配置、OneBot Token、QQ 登录状态；WebUI Token 不能代替 OneBot Token |
| Windows NapCat 已开但 WSL 连不上 | NAT / 镜像网络差异；优先将两者放在同一 Ubuntu，不公开接口来绕过问题 |
| Pillow 错误 | 运行 `/usr/bin/python3 -c 'from PIL import Image'`，确认安装在系统 Python 中；保留完整 Resources 目录 |
| 图片/GIF 未识别 | 开启识图并配置服务；大图、坏图、过多帧会被拒绝，不应编造画面 |
| 开始后没回复 | 白名单、真正 @、运行截止、额度、工作时段、主动接话是否选择沉默 |
| 发送未知后停止 | 先让对端确认，不能通过重复发送“修复” |

反馈时注明 Windows 版本、WSL 版本、CPU 架构、Swift 版本和脱敏后的错误。不要发送 API Key、控制地址、账号登录文件或完整记忆正文。
