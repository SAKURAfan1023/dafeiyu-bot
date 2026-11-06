import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { schemas } from './contracts.mjs';
import metadata from '../package.json' with { type: 'json' };

export function createAvatarServer(runtime) {
  const server = new McpServer({ name: 'dafeiyu-avatar', version: metadata.version }, {
    instructions: '先 avatar_list / avatar_status 查看角色与实际控制范围。打开 preview_url 并等待 renderer_ready 才可播放。工具分为发现、角色、视觉、语音、组合表演、停止。语音需显式配置本地 Qwen 模型并在预览点击开启声音。互不冲突的参数可并行，默认拒绝冲突，on_conflict=replace 仅替换冲突轨道；口型归语音所有。接受不代表完成；用 action_id 和 wait_seconds 查询 action/recent 确认完成与 inputs_reset。停止后再切换角色。断线不自动重播；状态不明时先查状态。画面左右为命名方向。没有独立手指、摄像头或麦克风控制。',
  });
  const descriptions = {
    avatar_list: 'List all five avatar models, their artwork licenses, supported actions, expressions and joint controls.',
    avatar_status: 'Read the actual model/session, voice and browser audio readiness, concurrent actions, child phases and confirmed cleanup. Optional action_id and wait_seconds (0–3) observe completion.',
    avatar_select: 'Select one of the five avatars. Refused while a motion owns the renderer; confirms the newly loaded model identity.',
    avatar_pose: 'Bounded head/gaze/eyelid/body/shoulder/elbow/wrist and expression pose. Transition, hold and return are explicit; omitted fields keep their existing owner/idle. Disjoint parameters can run alongside speech; manual mouth conflicts with audio. Screen-left and screen-right naming.',
    avatar_action: 'Play a bounded head action, look-around or a shoulder/elbow/wrist greeting. Query status for completion; never replay an uncertain action automatically.',
    avatar_stop: 'Stop speech, visual or all tracks and confirm their cleanup. Optional action_id prevents stale cancellation; omitting it addresses every current owner.',
    avatar_say: 'Stream 1–200 characters through the configured offline Chinese voice. Actual heard audio drives mouth and vowel. Omit expression to inherit the current face. Requires browser audio_ready; no recording, cloud TTS, queue or replay.',
    avatar_perform: 'Atomically preflight one speech plus either visual pose or named action. Default sync=speech_start begins the visual when first sound is heard. Pose holds through playback then returns; native motion retains its own duration. Completion includes every child and cleanup.',
  };
  for (const [name, schema] of Object.entries(schemas)) {
    server.registerTool(name, { description: descriptions[name], inputSchema: (schema.innerType ? schema.innerType() : schema).shape,
      annotations: { readOnlyHint: ['avatar_list', 'avatar_status'].includes(name), destructiveHint: false, idempotentHint: ['avatar_list', 'avatar_status'].includes(name), openWorldHint: false },
    }, async input => {
      try { const data = await runtime.dispatch(name, input); return { content: [{ type: 'text', text: JSON.stringify(data) }], structuredContent: data }; }
      catch (error) { const data = { code: error.code ?? 'AVATAR_ERROR', message: error.message }; return { isError: true, content: [{ type: 'text', text: JSON.stringify(data) }], structuredContent: data }; }
    });
  }
  return server;
}
