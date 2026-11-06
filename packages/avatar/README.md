# DaFeiYu Avatar MCP

五款可选择的二次元少女，独立于 QQ / 微信运行：蓝白水手服、鲸鱼帽衫、深海小研究员、海洋轻礼装、经典鲸鱼女仆。默认面部近景、双臂自然垂放，支持十种表情、八种动作、方向与肩肘腕细调，以及本地流式少女声和随实际声音变化的口型。

## 安装和预览

需要 Node.js 22+、支持 WebGL2 / Web Audio 的桌面浏览器。

```sh
npx --yes @sakurafan1023/avatar@0.2.0 preview
```

打开终端给出的本机地址，等“模型已连接”。“全身”可查看完整模型。语音是可选能力；未配置时仍能使用五款角色和全部视觉工具，不启动摄像头、麦克风或 QQ。

## MCP 接入

```json
{
  "mcpServers": {
    "dafeiyu-avatar": {
      "command": "npx",
      "args": ["--yes", "@sakurafan1023/avatar@0.2.0"]
    }
  }
}
```

先调用 `avatar_status`，打开其 `preview_url`，等 `renderer_ready=true`。默认启动一个新角色窗口；若已有独立预览，希望多个客户端控制同一角色和同一语音模型，使用：

```sh
npx --yes @sakurafan1023/avatar@0.2.0 connect-preview --url 'http://127.0.0.1:PORT/#TOKEN'
```

将完整 URL 换成该预览输出的地址，并在 MCP 配置的 args 中填入 `connect-preview`、`--url`、完整地址。地址含本机访问令牌，不要公开。连接入口只访问明确指定的 loopback 服务，不扫描端口、不跟随重定向、不重复启动模型；关闭连接客户端不会关闭原预览。直接启动的 MCP Host 关闭时会清理它自己拥有的预览和语音子进程。

## 本地少女声

当前语音后端是 **Qwen3-TTS VoiceDesign 1.7B MLX 6bit**，需 Apple Silicon Mac、Python 3.12 和约 2.7 GB 本地模型文件。Windows / Linux 可运行视觉模块；本包未提供其本地语音后端，也没有云端替代或浏览器朗读回退。

在自己的工作目录显式安装，模型下载仅发生在下面这条安装命令中；运行时始终离线：

```sh
npm install --save-exact @sakurafan1023/avatar@0.2.0
python3.12 -m venv local/tts/venv
local/tts/venv/bin/python -m pip install -r node_modules/@sakurafan1023/avatar/voice/requirements.txt
local/tts/venv/bin/hf download mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-6bit --revision ffc6545dc9cb086950aa46c6cd3db490e6ece3e1 --local-dir local/tts/qwen3-design-6bit
mkdir -p config
cp node_modules/@sakurafan1023/avatar/config/local-voice.example.json config/local-voice.json
npx dafeiyu-avatar preview --voice-config config/local-voice.json
```

配置中的 python / model / cache 相对于配置文件所在目录；保留虚拟环境 `bin/python` 路径，不要改成它指向的系统 Python。可以修改 `label`、音色描述 `instruct` 和固定随机种子 `seed`；这些只能在启动配置中设置，工具调用不能传任意模型、命令或文件路径。自备本地 Qwen3 CustomVoice 模型时可选 `speaker`，VoiceDesign 忽略该字段。配置和缓存放在自己的私有目录，不提交仓库。

打开预览后点击 **“开启声音”**。预热完成后可输入文字试听，或通过 MCP 使用 `avatar_say` / `avatar_perform`。每个新页面都需要开启声音；“已生成”不表示已播放。配置正确但生成失败时会返回失败状态，不伪造发声成功。首次预热和取消生成后的重新预热会增加等待，后续正常讲话复用同一个本机模型进程。

MCP 独立启动语音：在 args 末尾添加 `"--voice-config", "<absolute-config-path>/local-voice.json"`。也可以先启动带语音的独立 preview，再用上面的 `connect-preview` 共享它。

## 工具与组合调度

