# 存储与定期清理

> **2026-10-25 实测限制：NapCat 4.18.41 只允许白名单内的插件，本项目自定义清理插件被拒绝，QQ 聊天数据库自动清理当前不可用。** 下文原生聊天清理算法只有源码和模拟证据，不代表在当前 NapCat 上已运行。本机已校验并加载官方 `napcat-plugin-cleaner` 1.2.0，七天旧缓存预览成功；缓存清理不等于聊天记录清理。本轮没有删除缓存、没有开启清理定时任务。

图片发送记录与定时发送槽位只保留 **7 天**，仍有 20,000 条发送记录的数量上限。同会话去重窗口最大 7 天；旧配置的 30/90 天会自动收窄，`/next` 的搜索意图保留。每次状态保存、启动恢复和插画调度会裁剪记录。

## QQ 独立环境

`scripts/qq-storage-maintenance.py` 使用本机 Lima 的 `qq-ai` 虚拟机和 NapCat 插件接口。当前版本只验证了 `cache-preview`；`install` / `dry-run` / `run` / `watch` 的原生聊天清理路径因插件限制不可用，不应启动定期任务：

```sh
# 安装本项目的 NapCat 清理插件并预览，不删除数据
python3 scripts/qq-storage-maintenance.py install
# 单独预览；只返回数量和错误，不打印账号、聊天或凭证
python3 scripts/qq-storage-maintenance.py dry-run
# 清理一次
python3 scripts/qq-storage-maintenance.py run
# 持续检查：每 6 小时检查一次，成功后至少 24 小时再清理
python3 scripts/qq-storage-maintenance.py watch
# NapCat 4.18.41：先在官方插件商店安装并启用 napcat-plugin-cleaner，再只读预览缓存
python3 scripts/qq-storage-maintenance.py cache-preview
```

这不是开机托管。`watch` 只在它的进程存活时执行；电脑重启后需重新运行。它不会启动虚拟机、重启 QQ、登录账号、恢复自动回复、发送测试消息或调用模型。停止前台任务用 Ctrl+C；后台任务 PID 写在本机 `maintenance.lock` 中，停止时先核对实际进程。独占锁避免重复调度。

默认状态位置为 `~/Library/Application Support/WeChatAIBot/qq-state.json`；`--state`、`--runtime`、`--lima` 可指定部署位置。这套脚本针对 macOS + Lima 环境；Windows/WSL 目前不能直接按上述命令验收。

原有清理规则（QQ 聊天与媒体项依赖被拒绝的自定义插件，当前未运行；官方插件仅提供独立缓存预览）：

| 数据 | 规则与保护 |
| --- | --- |
| QQ 本机聊天记录 | 只处理当前配置中启用的好友/群；重新校验登录账号，用 QQ 原生 `queryMsgsWithFilterEx` 筛选 7 天前消息，再用 `deleteMsg` 删除本机记录，随后读取确认。不是 OneBot `delete_msg` 撤回消息。每会话每轮最多 1,000 条，超量在后续检查继续处理。 |
| QQ 媒体与内部日志 | 只处理确认的账号缓存目录中 `Pic/Ptt/Video/File/log` 的普通文件，按修改时间删除超过 7 天的文件；新文件、符号链接、头像、登录信息和聊天数据库文件不删除。遇到多个账号缓存目录会拒绝自动选择。 |
| 机器人状态 | 独占状态写入锁后裁剪图片发送记录、定时槽位和日志；正在运行的引擎持锁时跳过外部写入，由新版引擎在保存时裁剪。模型调用数、发送确认数、运行截止与长期记忆不重置。 |
| 项目迭代备份 | 只匹配运行目录中的 `pre-*-state.json` 和 `*-state-backup.json`；超过 7 天才删除，并保留最新 3 份。其他文件、正式案例、验收证据和 Git 历史不在删除范围。 |
| 清理执行记录 | `maintenance-checks.jsonl` 只保留 7 天且最多 1,000 条匿名汇总；`maintenance-status.json` 只保存最近结果与最近成功时间。权限 0600，无聊天正文、账号或凭证。 |

长期记忆继续使用已有的会话隔离、条数上限和到期检索规则；清理 QQ 本机原始记录不清除机器人提炼的长期记忆。过期聊天的引用附件可能因此无法回查。QQ 数据库删除记录后可复用空页，但数据库文件不一定立刻缩小；脚本不会操作加密数据库或运行 `VACUUM`。

QQ 未登录、服务接口不存在、消息时间/归属不明确、返回结构异常或删除无法确认时，该项失败，不宣称成功。部分步骤已完成后发生错误不会自动回滚已删除的过期数据；结果按实际完成量记录。`dry-run` 的候选数只覆盖每会话首批最多 100 条，不是全部历史消息的总量。

清理安装器上传文件后会设置 `napcat:napcat` 所属关系，避免 root 所有的 0600 文件阻断插件读取。新版容器独立挂载插件目录；已有容器需按 [升级与回退](UPGRADING.md) 迁移挂载，单纯 `docker start` 不会补上挂载。

## AI 与 ChatGPT 记录范围

本机制管理**此机器人项目**的 AI 运行日志、状态备份和清理记录。识图、生图主要在内存处理；插画下载临时文件正常处理结束后删除。固定表情资源不会随聊天追加。

它不会删除 ChatGPT 云端会话、Codex 全局历史、其他项目生成文件或本项目正式文档/案例。若需要管理这些记录，须另行确定具体位置和保留范围，不能把项目清理脚本递归指向整个用户目录。

## 验证边界

2026-10-25 登录后已通过实际应用的 OneBot 账号/在线检查，桥接返回 4.18.41。官方缓存插件的三个安装文件与官方 v1.2.0 发行包逐一哈希匹配，当前账号七天预览发现 211 个旧缓存文件、81,071,942 字节；扫描结果会随消息变化。预览删除数为 0，官方插件定时任务为 0。本项目聊天清理插件被上游白名单拒绝，不能标为真实清理通过。

合成测试覆盖一周边界、会话归属、预览不删除、新文件保护、符号链接保护、原生删除确认、记忆/计数保留和 0600 权限：

```sh
node scripts/test-storage-retention.mjs
python3 scripts/test-storage-retention.py
bash scripts/test.sh
```

原生聊天清理须先解决上游插件支持条件，再在已登录环境进行 `dry-run` 与删除确认；当前不要执行 `run` 或 `watch` 作为替代。官方 `cache-preview` 只验证缓存扫描，在线、HTTP 成功或模拟测试通过不能替代实际删除确认。

参考：[NapCat 原生消息服务定义](https://github.com/NapNeko/NapCatQQ/blob/main/packages/napcat-core/services/NodeIKernelMsgService.ts)、[NapCat CleanCache 实现](https://github.com/NapNeko/NapCatQQ/blob/main/packages/napcat-onebot/action/system/CleanCache.ts)。后者是缓存清理，不等于聊天记录清理，本项目没有直接调用其无年龄筛选的全量删除逻辑。
