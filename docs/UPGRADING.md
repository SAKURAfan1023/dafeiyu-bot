# QQ 桥接升级与回退

当前部署脚本固定为 NapCat **v4.18.41** 的官方 Docker 发布镜像，分别锁定 Linux amd64 / arm64 摘要；不使用随时间变化的 `latest`。版本来源：[上游发布说明](https://github.com/NapNeko/NapCatQQ/releases/tag/v4.18.41)。

升级前先在面板暂停并退出回复引擎。升级脚本只管理 QQ 桥接，不恢复自动回复、不延长截止时间、不重置模型或发送计数。原生清理测试也应先预览，不把管理页面可访问当作 QQ 已登录。

## macOS + Lima

在项目目录更新脚本，然后将它们复制到已启动的虚拟机：

```sh
git pull --ff-only
limactl copy deploy/qq-container-create.sh qq-ai:qq-runtime/qq-container-create.sh
limactl copy deploy/qq-container-upgrade.sh qq-ai:qq-runtime/qq-container-upgrade.sh
limactl copy deploy/qq-container-entrypoint.sh qq-ai:qq-runtime/qq-container-entrypoint.sh
limactl shell qq-ai bash qq-runtime/qq-container-upgrade.sh
```

如果 `limactl` 不在 PATH，使用本机安装位置。虚拟机需已启动；脚本不会安装开机托管。

## Windows WSL / Linux Docker

在运行 QQ 容器的 Linux 环境执行：

```sh
git pull --ff-only
cp deploy/qq-container-{create,upgrade,entrypoint}.sh "$HOME/qq-runtime/"
bash "$HOME/qq-runtime/qq-container-upgrade.sh"
```

脚本先下载镜像并检查 QQ、NapCat 发行包和启动依赖，再停旧容器。只有挂载结构符合本项目布局才继续；额外挂载或不同账号数据卷会拒绝处理。

## 备份与验证

每轮升级在 **运行 QQ 的 Linux 环境** 的 `~/qq-runtime/backups/时间戳/` 创建权限受限的冷备份：账号数据卷、配置、插件和旧容器元数据。旧容器保留为 `qq-ai-before-时间戳`；插件新增独立持久化挂载，避免重建丢失。QQ 与清理插件以 `napcat` 用户运行，清理安装器写入的文件也归该用户所有。

备份包含私人登录和聊天数据，不要提交 Git 或上传 Issue。虚拟机内的备份不能抵御整台虚拟机丢失，重要数据应另复制到宿主机私人目录。

升级后依次核对：管理接口、实际 NapCat/QQ 版本、登录与核心就绪、OneBot 账号/在线状态、既有白名单与自身消息上报、插件加载与清理预览。基础收发、引用与图片仍需指定会话的真实验收。自动测试与无登录启动不能替代登录及对端结果。

## 回退

脚本打印本轮准确的回退命令，在同一个 Linux 环境执行，例如：

```sh
bash "$HOME/qq-runtime/qq-container-upgrade.sh" rollback "$HOME/qq-runtime/backups/本轮时间戳"
```

回退会停止当前容器，保留它和升级后数据的恢复副本，然后恢复本轮冷备份并启动旧容器。**升级后新增的本机聊天与配置不并入旧备份**；请先确认需要回到升级前状态。回退不启动回复引擎。不要手动同时启动旧、新两个容器登录同一账号。

保留旧镜像、旧容器和冷备份，直到本轮验收完成。脚本不会自动删除这些升级恢复点；释放空间时需单独确认保留范围。

## 2026-10-25 本机升级记录

- Apple Silicon + Lima + Linux arm64，旧版 NapCat 4.18.28 / QQ 3.2.30-50969，已切换到 NapCat 4.18.41 / QQ 3.2.34-53644。
- ARM 镜像固定摘要与官方发布清单一致；镜像内 `NapCat.Shell.zip` 的 SHA-256 与上游发行资产一致。
- 账号、配置和旧插件已冷备份，另复制到宿主机私人目录；旧容器保持停止，未删除。机器人配置/记忆/计数文件与升级前备份逐字节相同。
- 已验证管理接口可访问、插件持久化挂载存在、容器不自动重启，以及容器内真实 `napcat` 用户能读取安装后的插件。额外的运行用户权限回归通过。
- 首轮创建遇到旧目录已归容器用户、VM 普通用户无法检查凭证文件的问题；改为特权只读检查后创建成功。源码自动测试 156 项、清理脚本测试、macOS 发布构建和签名通过。
- 用户扫码后，QQ 登录与核心就绪为真；临时只读探针和实际编译应用均通过 OneBot 账号/在线核对，协议返回 NapCat.Onebot 4.18.41 / v11，自身消息上报仍开启。机器人状态文件仍与升级前一致，未启动自动回复、未新增 QQ 发送；不能当成完整收发验收。实际回退尚未执行。
- 新版白名单拒绝本项目自定义清理插件。已通过官方插件商店安装 `napcat-plugin-cleaner` 1.2.0，启用前核对三个安装文件与官方发行包哈希一致；七天缓存预览通过，未删除文件、未配置定时任务。聊天数据库清理仍不可用，见 [存储限制](STORAGE.md)。