| 类别 | 工具 | 行为 |
| --- | --- | --- |
| 发现 | `avatar_list` | 五款形象、素材许可、动作、表情和实际控制范围 |
| 状态 | `avatar_status` | 模型和服务会话、语音/浏览器就绪状态、所有运行项及完成历史；可按 action_id 等待 0–3 秒 |
| 角色 | `avatar_select` | 切换并确认新模型身份；运行中须先停止 |
| 视觉 | `avatar_pose` | 头部三轴、注视、眼睑、眉口、身体、双侧肩肘腕、表情及进入/停留/回位 |
| 视觉 | `avatar_action` | 点头、摇头、侧头、轻跃、含蓄低头、自然环视、左右手招呼 |
| 语音 | `avatar_say` | 1–200 字离线流式说话；默认继承当前表情，也可明确指定 expression |
| 组合 | `avatar_perform` | 一句 speech + 一个 visual 或 action，完整检查后一起接受；默认声音实际开始时起动作 |
| 停止 | `avatar_stop` | scope=speech / visual / all；可按 action_id 停止并确认对应输入复位 |

说话示例，默认保留现有表情：

```json
{"text":"你好呀，今天也一起加油吧。","call_id":"greeting-1"}
```

`avatar_perform` 配表情、视线和轻微歪头：

```json
{"speech":{"text":"让我想一想，马上告诉你。"},"visual":{"expression":"thinking","head":{"tilt":0.12},"eyes":{"gaze_x":0.2},"transition_seconds":0.6,"return_seconds":0.85},"sync":"speech_start","call_id":"thinking-1"}
```

`avatar_perform` 边说边招手：

```json
{"speech":{"text":"你好呀，很高兴见到你。"},"action":"wave-left"}
```

组合中的 visual 姿态保持到实际声音播完，再按 return_seconds 回位，hold_seconds 不控制讲话长度。action 保留自己的动作时长，不为等语音而循环。`sync="now"` 可明确要求立即起动作。任何子项失败都会停止该组合剩余输出；已听到的声音无法回滚。

不同参数可以并行：说话时能另外调整头部、注视或手臂；省略字段继续当前拥有者或自然状态。静态表情的嘴型让位于语音口型，眉眼仍保留。手动嘴部控制与发声冲突。同一参数默认拒绝重复占用；`on_conflict="replace"` 明确替换冲突的语音或视觉轨道，停止视觉不会顺带打断仍在说的话。一个视觉轨道内的相关参数一起替换。

方向量为 [-1,1]，闭眼、嘴部开合和强度为 [0,1]；左右按画面命名。头部正值为向右、抬头、右侧歪头；视线正值为向右、向下；手臂正值为向外轻举。单独 pose 的 transition_seconds / return_seconds 为 0.25–3 秒，hold_seconds 为 0–15 秒。十种表情按日常、情绪、交流分组，`expression_profiles` 提供用途及推荐节奏。

`accepted=true` 仅表示接受。用 `avatar_status({"action_id":"…","wait_seconds":3})` 查看 action 或 recent，确认 `completed` 与 `inputs_reset=true`；组合还包含 children 状态。提供 `call_id` 可避免重试重复执行；`expected_model` 和 `expected_session` 拒绝过期调用。状态不明确先查询；断线记为 uncertain，不自动重播。无自动排队。语音单句最长约 58 秒，生成/播放分别有超时及数据边界。

## 模型与许可

每款包含原位分层 PNG、LivLiv v4 模型、关节和表情配置、封面、哈希清单。发根、刘海、耳侧和脸部共享连续表面；净肤底图清除旧五官，活动眼口不带矩形肤色贴片。头部适合正脸附近的小角度活动；手指未逐指绑定，不支持握拳、比心或手心翻转。这是 2.5D LivLiv 模型，不能当作 Cubism MOC / VTube Studio 模型。

代码及四款原创素材为 MIT；经典女仆款为上善无形 / ZipZipPipe 社区角色二创，素材单独遵循 **CC BY-NC-SA 4.0（非商业、署名、相同方式共享）**。播放器为 Apache-2.0，见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。未打包上游角色原画、Graphite 模型、原始 MOC 或 TTS 权重。

源码、制作过程、同镜头修复对比及重建方式见 [仓库模型说明](https://github.com/SAKURAfan1023/dafeiyu-bot/blob/main/docs/AVATAR_MODELS.md)。源码开发可运行 `npm run test:avatar`、`npm run test:avatar:browser`；实际本地语音检查为 `node scripts/check-avatar-voice.mjs <private-output-dir> <private-voice-config>`。软件通过和截图复核不代表用户已经完成自然度或音色听感验收。
