# 贡献指南

项目持续更新、完善与迭代中。Bug 和改进建议欢迎提交 Issue；重大重构建议先描述问题与方案。

1. 使用 macOS 14+ 和 Swift 6，或 Ubuntu 24.04 / WSL2 与 Swift 6.1.3；克隆后执行 `bash scripts/test.sh`。Linux 额外运行 `python3 scripts/test-linux-images.py` 和 `bash scripts/build-linux.sh`。
2. 修改前沿调用链核对输入、状态所有权、权限、并发与失败处理；不要仅凭函数名称认定可复用。
3. 新行为补必要回归测试；文本排版等低风险改动无需添加只复述实现的测试。
4. 运行 `bash scripts/test.sh`、`bash scripts/build.sh` 和 `python3 scripts/check-public.py`。
5. PR 说明问题、最终行为、验证结果与未覆盖项；区分模拟、真实提供方、真实 QQ 对端和长期稳定性。

所有测试应使用合成账号、消息和媒体。不得提交实际 Key、Cookie、控制地址、QQ 聊天、用户配置或未经授权的图片。代码按 MIT 提交，媒体需明确许可。请使用 GitHub no-reply 邮箱保护个人邮箱。

## 日常开发与更新

直接在克隆得到的 `dafeiyu-bot` 仓库开发，以 Git 提交为准。不要长期维护一份私人源码再手工复制到公开目录；账号、凭证、聊天和记忆应留在仓库外的运行目录，示例配置只放占位符。发布源码不会自动升级或重启已运行的机器人。

首次使用 GitHub 官方 CLI 完成登录并配置 Git 认证：

```sh
gh auth login --hostname github.com --git-protocol https --web
gh auth setup-git
```

登录在 GitHub 官方页面完成，不把密码或 Token 放进命令、源码、远程地址或 Issue。修改 Actions 工作流时还需对应权限，按授权页面核对范围；浏览器登录与命令行登录相互独立。

每次修改从最新主分支建立功能分支。已有未提交改动时先提交或暂存，不要直接覆盖工作目录：

```sh
git switch main
git pull --ff-only
git switch -c feature/your-change
# 修改代码，并运行上面的对应平台测试和构建
git add -- path/to/changed-file
git diff --cached --stat
git diff --cached
python3 scripts/check-public.py --staged
git commit -m "feat: describe the change"
git push -u origin HEAD
gh pr create
```

等待 GitHub 自动检查通过后再合并。其他机器用 `git pull --ff-only` 获取更新，按安装指南重新构建；运行数据和模型凭证无需复制进 Git。已有分支继续使用普通 `git push`，无需网页上传文件或重新打包整个项目。

`.gitignore` 只防止未跟踪文件被加入，不能清除历史提交。误跟踪的私人配置要先备份并用 `git rm --cached -- 文件路径` 解除跟踪；若凭证已经推送，必须撤销该凭证并处理历史，不能仅删除当前文件。扫描器是辅助检查，不能替代对新增内容、图片及提交作者信息的审阅。
