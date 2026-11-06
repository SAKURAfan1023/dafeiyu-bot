import { AvatarError } from './contracts.mjs';

/** Connects to one explicit existing host. No port scan, redirect, second renderer or TTS worker. */
export class PreviewBridge {
  static async connect(value) {
    const url = new URL(value);
    if (url.protocol !== 'http:' || url.hostname !== '127.0.0.1' || !url.port || url.pathname !== '/' || url.search || url.username || url.password || !/^#[a-f0-9]{48}$/.test(url.hash)) throw new AvatarError('INVALID_PREVIEW_URL', 'Use the complete http://127.0.0.1:PORT/#TOKEN preview URL');
    const bridge = new PreviewBridge();
    bridge.origin = url.origin; bridge.token = url.hash.slice(1);
    bridge.session = (await bridge.read()).session_id;
    return bridge;
  }
  async read() {
    const response = await fetch(this.origin + '/api/state', { redirect: 'error', signal: AbortSignal.timeout(5000), headers: { 'X-Avatar-Token': this.token } });
    if (!response.ok) throw new AvatarError('PREVIEW_UNAVAILABLE', 'Preview authorization failed; supply its current URL explicitly');
    return response.json();
  }
  async dispatch(tool, input = {}) {
    const readOnly = ['avatar_status', 'avatar_list'].includes(tool);
    const response = await fetch(this.origin + '/api/tool', { method: 'POST', redirect: 'error', signal: AbortSignal.timeout(7000),
      headers: { 'X-Avatar-Token': this.token, 'Content-Type': 'application/json' }, body: JSON.stringify({ tool, input: { ...input, ...(!readOnly ? { expected_session: input.expected_session ?? this.session } : {}) } }) });
    if (!response.ok) throw new AvatarError('PREVIEW_UNAVAILABLE', 'The explicit preview is unavailable; no command was replayed');
    const result = await response.json();
    if (!result.ok) throw new AvatarError(result.error.code, result.error.message);
    if (tool === 'avatar_status') this.session = result.data.session_id;
    return result.data;
  }
  async close() {} // A bridge never owns or closes the shared preview/worker.
}
