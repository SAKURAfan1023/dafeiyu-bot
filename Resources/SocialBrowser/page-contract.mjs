// Reject unknown payload shapes before the request can reach the site.
export function requestMatchesTarget(payload, expected) {
  const target = payload?.target_comment_id ?? payload?.target_comment?.id ?? '';
  return payload?.note_id === expected.id && payload?.content === expected.content &&
    String(target || '') === String(expected.parentID || '');
}
export function claimWrite(permit, payload) {
  if (!permit || permit.used || !Number.isFinite(permit.expected.deadline) || permit.expected.deadline <= Date.now() || !requestMatchesTarget(payload, permit.expected)) return false;
  permit.used = true;
  return true;
}
// Runs in the page through Playwright; preserve emoji alt text and verify the reply root.
export function commentEvidence(el) {
  const text = el.querySelector('.content') || el.querySelector('.note-text');
  const clone = text?.cloneNode(true);
  clone?.querySelectorAll('img').forEach(img => img.replaceWith(document.createTextNode(img.alt || '')));
  const ancestor = el.parentElement?.closest('[id^="comment-"]');
  return { content: clone?.textContent?.trim(),
    author: el.querySelector('a[href*="/user/profile/"]')?.getAttribute('href'),
    parentID: ancestor?.id.replace(/^comment-/, '') ?? '' };
}
