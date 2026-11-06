# 客户端安装指南

当前完整客户端为 `0.3.0-preview.3`，内置 NapCat `4.18.42`、QQ 后台、Node 和 MCP 模块。QQ 原始安装包单独放在[同一 GitHub 发布页](https://github.com/SAKURAfan1023/dafeiyu-bot/releases/tag/v0.3.0-preview.3)。首次使用先看[首页快速上手](../README.md#快速上手)。

## 选哪个文件

| 设备 | 客户端 | QQ 单独安装 |
| --- | --- | --- |
| Windows 10/11 x64 | `DaFeiYu-0.3.0-preview.3-windows-x64-setup.exe` | `QQ_9.9.33_260813_x64_01.exe` |
| Windows x64 便携方式 | `DaFeiYu-0.3.0-preview.3-windows-x64-portable.zip` | 同上 |
| Mac Apple Silicon，macOS 14+ | `DaFeiYu-0.3.0-preview.3-macos-arm64.dmg` | `QQ_7.0.0_260812_01.dmg`，安装到 `/Applications/QQ.app` |

QQ 文件是从腾讯官方地址取得的原始文件，未重打包；Windows 版本与 NapCat 官方 Windows OneKey 安装器所用版本一致。Mac 固定版本是待实际账号验收的配套版本，不承诺任意 QQ 版本都兼容。已有符合要求的 QQ 或 NapCat 可继续使用原部署。

客户端不需要 npm、Swift、WSL 或虚拟机。Windows 需要 [Microsoft Visual C++ x64 运行库](https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist)；图片功能另需 Python / Pillow。开发者使用的 `.tgz` 和 Source code 不属于客户端安装程序。

## Windows

1. 安装上表 QQ，再双击大肥鱼 Setup 安装。安装在当前用户目录；开始菜单会出现“大肥鱼 QQ”和“打开内置 NapCat”。桌面快捷方式可在安装时勾选。
2. 选择“打开内置 NapCat”。程序从包内完整归档准备一份可写的 NapCat，无需另行下载。双击打开目录内的 `launcher-user.bat`，Windows 10 使用 `launcher-win10-user.bat`。按控制台提示扫码，打开提示中的 WebUI 地址。
3. 按[首页第三步](../README.md#3-接通大肥鱼并试一次回复)创建本机正向 WebSocket，回到“大肥鱼 QQ”填写地址、QQ 号、OneBot Token 和模型 API Key。
4. 选择允许回复的会话，先做单次验收，再按需开始持续运行。

便携版解压后使用 `DaFeiYu.exe` 打开客户端，`Open NapCat.cmd` 打开内置 NapCat。保留整个解压目录。大肥鱼安装器不申请管理员权限、不修改系统 PATH、不增加开机服务；QQ 和 NapCat 自身的授权提示由用户按其说明处理。

## Mac

1. 安装上表 QQ 到 `/Applications/QQ.app`。打开大肥鱼 DMG，将 `DaFeiYu.app` 拖入“应用程序”。
2. 打开大肥鱼，在菜单栏的大肥鱼菜单中选择“打开内置 NapCat”。程序从包内准备完整 NapCat，再打开一同内置的官方配置工具。
3. 在配置工具中选择“切换程序入口「NapCat」”，按系统提示授权，再选择“启动 NapCat”并扫码。因为 NapCat 本体已经在本机，**不必点击下载或更新**。如系统要求访问 QQ 数据或 App 管理权限，请按提示授权相关应用。
4. 按[首页第三步](../README.md#3-接通大肥鱼并试一次回复)配置本机 WebSocket，并在大肥鱼中连接、选择回复范围和单次验收。

准备过程不会自动启动 QQ、修改 QQ 入口、扫码登录或开始回复。切换入口由你在官方配置工具中明确执行。已有 NapCat 目录和配置会保留，程序不会静默覆盖。

## npm 与 MCP

喜欢终端时，按照[首页 npm 命令](../README.md#npm-快速使用)安装并打开面板。客户端打包版本与已发布 QQ / MCP 模块版本独立管理；模块的固定版本仍为 `.2`，不用手动挑选平台后台。

安装包也自带 MCP，无需额外安装 Node。配置中的 command 与 args 分开填写，路径有空格时仍作为一个 JSON 字符串处理。

Mac 安装到“应用程序”后的配置：

```json
{
  "mcpServers": {
    "dafeiyu": {
      "command": "/Applications/DaFeiYu.app/Contents/Resources/dafeiyu-mcp.command",
      "args": []
    }
  }
}
```

Windows 用实际安装目录替换 `<安装目录>`，默认在当前用户的 `AppData/Local/Programs/DaFeiYuQQ`：

```json
{
  "mcpServers": {
    "dafeiyu": {
      "command": "<安装目录>/runtime/node.exe",
      "args": ["<安装目录>/runtime/launch.mjs", "mcp"]
    }
  }
}
```

MCP 与客户端共享后台和设置。凭证在本机面板填写；打开 Host 不会自动连接 QQ、读取记忆或开始回复。工具范围和写操作校验见 [QQ 模块说明](QQ_MODULES.md)。

## 停止、升级和卸载

关闭浏览器或 MCP Host 不会退出独立后台。先暂停并断开，再停止：

- Windows：双击安装目录内的 `Stop DaFeiYu.cmd`。
- Mac：原生客户端持有的后台随应用退出；MCP 单独启动的后台在终端执行以下两条命令。

```sh
"/Applications/DaFeiYu.app/Contents/Resources/QQRuntime/node" "/Applications/DaFeiYu.app/Contents/Resources/QQRuntime/launch.mjs" disconnect
"/Applications/DaFeiYu.app/Contents/Resources/QQRuntime/node" "/Applications/DaFeiYu.app/Contents/Resources/QQRuntime/launch.mjs" stop
```

NapCat / QQ 是独立进程，请另行退出其终端或配置工具；停止大肥鱼不会强制杀掉 QQ。

升级或卸载前停止大肥鱼与 NapCat，备份自己的数据。Windows 从“设置 → 应用”卸载；Mac 将应用移至废纸篓。用户数据保留：

| 内容 | 位置 |
| --- | --- |
| Windows 大肥鱼配置和记忆 | `%LOCALAPPDATA%/DaFeiYu` |
| Windows 内置 NapCat 的可写副本 | `%LOCALAPPDATA%/DaFeiYu/NapCat` |
| Mac 大肥鱼配置和记忆 | 用户资料库的 `Application Support/WeChatAIBot` |
| Mac NapCat 的可写副本 | 用户资料库的 `Containers/com.tencent.qq/Data/Documents/napcat` |

目录中含私人数据，不要上传到 Issue。内置归档保持原始字节；本机准备新副本时只更新包版本标记，已有副本、登录和插件不会被覆盖。

## 来源、校验和首次打开

发布页附客户端与 QQ 原始安装文件的 SHA-256 校验和；NapCat 的来源、版本和摘要固定在仓库 `desktop-release.json`，随包保留完整原始许可。NapCat 有非商业用途限制，项目 MIT 不覆盖 NapCat 或 QQ 的许可。

预览版尚无开发者证书：Mac 只有临时签名、未做 Apple 公证，Windows 未做 Authenticode 签名。系统可能提示未知开发者，请核对本仓库来源和校验和后自行决定是否允许打开。程序不会关闭或绕过系统保护。
