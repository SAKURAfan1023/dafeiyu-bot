import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';

export function createServer(qq, runtime) {
  const server = new McpServer({ name: 'dafeiyu', version: '0.3.0-preview.2' }, {
    instructions: '先调用 qq_status，使用最近返回的账号、后台代次和配置版本执行写操作。首次保存连接允许旧账号为空。打开工具不会自动连接或回复；只有用户明确要求时才能启动已保存范围。凭证仅在本机面板配置，默认不读取记忆。提交后超时不自动重试，先重新读取状态。客户端和 MCP 共用后台，Host 关闭不退出后台。'
  });
  const expected = { account: z.string().regex(/^[1-9]\d*$/), generation: z.string().uuid(), revision: z.string().uuid() };
  const result = value => ({ content: [{ type: 'text', text: JSON.stringify(value) }], structuredContent: value });
  const handler = fn => async input => {
    try { return result(await fn(input)); }
    catch (error) {
      if (error?.code === 'QQ_STATE_CHANGED') {
        return { isError: true, content: [{ type: 'text', text: 'QQ 账号、后台代次或配置版本已变化。本次操作未提交；请先重新读取状态。' }],
          structuredContent: {code:'QQ_STATE_CHANGED',submitted:false} };
      }
      return { isError: true, content: [{ type: 'text', text: 'QQ 操作未确认完成。请重新读取状态；如已提交，不要重复发送。' }] };
    }
  };
  const write = async ({ account, generation, revision, ...input }) => qq.action(runtime, input, { account, generation, revision });
  server.registerTool('qq_status', {
    description: '查看已安装 QQ 后台的账号配置、连接、运行、额度与发送状态；不会连接账号或启动回复，不包含记忆内容。',
    inputSchema: {}, annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true }
  }, handler(() => qq.status(runtime)));
  server.registerTool('qq_contacts', {
    description: '查看当前已核对账号的好友和群列表以及已配置会话；不会主动读取聊天或发送消息。',
    inputSchema: {}, annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true }
  }, handler(async () => {
    const state = await qq.status(runtime);
    return { connected: state.connected, contacts: state.contacts, targets: state.config.targets, expected: qq.expectation(state) };
  }));
  server.registerTool('qq_run_control', {
    description: '按用户明确指令暂停、断开或启动已保存范围的 QQ 自动回复。start 会对该范围产生真实回复；账号凭证须先在本机面板或 CLI 配置。默认时长 15 分钟。',
    inputSchema: { ...expected, action: z.enum(['pause','disconnect','start']), singleReply: z.boolean().optional(), durationMinutes: z.number().int().min(1).max(4320).default(15) },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false }
  }, handler(write));
  server.registerTool('qq_save_connection', {
    description: '仅保存 QQ 本机 OneBot 地址和预期账号，不安装 NapCat、不连接、不开始回复；配置版本必须来自最近一次状态。',
    inputSchema: { ...expected, account: z.string().regex(/^(?:[1-9]\d*)?$/), endpoint: z.string().regex(/^ws:\/\/127\.0\.0\.1:[0-9]+\/?$/), expectedSelfID: z.string().regex(/^[1-9]\d*$/) },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true }
  }, handler(input => write({ ...input, action: 'saveConnection' })));
  server.registerTool('qq_manage_target', {
    description: '按明确指令添加/移除已知会话或设置人设。添加不等于启用；启用范围须另保存。仅接受当前账号联系人中的目标。',
    inputSchema: { ...expected, action: z.enum(['add','remove','setPersona']), target: z.string().max(100), personaStyle: z.string().max(100).optional() },
    annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: false }
  }, handler(write));
  server.registerTool('qq_settings', {
    description: '保存现有 QQ 人设、回复范围、记忆或图片工具设置。不是任意 OneBot 操作；服务端校验字段。不得传入密码或模型密钥；保存设置不会开始回复。',
    inputSchema: { ...expected, action: z.enum(['save','saveArtwork','saveVisualTools','saveImageGeneration']), settings: z.record(z.unknown()) },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true }
  }, handler(({ settings, ...input }) => {
    const allowed = new Set(['ai','persona','enabled','onlineEnabled','visionEnabled','memoryEnabled','memoryOptions',
      'groupParticipationEnabled','groupParticipationEvery','artwork','visualTools','imageGeneration']);
    if (Object.keys(settings).some(key => !allowed.has(key))) throw new Error('Unsupported setting');
    return write({ ...input, ...settings });
  }));
  server.registerTool('qq_memory', {
    description: '仅在用户要求时查询当前账号已保存的机器人记忆；不是 QQ 全量聊天历史。',
    inputSchema: { account: z.string().regex(/^[1-9]\d*$/), target: z.string().max(100).optional() },
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true }
  }, handler(async ({ account, target }) => {
    const state = await qq.status(runtime, { includeMemory: true });
    if (state.config.expectedSelfID !== account) throw new Error('Account changed');
    return { account, memories: (state.memories ?? []).filter(item => !target || item.key === account + ':' + target) };
  }));
  return server;
}
