# 大肥鱼 / DeepSeek 少女方向图

2026-11-06：用户已认可 agent-stage 的新版日式少女风格，要求为大肥鱼制作 DeepSeek 主题角色，之后作为 MCP 工具供其他人使用。首轮生成 A–D 四款，本轮按用户要求补充经典女仆 E。用户已确定几个造型全部制作，供使用者选择，不再等待五选一。当前五款已制作可动分层与独立 Avatar MCP，制作与使用见 [五款模型说明](../../AVATAR_MODELS.md)。本目录继续保留原造型图。

| 方向 | 文件 | 主要差异 |
| --- | --- | --- |
| A 蓝白水手服 | [a-sailor.png](a-sailor.png) | 深蓝长直发、鲸鱼发夹、水手领与百褶裙；经典元气 |
| B 鲸鱼帽衫 | [b-whale-hoodie.png](b-whale-hoodie.png) | 深蓝短发、鳍状帽衫细节、日常卫衣；软萌亲近 |
| C 深海小研究员 | [c-ocean-researcher.png](c-ocean-researcher.png) | 低侧马尾、白夹克、蓝领结与海洋徽章；聪明利落 |
| D 海洋轻礼装 | [d-ocean-dress.png](d-ocean-dress.png) | 浅蓝双马尾、浪花披肩裙与鲸尾发饰；轻盈精致 |
| E 经典鲸鱼娘（修正） | [e-classic-whale-maid-v2.png](e-classic-whale-maid-v2.png) | 渐变蓬松长发、鲸鳍耳、大鲸尾、弧形呆毛、蓝白金边女仆长裙；参考经典社区形象 |

[打开五款对比页](index.html)。各图使用相近的正面全身构图，背景为浅蓝白色，供比较脸部、发型、服装与海洋元素。A–E 全部保留，前四款原图未改动。

用户随后指出首版 E 不符合经典 DeepSeek 娘。本轮已网络检索原设帖和作者图像归档，对照原版正常比例立绘及 Q 版展示，新绘 E v2；前四款不变。来源、读取限制、作者署名和许可边界见 [经典参考记录](CLASSIC-REFERENCE.md)。旧 E 保留为历史；用户已认可修正版，并授权制作五款模型。

五款模型现通过同一 MCP 入口列出、选择或切换，支持头部、注视、表情和肩肘腕细调。此处页面仅展示原始造型；实际可动预览由 `npm run preview:avatar` 启动。

生成方式：内置 `image_gen`，每个方向单独生成；完整提示词在 [prompts.json](prompts.json)，尺寸、哈希与生成文件名在 [generation-manifest.json](generation-manifest.json)。A–D 和 E 首版使用文字提示生成；E v2 以已核对的经典女仆立绘作图片参考，没有使用模型、贴图或绑定文件。

本目录为非官方 AI 生成造型方案，E v2 属于上善无形 / ZipZipPipe 社区角色的参考二创，单独保留署名和素材许可记录；不将其称为完全独立原创或套用 MIT 代码许可。图片生成不代表已经完成可动绑定、MCP 接入或第三方品牌授权。旧 DeepSeek-chan 模型及石墨素材没有被复制到本目录。
