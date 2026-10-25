# 面板设计与素材来源

2026-10-25：QQ 与微信采用独立左侧目录；macOS 原生客户端和本机 Web 共用品牌素材。Web 的微信目录只指引到原生客户端，没有新增微信网页操作接口。

## 视觉与操作

参考 Awwwards 的 [Superlist（2021-04-19 SOTD）](https://www.awwwards.com/sites/superlist) 和 [Lusion（2019-05-20 SOTD）](https://www.awwwards.com/sites/lusion)。作品的获奖信息和页面结构已实际查看；下面是本项目对设计的转化，不代表 Awwwards 对本项目背书，也没有复制其源码或素材。

- 强调字级、留白和清楚的视觉锚点，采用墨色侧栏、暖白工作区、浅芽绿选中态与蓝色主要按钮。
- Logo 采用社区 Q 版 DeepSeek 娘的头像化重绘，替换旧的文字占位与动物鲸鱼草案。
- 连接页提供三步导航和真实状态；没有虚构流量图、在线率或运行成功指标。
- 图片工具分成三个子页；所有编辑器继续保留在原有状态所有者内，切页不清空草稿。
- 「查看修改」定位待保存区域；回复、范围与记忆仍共用原保存事务，图片工具各自保存。未修改时不显示回复保存条。
- 问号支持悬停、点击和键盘；Web 支持 Esc 收起。异常、配置冲突、额度、未保存内容继续直接显示。
- 左侧底部新增「使用指南」，将 5 步入门与常见问题集中展示，每步只导航到对应配置；不自动连接或启动。微信说明独立标注测试状态。
- 清除装饰性英文编号、重复草稿说明和未调用占位；正常同步不占位置，异常、待提交、凭证载入状态与真实执行结果保留。
- 动效限定为短暂的内容进入与按钮反馈，遵循减少动态效果设置；无滚动劫持或无限动画。

## Logo 生成记录

使用内置 **imagegen**，以网上可核对的社区参考图重绘。参考作者 **YunYueSama**，仓库 [codex-deepseek-pet](https://github.com/YunYueSama/codex-deepseek-pet)，版本 `7661c8b304c5400701f91da01b1a643a207331de`；文件为 `assets/whale/portrait.png` 与 `design/character-standard.png`。参考图没有作为本项目原创素材重新发布。

产物：`Resources/QQControl/logo.png`，透明 PNG；素材许可与署名见 [第三方声明](../THIRD_PARTY_NOTICES.md) 和 [完整许可](../Resources/QQControl/LOGO-LICENSE.txt)。本项目的改编不代表 DeepSeek 官方认可。

最终提示词：

> Create a single cute CHIBI AVATAR LOGO of DeepSeek whale-maid girl, directly using the two supplied online community character references as the visual template. Image 1 is the identity and palette reference. Image 2 is the expression and line-quality reference; especially the slightly smug cute face at bottom left. This is an original head-and-shoulders redraw for a personal chatbot, not a collage or screenshot. Preserve the distinctive long deep-periwinkle blue hair with fluffy curled side locks, little ahoge, small blue-and-white WHALE FIN ears with blue bows, white ruffled maid headband, round soft face and navy/white maid collar. Head very large, shoulders tiny; rounded cheeks, large but SIMPLE blue eyes, gently half-lidded expression, very small w-shaped closed smile, subtle peach blush, one small hand touching her cheek. Make her disarmingly cute and a little silly, not sexy, glamorous or realistic. STYLE: delicate thin dark-blue hand-drawn anime linework, soft flat pastel cel colors, only one restrained shadow, broad simple shapes like a charming Japanese doujin chibi sticker drawn by an illustrator. Avoid the generic AI game-avatar look: NO thick black vector outlines, NO enormous glass gemstone eyes, NO shiny plastic hair, NO airbrushing, NO 3D, NO elaborate gradients, NO photorealistic lighting, NO floating sparkles or props, NO animal-whale replacing the girl. Front-facing friendly head portrait, face and head occupy 85% of the square canvas, all hair and headband contained within a small safe border. Transparent background, no text, no watermark, no brand lettering, no frame, exactly one avatar. Prioritize similarity to these community chibi templates over invented redesign details.

## 验证范围

真实 QQ 自动回复保持暂停；本轮不连接真实 QQ、不发送测试消息、不调用对话模型。Web 使用隔离配置检查草稿、保存、重载、导航、提示与断言；原生使用合成数据渲染。Computer Use 本机管道不可用，原生真实点击验收尚未完成，不能用渲染或编译代替。

本轮回归：应用 84 项测试、核心 76 项测试、宿主/Node 清理测试均通过；Release 构建及签名校验通过。本机 HTTP 与合成 OneBot 回归覆盖静态素材、鉴权、冲突版本、配置保存回滚和暂停清队列。18 张原生合成渲染包含教程、自定义窗口和工具保存异常；Web 实际点击核对教程跳转、常见问题展开、草稿返回与放弃、无效账号报错、工具分区和零发送计数；隔离后台暂停后，超时警告保持可见，恢复后正常同步提示自动隐藏。

默认配置迭代：网页首屏预填原生默认参数，后台返回前保持表单不可编辑；加载后以已有配置为准。网页和客户端均支持当前页「使用推荐配置」，仅修改草稿，保留账号、凭证、会话范围、定时目标与画师。新增默认值一致性测试及 5 个页面的草稿边界测试；浏览器延迟状态夹具验证首屏无数字空值、后续加载自定义值，合成提交核对账号与凭证保留。

性格迭代：默认性格改为面板内的选择列表，支持键盘操作；新增 Web 弹窗与原生自定义窗口。角色名、prompt、字数和配图写入原回复草稿，保存沿用配置版本检查。取消不改设置，检测到外部配置更新时保留输入并阻止覆盖。新字段兼容旧配置；空 prompt、超长文本、控制字符和未定义的会话自定义切换被拒绝。内置风格不带入已保存的自定义 prompt。

验证：Web 实际点击覆盖内置切换、保存、取消、空值校验、应用与重载后编辑；合成 OneBot 和模型协议夹具确认自定义 prompt 仅进入相应会话的生成、复核请求。没有调用真实模型或向真实 QQ 发送验收消息，不能据此声称模型每次都能按人设理解。原生使用合成渲染，真实点击验收仍受 Computer Use 管道故障影响。
