# 大肥鱼客户端安装包 · 0.3.0-preview.2

普通用户从 [GitHub Release](https://github.com/SAKURAfan1023/dafeiyu-bot/releases/tag/v0.3.0-preview.2) 下载与系统匹配的安装包。客户端包内含运行所需的 Node 和 QQ 模块，无需 npm、Swift、WSL 或虚拟机。QQ、NapCat 和模型服务仍由用户自行配置，图片功能另需 Python / Pillow。

| 系统 | 文件 | 安装方式 |
| --- | --- | --- |
| Windows x64 | `DaFeiYu-0.3.0-preview.2-windows-x64-setup.exe` | 双击安装，从开始菜单打开“大肥鱼 QQ”；桌面快捷方式可选 |
| Windows x64 便携版 | `DaFeiYu-0.3.0-preview.2-windows-x64-portable.zip` | 解压后打开 `DaFeiYu.exe`，保留整个目录 |
| Mac Apple Silicon | `DaFeiYu-0.3.0-preview.2-macos-arm64.dmg` | 打开 DMG，将 `DaFeiYu.app` 拖入“应用程序”后打开 |

GitHub 中的 `.tgz` 是给 npm 使用的模块归档；Source code 是源码。它们不属于上表的客户端安装包。Intel Mac、Windows ARM64 暂未提供客户端包。

## 系统要求与首次打开

Mac 需要 macOS 14+ 和 Apple Silicon；Windows 需要 Windows 10/11 x64 及 Microsoft Visual C++ x64 运行库。运行库可从 [微软官方页面](https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist)获取。Windows 安装程序只安装到当前用户目录，不申请管理员权限，不修改系统 PATH，不注册开机启动或后台服务。

这是未取得开发者证书的预览版。Mac 仅有本机临时签名，未做 Apple 公证；Windows 安装程序未做 Authenticode 签名，系统可能提示无法验证开发者。请核对本仓库的发布来源与 SHA-256，并由你决定是否在系统界面允许打开；安装包不会关闭或绕过系统保护。

Windows 客户端打开本机浏览器面板。Mac 提供现有原生界面，保留 QQ、社交和微信入口；社交浏览器依赖仍按项目的社交安装说明单独准备，微信仍在测试。打开客户端不会自动连接 QQ 或开始回复。

## 配置与停止

自行准备 QQ / NapCat 后，在客户端填写 OneBot 正向 WebSocket 地址、预期 QQ 账号和模型凭证。先连接并核对实际身份，再保存允许回复的范围并明确启动。

关闭浏览器或 MCP Host 不会停止独立 QQ 后台。Windows 可先在面板断开，再双击 `Stop DaFeiYu.cmd`；Mac 原生客户端持有的后台随应用退出，MCP 单独启动的后台可用面板断开并停止。运行中的独立后台也可执行包内 `launch.mjs disconnect` 后执行 `launch.mjs stop`。

升级或卸载前先断开并停止后台，避免替换正在使用的文件。Windows 可在“设置 → 应用”卸载；Mac 将应用移至废纸篓。用户数据保留：Windows 为 `%LOCALAPPDATA%\DaFeiYu`，Mac 为用户资料库的 `Application Support/WeChatAIBot`。安装与卸载不会删除聊天配置或记忆。

## 使用包内 MCP

安装包与原有 npm 入口共享同一份用户数据和后台。MCP 不自动连接 QQ 或启动回复，凭证仍在本机面板填写。

Mac 安装到“应用程序”后，Host 配置：

```json
{
  "mcpServers": {
    "dafeiyu": {
      "command": "/Applications/DaFeiYu.app/Contents/MacOS/dafeiyu-mcp",
      "args": []
    }
  }
}
```

Windows 使用安装目录中内置的 `node.exe`，将下面路径中的 `<安装目录>` 替换为实际目录；默认在当前用户的 `AppData/Local/Programs/DaFeiYuQQ`：

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

路径中含空格时仍按 JSON 字符串填写，不能把 command 和参数拼成一个字符串。完整工具范围与权限见 [QQ 模块说明](QQ_MODULES.md)。Windows 本轮安装和运行测试使用合成账号，真实 QQ 扫码和消息收发仍需用户环境验收。
