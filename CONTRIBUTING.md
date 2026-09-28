# 贡献指南

项目持续更新、完善与迭代中。Bug 和改进建议欢迎提交 Issue；重大重构建议先描述问题与方案。

1. 使用 macOS 14+ 和 Swift 6 工具链，克隆后执行 `bash scripts/test.sh`。
2. 修改前沿调用链核对输入、状态所有权、权限、并发与失败处理；不要仅凭函数名称认定可复用。
3. 新行为补必要回归测试；文本排版等低风险改动无需添加只复述实现的测试。
4. 运行 `bash scripts/test.sh`、`bash scripts/build.sh` 和 `python3 scripts/check-public.py`。
5. PR 说明问题、最终行为、验证结果与未覆盖项；区分模拟、真实提供方、真实 QQ 对端和长期稳定性。

所有测试应使用合成账号、消息和媒体。不得提交实际 Key、Cookie、控制地址、QQ 聊天、用户配置或未经授权的图片。代码按 MIT 提交，媒体需明确许可。请使用 GitHub no-reply 邮箱保护个人邮箱。
