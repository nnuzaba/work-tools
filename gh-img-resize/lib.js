/**
 * Pure text helpers for finding and resizing images inside GitHub markdown.
 * Loaded as a content script (globals) and by node tests (module.exports).
 */
const IMAGE_TOKEN_PATTERN = /<img\b[^>]*>|!\[([^\]]*)\]\(([^)\s]+)[^)]*\)/gi;

/** Returns every image in the text, in order, as {start, end, raw, src, alt}. */
function findImageTokens(text) {
  const tokens = [];
  for (const match of text.matchAll(IMAGE_TOKEN_PATTERN)) {
    const raw = match[0];
    const isHtmlTag = raw.startsWith('<');
    const src = isHtmlTag ? readAttr(raw, 'src') : match[2];
    const alt = isHtmlTag ? readAttr(raw, 'alt') : match[1];
    tokens.push({ start: match.index, end: match.index + raw.length, raw, src, alt });
  }
  return tokens;
}

function readAttr(tag, name) {
  const found = tag.match(new RegExp(`\\s${name}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s>]+))`, 'i'));
  return found ? found[1] ?? found[2] ?? found[3] : '';
}

/** Rewrites one image token so it has the given width (px number or "50%") and no height. */
function tokenWithWidth(token, width) {
  if (!token.raw.startsWith('<')) {
    const safeAlt = token.alt.replace(/"/g, '&quot;');
    return `<img width="${width}" alt="${safeAlt}" src="${token.src}">`;
  }
  const withoutSize = token.raw.replace(/\s+(?:width|height)\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)/gi, '');
  return withoutSize.replace(/^<img\b/i, `<img width="${width}"`);
}

/** Edit that sets the width of the image at position `imageIndex`. */
function resizeEdits(text, imageIndex, width) {
  const token = findImageTokens(text)[imageIndex];
  return token ? [{ start: token.start, end: token.end, replacement: tokenWithWidth(token, width) }] : [];
}

/** Edits that shrink freshly uploaded GitHub images whose src is not in `seenSrcs`. */
function newUploadEdits(text, seenSrcs, width) {
  return findImageTokens(text)
    .filter((token) => token.src.includes('/user-attachments/') && !seenSrcs.has(token.src))
    .map((token) => ({ start: token.start, end: token.end, replacement: tokenWithWidth(token, width) }));
}

/** Applies non-overlapping edits and moves the caret so it stays at the same spot. */
function applyEdits(text, edits, caret) {
  let result = text;
  let caretShift = 0;
  for (const edit of [...edits].sort((a, b) => b.start - a.start)) {
    result = result.slice(0, edit.start) + edit.replacement + result.slice(edit.end);
    if (edit.end <= caret) caretShift += edit.replacement.length - (edit.end - edit.start);
  }
  return { text: result, caret: caret + caretShift };
}

if (typeof module !== 'undefined') {
  module.exports = { findImageTokens, tokenWithWidth, resizeEdits, newUploadEdits, applyEdits };
}
