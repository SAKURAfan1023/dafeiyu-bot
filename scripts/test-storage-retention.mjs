import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { oldMessageIDs, cleanHistory, pruneMedia } from '../Resources/NapCatRetention/index.mjs';

const cutoff = 1_900_000_000;
const peer = { chatType: 2, peerUid: '99999', guildId: '' };
const old = { chatType: 2, peerUid: '99999', msgId: '123', msgTime: String(cutoff - 1) };
const recent = { ...old, msgId: '124', msgTime: String(cutoff) };
assert.deepEqual(oldMessageIDs([old, recent], peer, cutoff), ['123']);
for (const bad of [{ ...old, peerUid: '88888' }, { ...old, chatType: 1 }, { ...old, msgTime: 'NaN' }, { ...old, msgId: '0' }]) {
  assert.throws(() => oldMessageIDs([bad], peer, cutoff));
}
let calls = 0, rows = [old, recent];
const service = {
  queryMsgsWithFilterEx: async () => ({ result: 0, msgList: rows }),
  deleteMsg: async (_, ids) => { calls++; rows = rows.filter(m => !ids.includes(m.msgId)); },
  getMsgsByMsgId: async (_, ids) => ({ result: 0, msgList: rows.filter(m => ids.includes(m.msgId)) })
};
assert.equal((await cleanHistory(service, peer, cutoff, true)).candidates, 1);
assert.equal(calls, 0);
assert.equal((await cleanHistory(service, peer, cutoff, false)).deleted, 1);
assert.deepEqual(rows, [recent]);
await assert.rejects(cleanHistory({ ...service, deleteMsg: undefined }, peer, cutoff, false));
await assert.rejects(cleanHistory({ ...service, queryMsgsWithFilterEx: async () => ({ result: 1, msgList: [old] }) }, peer, cutoff, false));
await assert.rejects(cleanHistory({ ...service, queryMsgsWithFilterEx: async () => ({ result: 0, msgList: [old] }), deleteMsg: async () => {}, getMsgsByMsgId: async () => ({ result: 0, msgList: [old] }) }, peer, cutoff, false));

const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'retention-test-'));
try {
  const root = path.join(dir, 'Pic'), outside = path.join(dir, 'must-stay');
  await fs.mkdir(root); await fs.mkdir(path.join(root, 'nested'));
  for (const file of [outside, path.join(root, 'nested/old'), path.join(root, 'recent')]) await fs.writeFile(file, 'fixture');
  const past = new Date((cutoff - 100) * 1000);
  await fs.utimes(path.join(root, 'nested/old'), past, past);
  await fs.utimes(outside, past, past);
  const future = new Date((cutoff + 100) * 1000);
  await fs.utimes(path.join(root, 'recent'), future, future);
  await fs.symlink(outside, path.join(root, 'link'));
  assert.equal((await pruneMedia(root, cutoff, true)).files, 1);
  assert.equal((await pruneMedia(root, cutoff, false)).files, 1);
  assert.equal(await fs.readFile(outside, 'utf8'), 'fixture');
  assert.equal(await fs.readFile(path.join(root, 'recent'), 'utf8'), 'fixture');
} finally { await fs.rm(dir, { recursive: true }); }
console.log('QQ retention: date, scope, dry-run, native confirmation and symlink protection passed');
