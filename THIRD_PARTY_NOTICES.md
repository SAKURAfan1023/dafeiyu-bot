# 第三方与素材说明

- 项目为独立社区项目，不隶属于或代表 DeepSeek、腾讯、Pixiv、智谱、Cloudflare、Google。
- Swift / Apple 系统框架由相应平台提供。NapCat、Lima、Docker、QQ 不打包进本仓库，其代码、镜像、客户端与服务分别遵循上游许可/条款。
- NapCat 项目：https://github.com/NapNeko/NapCatQQ
- NapCat Docker：https://github.com/NapNeko/NapCat-Docker
- Lima：https://github.com/lima-vm/lima
- OneBot 11：https://github.com/botuniverse/onebot-11
- 小红书本机执行器使用 Playwright（Microsoft，Apache-2.0），由 npm 按锁文件安装，不打包登录资料。页面结构与选择器参考 `xpzouying/xiaohongshu-mcp` 固定版本；实现与来源说明见 [NOTICE](Resources/Xiaohongshu/NOTICE)。
- README 封面与 `Resources/QQStickers/` 四张示例图由本项目为公开版原创 AI 生成，按 CC0 1.0 提供（https://creativecommons.org/publicdomain/zero/1.0/）。生成记录日期：2026-09-28。商标或平台名称不在此授权范围内。
- 公开版表情库含 4 张原创示例及 33 张 [YunYueSama 蓝发鲸鱼娘](https://github.com/YunYueSama/codex-deepseek-pet/tree/7661c8b304c5400701f91da01b1a643a207331de/assets/whale) 社区素材。固定版本 `7661c8b304c5400701f91da01b1a643a207331de`；修改为图集独立帧拆分、透明留白裁剪与无损 WebP 编码，未重绘角色。按上游大肥鱼项目署名许可 1.0 保留作者、逐图来源与[完整许可及素材边界](Resources/QQStickers/WHALE-LICENSE.txt)。许可不额外授予底层角色及第三方参考权利，本项目 MIT 不覆盖图片许可。公开 Photos 画廊及下载包保留署名。
- `Resources/PhotoStickers/` 为 Photos 网页独立素材：29 张取自 [ZipZipPipe 的 B站原帖](https://www.bilibili.com/opus/1238946461156114455)，按作者原帖声明的 CC BY-NC-SA 4.0；另 59 张来自中文社区「蓝色大肥鱼」明确标为自己创作、CC0 的投稿，署名 1cyberlangke1 / MX1951，仍保留底层角色的 CC BY-NC-SA 4.0 边界。角色原作上善无形，女仆版二次设计 ZipZipPipe。图片保留原始文件，未重绘或加字；逐图链接、固定版本、完整许可及排除范围见[来源记录](Resources/PhotoStickers/licenses/SOURCES.txt)。这些网页素材不随机器人默认安装包加载，仅由用户选择导入。网站、公开构建与图库筛选均限定 DeepSeek 娘，不收录其他角色充数。
- 开发者私人环境收集的其他第三方表情不随公开版分发；本机导入默认私有，只有明确勾选公开、填写署名许可来源并经独立发布的内容才进入公开站。案例文档包含从实际消息附件取回、经匿名处理的图片预览，仅用于解释该段对话。案例界面是重新排版，不是私有运行截图。运行中搜索到的插画属于各自创作者，来源链接不等于再授权；请尊重署名与来源站点访问规则。
- `docs/assets/cases/` 中的聊天附件预览和第三方表情不适用本项目 MIT 或原创素材 CC0 授权，不作为可自由复用的素材包提供；原作者未能从消息附件中核实时，不猜测或补写署名。案例 04 的原回复标注其图片由智谱 CogView-3-Flash 生成，这不构成第三方模型或素材的额外授权。权利人可通过 Issues 联系作者更正署名或移除相关图片。

- Windows/WSL 与 Linux 使用 [Swift Crypto](https://github.com/apple/swift-crypto)（Apache-2.0）及其上游依赖，图像适配使用系统安装的 [Pillow](https://github.com/python-pillow/Pillow)（HPND）。这些依赖的许可证不会被本仓库 MIT 替代；分发编译产物时需同时保留对应许可与声明。
- Linux 的 OneBot WebSocket 连接使用 [WebSocketKit](https://github.com/vapor/websocket-kit)（MIT）及 [SwiftNIO](https://github.com/apple/swift-nio)（Apache-2.0）生态依赖，版本范围见 `Package.swift`。重新分发这些依赖或编译产物时，同样需要保留上游许可证和声明。

## 面板角色 Logo（2026-10-25）

`Resources/QQControl/logo.png` 是基于社区 Q 版角色模板，经内置 imagegen 重新生成、简化为头像构图的改编素材，并非上游原图或 DeepSeek 官方形象。

- 作者：YunYueSama
- 仓库：https://github.com/YunYueSama/codex-deepseek-pet
- 参考版本：`7661c8b304c5400701f91da01b1a643a207331de`
- 参考文件：`assets/whale/portrait.png`、`design/character-standard.png`
- 保留上游[完整素材署名许可](Resources/QQControl/LOGO-LICENSE.txt)，以及其底层第三方角色、标志不被额外授权的说明。本项目 MIT 不取消这些素材义务，不暗示上游或 DeepSeek 官方认可。
- 改编内容：头肩头像、表情与线条简化、透明背景。生成提示与设计来源见 [面板设计](docs/PANEL_DESIGN.md)。
