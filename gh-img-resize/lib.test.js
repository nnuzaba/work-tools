const test = require('node:test');
const assert = require('node:assert');
const { findImageTokens, resizeEdits, newUploadEdits, applyEdits } = require('./lib.js');

const UPLOAD = 'https://github.com/user-attachments/assets/abc';

const resizeCases = [
  {
    name: 'GitHub upload tag: replaces width, drops height',
    text: `<img width="1512" height="982" alt="image" src="${UPLOAD}" />`,
    index: 0, width: 400,
    expected: `<img width="400" alt="image" src="${UPLOAD}" />`,
  },
  {
    name: 'markdown image becomes an img tag',
    text: `hi ![my "shot"](${UPLOAD}) bye`,
    index: 0, width: '50%',
    expected: `hi <img width="50%" alt="my &quot;shot&quot;" src="${UPLOAD}"> bye`,
  },
  {
    name: 'only touches the requested image',
    text: `![a](${UPLOAD}1)\n<img src='${UPLOAD}2' width=300>`,
    index: 1, width: 200,
    expected: `![a](${UPLOAD}1)\n<img width="200" src='${UPLOAD}2'>`,
  },
  {
    name: 'leaves data-width alone',
    text: `<img data-width="9" src="${UPLOAD}">`,
    index: 0, width: 100,
    expected: `<img width="100" data-width="9" src="${UPLOAD}">`,
  },
  { name: 'out-of-range index is a no-op', text: 'no images', index: 0, width: 100, expected: 'no images' },
];

for (const c of resizeCases) {
  test(`resize: ${c.name}`, () => {
    const { text } = applyEdits(c.text, resizeEdits(c.text, c.index, c.width), 0);
    assert.strictEqual(text, c.expected);
  });
}

test('newUploadEdits shrinks only unseen user-attachments images and keeps the caret in place', () => {
  const before = `<img width="1000" src="${UPLOAD}old">\n`;
  const fresh = `<img width="1512" height="982" alt="image" src="${UPLOAD}new" />`;
  const text = `${before}${fresh}\n![x](https://example.com/a.png)\nTYPING`;
  const caret = text.indexOf('TYPING');
  const edits = newUploadEdits(text, new Set([`${UPLOAD}old`]), 400);
  const result = applyEdits(text, edits, caret);
  assert.strictEqual(edits.length, 1);
  assert.ok(result.text.includes(`<img width="400" alt="image" src="${UPLOAD}new" />`));
  assert.ok(result.text.includes(`<img width="1000" src="${UPLOAD}old">`));
  assert.strictEqual(result.text.slice(result.caret, result.caret + 6), 'TYPING');
});

test('findImageTokens ignores the upload placeholder (empty src)', () => {
  const tokens = findImageTokens('![Uploading image.png…]()');
  assert.strictEqual(tokens.length, 0);
});
