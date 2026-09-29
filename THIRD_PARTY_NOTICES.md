# 第三方与素材说明

- 项目为独立社区项目，不隶属于或代表 DeepSeek、腾讯、Pixiv、智谱、Cloudflare、Google。
- Swift / Apple 系统框架由相应平台提供。NapCat、Lima、Docker、QQ 不打包进本仓库，其代码、镜像、客户端与服务分别遵循上游许可/条款。
- NapCat 项目：https://github.com/NapNeko/NapCatQQ
- NapCat Docker：https://github.com/NapNeko/NapCat-Docker
- Lima：https://github.com/lima-vm/lima
- OneBot 11：https://github.com/botuniverse/onebot-11
- README 封面与 `Resources/QQStickers/` 四张示例图由本项目为公开版原创 AI 生成，按 CC0 1.0 提供（https://creativecommons.org/publicdomain/zero/1.0/）。生成记录日期：2026-09-28。商标或平台名称不在此授权范围内。
- 公开版的运行表情库不含开发者私人环境收集的第三方表情；案例文档包含从实际消息附件取回、经匿名处理的图片预览，仅用于解释该段对话。案例界面是重新排版，不是私有运行截图。运行中搜索到的插画属于各自创作者，来源链接不等于再授权；请尊重署名与来源站点访问规则。
- `docs/assets/cases/` 中的聊天附件预览和第三方表情不适用本项目 MIT 或原创素材 CC0 授权，不作为可自由复用的素材包提供；原作者未能从消息附件中核实时，不猜测或补写署名。案例 04 的原回复标注其图片由智谱 CogView-3-Flash 生成，这不构成第三方模型或素材的额外授权。权利人可通过 Issues 联系作者更正署名或移除相关图片。

- Windows/WSL 与 Linux 使用 [Swift Crypto](https://github.com/apple/swift-crypto)（Apache-2.0）及其上游依赖，图像适配使用系统安装的 [Pillow](https://github.com/python-pillow/Pillow)（HPND）。这些依赖的许可证不会被本仓库 MIT 替代；分发编译产物时需同时保留对应许可与声明。
- Linux 的 OneBot WebSocket 连接使用 [WebSocketKit](https://github.com/vapor/websocket-kit)（MIT）及 [SwiftNIO](https://github.com/apple/swift-nio)（Apache-2.0）生态依赖，版本范围见 `Package.swift`。重新分发这些依赖或编译产物时，同样需要保留上游许可证和声明。
