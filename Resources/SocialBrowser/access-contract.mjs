export function restrictedResponse(url, status, code) {
  let host; try { host=new URL(url).hostname; } catch { return false; }
  if(!['edith.xiaohongshu.com','www.xiaohongshu.com','api.bilibili.com'].includes(host))return false;
  return [403,412,429].includes(status) || [300011,300012,-352,-403,-412,-509].includes(code) || host==='api.bilibili.com' && [-102,12015].includes(code);
}
