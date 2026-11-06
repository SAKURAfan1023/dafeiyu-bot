# Avatar code and artwork

The MCP host, UI, authoring scripts and original additions use the repository's MIT license.

The browser player is based on [LivLiv Player](https://github.com/livliv-dev/player), commit `0ffb70f2b815d924ab10b07fa892c413846a71cd`, version 0.3.0, under Apache-2.0. Its LICENSE, NOTICE and modification record are included in `web/player/`. DaFeiYu adds `Player.setJointPose`, pre-body mesh joint transforms, expression opacity correction, and controller-owned PCM streaming through the existing SpeechPlayer audio-clock hooks. The local Qwen worker protocol follows this workspace's agent-stage implementation; it contains no reference artwork or voice weights. No upstream sample artwork, Cubism Core, MOC files or original model textures are bundled.

Models sailor, hoodie, researcher and ocean-dress use this project's approved AI-generated character artwork and newly generated occlusion plates under MIT. These are unofficial ocean-themed characters, not official DeepSeek characters or endorsements. Brand rights remain with their owners.

## Classic whale maid artwork: CC BY-NC-SA 4.0

Original whale-girl character: **上善无形**. Maid redesign: **ZipZipPipe**. This project's neutral master, occlusion plates, blink/mouth artwork and sprite extraction/rigging are AI-generated adaptations and technical modifications of the referenced community design. This model's ARTWORK is separate from the MIT code license and follows the upstream declared [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) terms: attribution, noncommercial use and share-alike. Do not infer commercial artwork rights from the code license or from AI regeneration. No endorsement is implied.

- Original character and author's license declaration: https://www.bilibili.com/opus/1231977657712771073
- Maid design collection: https://www.pixiv.net/artworks/148186519
- Creator's showcase: https://www.bilibili.com/video/BV1tE9XBbErS/
- Reference archive/provenance: https://github.com/shuaizenge/ai-girls/blob/main/catalog.json
- Cross-check: https://github.com/livliv-dev/player/blob/main/characters/CREDITS.md

The original author's CC BY-NC-SA declaration and LivLiv's matching author/maid-design credit were rechecked on 2026-11-07. The Pixiv portrait was checked through its byte-verified archive; its live page could not be read, and the creator's video previously returned HTTP 412. This does not grant any commercial rights. Original reference images and LivLiv's adapted model files are not bundled. All five models in this package are newly rendered and rigged adaptations or original designs.

## Optional local voice

The recommended Qwen3-TTS MLX VoiceDesign model is published by mlx-community under Apache-2.0: https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-6bit . Model weights and the Python environment are installed separately by the user, never included or automatically downloaded by this package. Dependency licenses remain applicable to the separately installed environment.
