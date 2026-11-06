# 经典 DeepSeek 娘参考与 E 修正

用户指出第一版 E 不符合经典 DeepSeek 娘。首版仅保留了蓝发和女仆服，缺少鲸鳍耳、完整大鲸尾、弧形呆毛、深蓝至浅蓝的蓬松渐变长发；本轮先网络搜索并对照原图，再生成修正版。

## 已核对的来源

- [上善无形：鲸鱼娘原设帖](https://www.bilibili.com/opus/1231977657712771073)：原作者正文可读取，明确列出渐变蓝发、呆毛、鲸鱼尾、头鳍等特征，并标注 CC BY-NC-SA 4.0。
- [ZipZipPipe：《AI娘化》原图合集](https://www.pixiv.net/artworks/148186519)：正常比例女仆立绘为第 1 页。当前 Pixiv 页面未能直接读取；实际参考图来自下方归档，已核对 SHA-256 与归档清单一致。
- [ZipZipPipe：《大AI和小AI们》](https://www.bilibili.com/video/BV1tE9XBbErS/)：女仆版及 Q 版展示来源。当前直接访问返回 HTTP 412；作者与改编链由归档及 [LivLiv 角色署名](https://github.com/livliv-dev/player/blob/main/characters/CREDITS.md) 交叉核对。
- [图像归档及来源清单](https://github.com/shuaizenge/ai-girls/blob/main/catalog.json)：参考图 `zipzippipe-pixiv-148186519-p00.jpg`，SHA-256 为 `73264faff3511347b1b9668d5d937cbb3f2402f8bb03cc158fc8a81bfc2d077c`。同时查看作者视频的 Q 版展示截帧，以区分常规比例和 Q 版表现。

## 本轮产物

`e-classic-whale-maid-v2.png`：内置 image_gen 参考原版立绘重画，恢复鲸鳍耳、大鲸尾、弧形呆毛、深蓝至浅蓝的蓬松长发、深蓝白色长裙、鲸鱼围裙、胸前蝴蝶结与金色细边。使用正面全身构图，并保持衣着完整覆盖。完整提示词见 `prompts.json` 对应条目。

前四款保持不变；`e-classic-maid.png` 是被用户指出偏离经典形象的首版，保留为历史，对比页当前展示 v2。新版尚待用户视觉反馈，不把生成完成写成认可或模型完成。

## 署名与素材边界

原角色：上善无形；女仆二次设计：ZipZipPipe；本轮新绘：image_gen。E v2 是社区角色的参考二创，不再标为完全独立的新角色。上游原设帖及角色归档标注 CC BY-NC-SA 4.0，E 相关素材单独保留作者链及该许可声明与链接，不能套用项目的 MIT 代码许可或据此宣称可商用；2026-11-07 再次读取原作者 CC BY-NC-SA 声明，并核对 LivLiv 官方角色署名中同一原角色、女仆设计和 CC BY-NC-SA 许可；Pixiv 原页仍不可读取，不据此扩大至商业用途。原版参考图片仅存于被忽略的本机 `local/`，不复制进本目录，不打包原模型、贴图或绑定。
