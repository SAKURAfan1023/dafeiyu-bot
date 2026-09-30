import fs from 'node:fs/promises';
import path from 'node:path';

const WEEK = 7 * 86400;
let busy = false;

// Keep identity/date validation next to the only native deletion call.
export function oldMessageIDs(messages, peer, cutoff) {
  if (!Array.isArray(messages)) throw new Error('Invalid history response');
  const ids = [];
  for (const m of messages) {
    const time = Number(m.msgTime);
    if (String(m.peerUid) !== peer.peerUid || Number(m.chatType) !== peer.chatType ||
        !/^[1-9]\d*$/.test(String(m.msgId)) || !Number.isFinite(time) || time <= 0) {
      throw new Error('History identity/date validation failed');
    }
    if (time < cutoff) ids.push(String(m.msgId));
  }
  return [...new Set(ids)];
}

export async function pruneMedia(root, cutoff, dryRun) {
  const result = { files: 0, bytes: 0, errors: 0 };
  async function visit(dir) {
    let stat;
    try { stat = await fs.lstat(dir); } catch (e) { if (e.code !== 'ENOENT') result.errors++; return; }
    if (!stat.isDirectory() || stat.isSymbolicLink()) return;
    const entries = await fs.readdir(dir, { withFileTypes: true }).catch(() => { result.errors++; return []; });
    for (const entry of entries) {
      const file = path.join(dir, entry.name);
      const before = await fs.lstat(file).catch(() => null);
      if (!before || before.isSymbolicLink()) continue;
      if (before.isDirectory()) { await visit(file); continue; }
      if (!before.isFile() || before.mtimeMs / 1000 >= cutoff) continue;
      if (!dryRun) {
        const after = await fs.lstat(file).catch(() => null);
        if (!after || !after.isFile() || after.ino !== before.ino || after.mtimeMs !== before.mtimeMs) continue;
        try { await fs.unlink(file); } catch { result.errors++; continue; }
      }
      result.files++; result.bytes += before.size;
    }
  }
  await visit(root);
  return result;
}

export async function cleanHistory(service, peer, cutoff, dryRun) {
  if (typeof service.queryMsgsWithFilterEx !== 'function' || typeof service.deleteMsg !== 'function' ||
      typeof service.getMsgsByMsgId !== 'function') throw new Error('Local history API unavailable');
  let candidates = 0, deleted = 0;
  try {
    for (let batch = 0; batch < 10; batch++) {
      const data = await service.queryMsgsWithFilterEx('0', '0', '0', {
        chatInfo: peer, filterMsgType: [], filterSendersUid: [],
        filterMsgFromTime: '1', filterMsgToTime: String(Math.floor(cutoff) - 1),
        isReverseOrder: false, isIncludeCurrent: true, pageLimit: 100
      });
      if (data.result !== 0 || !Array.isArray(data.msgList)) throw new Error('History query failed');
      const ids = oldMessageIDs(data.msgList, peer, cutoff);
      candidates += ids.length;
      if (dryRun || !ids.length) break;
      // deleteMsg deletes local records. Never use recallMsg/delete_msg (message recall).
      await service.deleteMsg(peer, ids);
      const check = await service.getMsgsByMsgId(peer, ids);
      if (check.result !== 0 || !Array.isArray(check.msgList) ||
          check.msgList.some(m => ids.includes(String(m.msgId)))) throw new Error('Local deletion not confirmed');
      deleted += ids.length;
    }
  } catch (error) { error.counts = { candidates, deleted }; throw error; }
  return { candidates, deleted, capped: !dryRun && deleted >= 1000 };
}

export async function plugin_init(ctx) {
  ctx.router.post('/cleanup', async (req, res) => {
    if (busy) { res.status(409).json({ code: -1, message: 'Cleanup already running' }); return; }
    busy = true;
    try {
      const policy = JSON.parse(await fs.readFile(ctx.configPath, 'utf8'));
      const account = String(ctx.core.selfInfo.uin);
      if (!/^[1-9]\d{4,19}$/.test(account) || policy.account !== account || policy.enabled !== true ||
          !Array.isArray(policy.targets) || policy.targets.length > 20 || req.body?.account !== account ||
          typeof req.body?.dryRun !== 'boolean') throw new Error('Cleanup policy/account mismatch');
      const dryRun = req.body.dryRun, cutoff = Date.now() / 1000 - WEEK;
      const result = { dryRun, retentionDays: 7, scopes: 0, candidates: 0, deleted: 0, files: 0, bytes: 0, errors: 0, capped: false };
      const service = ctx.core.context.session.getMsgService();
      for (const target of policy.targets) {
        if (!['private', 'group'].includes(target.type) || !/^[1-9]\d{4,19}$/.test(target.id)) throw new Error('Invalid cleanup scope');
        const uid = target.type === 'group' ? target.id : await ctx.core.apis.UserApi.getUidByUinV2(target.id);
        if (typeof uid !== 'string' || (target.type === 'private' && !/^u_[a-zA-Z0-9_-]+$/.test(uid))) throw new Error('Peer UID unavailable');
        const peer = { chatType: target.type === 'group' ? 2 : 1, peerUid: uid, guildId: '' };
        try {
          const counts = await cleanHistory(service, peer, cutoff, dryRun);
          result.scopes++; result.candidates += counts.candidates; result.deleted += counts.deleted;
          result.capped ||= counts.capped;
        } catch (error) { result.errors++; result.candidates += error.counts?.candidates ?? 0; result.deleted += error.counts?.deleted ?? 0; }
      }
      // QQ stores account data in nt_qq_<hash>; never touch nt_db, global, login or avatars.
      const qqRoot = path.resolve(ctx.core.dataPath);
      const mediaRoot = path.resolve(policy.mediaRoot ?? '');
      const relative = path.relative(qqRoot, mediaRoot);
      if (!/^nt_qq_[a-f0-9]+[/\\]nt_data$/.test(relative)) throw new Error('Media root not approved');
      for (const category of ['Pic', 'Ptt', 'Video', 'File', 'log']) {
        const counts = await pruneMedia(path.join(mediaRoot, category), cutoff, dryRun);
        result.files += counts.files; result.bytes += counts.bytes; result.errors += counts.errors;
      }
      res.json({ code: 0, data: result });
    } catch { res.status(400).json({ code: -1, message: 'Cleanup failed; no credentials or chat content logged' }); }
    finally { busy = false; }
  });
}
