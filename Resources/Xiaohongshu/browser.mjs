// Independent browser adapter. No model credentials, arbitrary tools, or personal Chrome profile.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { claimWrite, commentEvidence } from './page-contract.mjs';
import { createHash } from 'node:crypto';
const require = createRequire(path.join(process.env.DAFEIYU_XHS_DEPENDENCIES, 'package.json'));
process.umask(0o077);
const { chromium } = require('playwright-core');
const secret = process.env.DAFEIYU_XHS_TOKEN;
if (!secret || !process.env.DAFEIYU_XHS_PROFILE) process.exit(1);
const origin = 'https://www.xiaohongshu.com';
let context, page, busy = false, shuttingDown = false;
let writePermit = null, cancelled = false;
const clean = v => String(v ?? '').trim();
const validID = v => /^[a-zA-Z0-9_-]{1,100}$/.test(v);
function browserPath() {
  const candidates = process.platform === 'darwin'
    ? ['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge']
    : ['/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser'];
  return candidates.find(p => fs.existsSync(p));
}
async function browser() {
  if (context) return;
  const executablePath = browserPath();
  if (!executablePath) throw new Error('browser_missing');
  context = await chromium.launchPersistentContext(process.env.DAFEIYU_XHS_PROFILE, {
    executablePath, headless: false, viewport: { width: 1180, height: 840 },
    acceptDownloads: false, permissions: [],
  });
  context.on('close', () => { context = undefined; page = undefined; });
  // Keep this deny rule for the whole browser lifetime, including after an unknown result.
  await context.route(/\/api\/sns\/web\/[^/]+\/comment\/(post|reply|delete)/, async route => {
    const url = new URL(route.request().url());
    const trusted = url.protocol === 'https:' && ['www.xiaohongshu.com', 'edith.xiaohongshu.com'].includes(url.hostname);
    if (trusted && route.request().method() === 'OPTIONS') return route.continue();
    let payload; try { payload = route.request().postDataJSON(); } catch {}
    if (!trusted || url.pathname !== '/api/sns/web/v1/comment/post' || route.request().method() !== 'POST' || cancelled || !claimWrite(writePermit, payload)) {
      if (writePermit) writePermit.blocked = true;
      return route.abort();
    }
    await route.continue();
  });
  page = context.pages()[0] || await context.newPage();
  page.setDefaultTimeout(12000);
  page.setDefaultNavigationTimeout(25000);
  context.on('page', p => { if (p !== page) p.close().catch(() => {}); });
}
async function navigate(url) {
  if (new URL(url).origin !== origin) throw new Error('invalid_origin');
  await browser();
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  if (new URL(page.url()).origin !== origin) throw new Error('unexpected_origin');
}
async function identity() {
  await browser();
  if (new URL(page.url()).origin !== origin) await navigate(origin + '/explore');
  const result = await page.locator('li.user.side-bar-component a[href*="/user/profile/"]').first().getAttribute('href', { timeout: 4000 }).catch(() => null);
  const id = result?.match(/\/user\/profile\/([a-zA-Z0-9_-]+)/)?.[1];
  if (!id) throw new Error('login_required');
  return { id, name: '小红书账号 · ' + id.slice(-6) };
}
async function search(keyword) {
  if (!clean(keyword) || keyword.length > 80) throw new Error('invalid_keyword');
  await navigate(origin + '/search_result?keyword=' + encodeURIComponent(keyword) + '&source=web_explore_feed');
  await page.waitForFunction(() => {
    const s = window.__INITIAL_STATE__?.search?.feeds;
    const feeds = s?.value ?? s?._value ?? s;
    // The page starts with an empty list before the search request completes.
    // An empty bootstrap is not evidence that the keyword has no matches.
    return Array.isArray(feeds) && feeds.length > 0;
  }, null, { timeout: 15000 });
  const feeds = await page.evaluate(() => {
    const s = window.__INITIAL_STATE__.search.feeds;
    return JSON.parse(JSON.stringify(s?.value ?? s?._value ?? s));
  });
  return { posts: feeds.filter(f => f.modelType === 'note' && validID(f.id)).slice(0, 20).map(f => ({
    id: f.id, locator: clean(f.xsecToken), title: clean(f.noteCard?.displayTitle).slice(0, 200),
    author: clean(f.noteCard?.user?.nickname ?? f.noteCard?.user?.nickName).slice(0, 80),
    kind: clean(f.noteCard?.type),
  })).filter(f => f.locator) };
}
async function read(input) {
  if (!validID(input.id) || !input.locator || input.locator.length > 2048) throw new Error('invalid_target');
  await navigate(origin + '/explore/' + input.id + '?xsec_token=' + encodeURIComponent(input.locator) + '&xsec_source=pc_search');
  await page.waitForFunction(id => !!window.__INITIAL_STATE__?.note?.noteDetailMap?.[id]?.note, input.id, { timeout: 15000 });
  await page.locator('.comments-container').first().scrollIntoViewIfNeeded({ timeout: 2000 }).catch(() => {});
  const commentsReady = await page.waitForFunction(id => {
    const detail = window.__INITIAL_STATE__?.note?.noteDetailMap?.[id];
    const count = detail?.note?.interactInfo?.commentCount;
    return detail?.comments?.list?.length > 0 || detail?.comments?.hasMore === false || count === 0 || count === '0';
  }, input.id, { timeout: 8000 }).then(() => true, () => false);
  const data = await page.evaluate(id => JSON.parse(JSON.stringify(window.__INITIAL_STATE__.note.noteDetailMap[id])), input.id);
  const n = data.note;
  if (n.noteId !== input.id) throw new Error('target_changed');
  const comments = [];
  function add(c, root = null) {
    if (!validID(c.id) || comments.length >= 30) return;
    comments.push({ id: c.id, rootID: root, authorID: clean(c.userInfo?.userId), author: clean(c.userInfo?.nickname ?? c.userInfo?.nickName).slice(0, 80), text: clean(c.content).slice(0, 1500) });
    for (const sub of c.subComments ?? []) add(sub, root || c.id);
  }
  for (const c of data.comments?.list ?? []) add(c);
  return { id: n.noteId, title: clean(n.title).slice(0, 200), text: clean(n.desc).slice(0, 6000),
    author: clean(n.user?.nickname ?? n.user?.nickName).slice(0, 80), authorID: clean(n.user?.userId),
    kind: clean(n.type), imageCount: n.imageList?.length ?? 0, comments,
    coverage: '仅已加载文字及评论；图片、视频未分析' + (!commentsReady ? '；评论尚未加载，不代表没有评论' : data.comments?.hasMore ? '；评论未读完' : ''),
  };
}
// Match only an exact comment ID. Never fall back to the same user's other comments.
async function visibleComment(id) {
  const node = page.locator('#comment-' + id);
  if (await node.count() !== 1) throw new Error('target_missing');
  return node;
}
async function verify(input) {
  await read(input);
  await identity().then(i => { if (i.id !== input.expectedUID) throw new Error('account_changed'); });
  if (!validID(input.externalID)) return { state: 'uncertain' };
  let node = await visibleComment(input.externalID).catch(() => null);
  if (!node && input.parentID && validID(input.parentID)) {
    const parent = await visibleComment(input.parentID).catch(() => null);
    if (parent) {
      await parent.scrollIntoViewIfNeeded({ timeout: 2000 }).catch(() => {});
      const more = parent.locator('.show-more').filter({ hasText: /展开\s*(?:\d+\s*条|更多)回复/ }).first();
      if (await more.count()) {
        await more.click({ timeout: 2000 }).catch(() => {});
        await page.locator('#comment-' + input.externalID).waitFor({ state: 'attached', timeout: 3000 }).catch(() => {});
        node = await visibleComment(input.externalID).catch(() => null);
      }
    }
  }
  if (!node) return { state: 'accepted', externalID: input.externalID };
  const details = await node.evaluate(commentEvidence);
  const uid = details.author?.match(/\/user\/profile\/([a-zA-Z0-9_-]+)/)?.[1];
  if (uid === input.expectedUID && details.content === input.content && (details.parentID || '') === (input.parentID || '')) return { state: 'confirmed', externalID: input.externalID, authorID: uid };
  return { state: 'accepted', externalID: input.externalID };
}
async function submit(input) {
  const current = await read(input);
  const parent = input.parentID ? current.comments.find(c => c.id === input.parentID) : null;
  const fingerprint = createHash('sha256').update(current.id + '\n' + current.title + '\n' + current.text + '\n' + (parent ? parent.id + parent.authorID + parent.text : '')).digest('hex');
  if (input.fingerprint !== fingerprint) throw new Error('target_changed');
  const who = await identity();
  if (who.id !== input.expectedUID) throw new Error('account_changed');
  if (!clean(input.content) || input.content.length > 300) throw new Error('invalid_content');
  if (input.parentID && (!parent || parent.rootID)) throw new Error('target_missing');
  const baseline = new Set(current.comments.map(c => c.id));
  if (input.parentID) {
    const parent = await visibleComment(input.parentID);
    await parent.locator('.right .interactions .reply').click();
  } else {
    await page.locator('div.input-box div.content-edit span').click();
  }
  await page.locator('div.input-box div.content-edit p.content-input').fill(input.content);
  if ((await identity()).id !== input.expectedUID) throw new Error('account_changed');
  // Guard the actual outgoing request, not just the UI label. Unknown payloads are blocked.
  if (cancelled || !Number.isFinite(input.deadline) || input.deadline <= Date.now()) throw new Error('operation_cancelled');
  const permit = { expected: input, used: false, blocked: false };
  writePermit = permit;
  try {
    const response = page.waitForResponse(r => r.url().includes('/api/sns/web/v1/comment/post') && r.request().method() === 'POST', { timeout: 12000 });
    // Attach a rejection handler before click can fail.
    response.catch(() => {});
    await page.locator('div.bottom button.submit').click();
    const res = await response.catch(() => null);
    if (permit.blocked && !permit.used) return { state: 'rejected', reason: 'request_target_mismatch' };
    if (!res) return { state: 'uncertain' };
    const raw = await res.json().catch(() => null);
    const c = raw?.data?.comment;
    const externalID = clean(c?.id);
    if (!res.ok() || raw?.success !== true || !validID(externalID) || baseline.has(externalID)) return { state: 'uncertain' };
    const authorID = clean(c?.user_info?.user_id ?? c?.userInfo?.userId);
    if (authorID && authorID !== input.expectedUID) return { state: 'uncertain' };
    return { state: 'accepted', externalID, authorID };
  } finally { writePermit = null; }
}
async function execute(input) {
  switch (input.action) {
    case 'login': {
      await navigate(origin + '/explore');
      await page.bringToFront();
      const qr = await page.locator('.login-container .qrcode-img').first().screenshot({ timeout: 4000 }).catch(() => null);
      return { qr: qr?.toString('base64') ?? '', message: '请在独立浏览器登录，完成后核对账号' };
    }
    case 'identity': return identity();
    case 'search': await identity(); return search(input.keyword);
    case 'read': return read(input);
    case 'submit': return submit(input);
    case 'verify': return verify(input);
    default: throw new Error('unknown_action');
  }
}
const server = http.createServer(async (req, res) => {
  if (req.method !== 'POST' || !['/action','/cancel'].includes(req.url) || req.headers.authorization !== 'Bearer ' + secret || req.headers.host !== '127.0.0.1:' + server.address().port || req.headers.origin) {
    res.writeHead(403).end(); return;
  }
  if (req.url === '/cancel') {
    cancelled = true; writePermit = null;
    res.writeHead(200, { 'Content-Type': 'application/json' }).end('{}');
    return;
  }
  if (busy || shuttingDown) { res.writeHead(409).end(); return; }
  busy = true; cancelled = false;
  let bytes = 0, chunks = [], timer;
  const reply = (code, value) => { if (!res.destroyed) res.writeHead(code, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }).end(JSON.stringify(value)); };
  try {
    for await (const chunk of req) { bytes += chunk.length; if (bytes > 16384) throw new Error('request_too_large'); chunks.push(chunk); }
    const input = JSON.parse(Buffer.concat(chunks));
    // On deadline close the owned context and await termination before releasing busy.
    const task = execute(input);
    const expired = new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('operation_timeout')), 45000); });
    try { reply(200, await Promise.race([task, expired])); }
    catch (error) {
      await context?.close(); context = undefined; page = undefined;
      await task.catch(() => {});
      throw error;
    }
  } catch (error) {
    const known = /^(browser_missing|login_required|account_changed|target_changed|target_missing|invalid_[a-z_]+|operation_timeout|operation_cancelled|request_too_large|unknown_action)$/;
    reply(400, { error: known.test(error.message) ? error.message : 'page_unavailable' });
  } finally { clearTimeout(timer); busy = false; }
});
server.listen(0, '127.0.0.1', () => console.log(JSON.stringify({ port: server.address().port })));
async function shutdown() {
  if (shuttingDown) return; shuttingDown = true;
  server.close(); await context?.close(); process.exit(0);
}
process.on('SIGTERM', shutdown); process.on('SIGINT', shutdown);
process.stdin.resume(); process.stdin.on('end', shutdown);
