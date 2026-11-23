/**
 * Runs on github.com. Two features:
 * 1. Freshly uploaded images get a default width instead of their huge native size.
 * 2. Images in a comment's Preview tab get a drag handle; dragging writes width="N" into the markdown.
 */
let defaultUploadWidth = 400;
chrome.storage.sync.get({ defaultWidth: 400 }, (settings) => { defaultUploadWidth = settings.defaultWidth; });
chrome.storage.onChanged.addListener((changes) => {
  if (changes.defaultWidth) defaultUploadWidth = changes.defaultWidth.newValue;
});

const textareaValueSetter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set;
const seenSrcsByTextarea = new Map();
let extensionWritingTextarea = false;

/** Sets the value the way React expects, so GitHub keeps the change when you save. */
function writeTextarea(textarea, edits) {
  if (!edits.length) return;
  const { text, caret } = applyEdits(textarea.value, edits, textarea.selectionStart);
  extensionWritingTextarea = true;
  textareaValueSetter.call(textarea, text);
  textarea.dispatchEvent(new Event('input', { bubbles: true }));
  extensionWritingTextarea = false;
  textarea.setSelectionRange(caret, caret);
}

/** Remembers which images were already in the box, so only new uploads get shrunk. */
function rememberExistingImages(textarea) {
  if (!textarea || seenSrcsByTextarea.has(textarea)) return;
  seenSrcsByTextarea.set(textarea, new Set(findImageTokens(textarea.value).map((token) => token.src)));
}

function shrinkNewUploads(textarea) {
  const seenSrcs = seenSrcsByTextarea.get(textarea);
  if (!seenSrcs || !defaultUploadWidth || extensionWritingTextarea) return;
  writeTextarea(textarea, newUploadEdits(textarea.value, seenSrcs, defaultUploadWidth));
  findImageTokens(textarea.value).forEach((token) => seenSrcs.add(token.src));
}

function textareaNear(target) {
  if (target instanceof HTMLTextAreaElement) return target;
  return target?.closest?.('form')?.querySelector('textarea') ?? null;
}

for (const eventName of ['focusin', 'paste', 'dragenter']) {
  document.addEventListener(eventName, (event) => rememberExistingImages(textareaNear(event.target)), true);
}
document.addEventListener('input', (event) => {
  if (event.target instanceof HTMLTextAreaElement) shrinkNewUploads(event.target);
}, true);
// GitHub swaps the upload placeholder for the final URL without always firing input, so also poll.
setInterval(() => {
  for (const textarea of seenSrcsByTextarea.keys()) {
    if (!textarea.isConnected) seenSrcsByTextarea.delete(textarea);
    else shrinkNewUploads(textarea);
  }
}, 1000);

const resizeHandle = document.createElement('div');
resizeHandle.className = 'ghir-handle';
const widthLabel = document.createElement('div');
widthLabel.className = 'ghir-label';
document.documentElement.append(resizeHandle, widthLabel);
let hoveredImage = null;
let dragInProgress = false;

function previewImages(markdownBody) {
  return [...markdownBody.querySelectorAll('img')].filter((img) => !img.matches('.emoji, g-emoji img'));
}

/** Walks up from the image to the closest ancestor that also holds a textarea. */
function textareaFor(img) {
  for (let ancestor = img.parentElement; ancestor; ancestor = ancestor.parentElement) {
    const textarea = ancestor.querySelector('textarea');
    if (textarea) return textarea;
  }
  return null;
}

/** Returns {textarea, imageIndex} for an editable preview image, or {skipReason} if not editable. */
function editableSourceFor(img) {
  const textarea = textareaFor(img);
  const markdownBody = img.closest('.markdown-body');
  if (!textarea) return { skipReason: 'no textarea found above the image' };
  if (!markdownBody) return { skipReason: 'image is not inside .markdown-body' };
  const images = previewImages(markdownBody);
  const tokenCount = findImageTokens(textarea.value).length;
  // If counts differ (e.g. images inside code blocks), we can't safely match them up.
  if (images.length !== tokenCount) {
    return { skipReason: `preview has ${images.length} images but the markdown has ${tokenCount}` };
  }
  return { textarea, imageIndex: images.indexOf(img) };
}

const imagesAlreadyLogged = new WeakSet();
function logSkipOnce(img, skipReason) {
  if (imagesAlreadyLogged.has(img)) return;
  imagesAlreadyLogged.add(img);
  console.info('[gh-img-resize] no handle:', skipReason, img);
}

function placeHandle(img) {
  const box = img.getBoundingClientRect();
  resizeHandle.style.left = `${box.right - 9}px`;
  resizeHandle.style.top = `${box.bottom - 9}px`;
  resizeHandle.style.display = 'block';
}

function hideHandle() {
  if (dragInProgress) return;
  resizeHandle.style.display = 'none';
  hoveredImage = null;
}

document.addEventListener('mouseover', (event) => {
  if (dragInProgress || event.target === resizeHandle) return;
  const img = event.target.closest?.('.markdown-body img');
  const source = img ? editableSourceFor(img) : null;
  if (source?.textarea) {
    hoveredImage = img;
    placeHandle(img);
  } else {
    if (source) logSkipOnce(img, source.skipReason);
    hideHandle();
  }
});
window.addEventListener('scroll', hideHandle, true);

resizeHandle.addEventListener('pointerdown', (event) => {
  const img = hoveredImage;
  if (!img) return;
  event.preventDefault();
  resizeHandle.setPointerCapture(event.pointerId);
  dragInProgress = true;
  const startX = event.clientX;
  const startWidth = img.getBoundingClientRect().width;
  const maxWidth = img.closest('.markdown-body').clientWidth;
  let newWidth = Math.round(startWidth);

  const onMove = (moveEvent) => {
    newWidth = Math.min(maxWidth, Math.max(40, Math.round((startWidth + moveEvent.clientX - startX) / 10) * 10));
    img.style.width = `${newWidth}px`;
    img.style.height = 'auto';
    placeHandle(img);
    widthLabel.textContent = `${newWidth}px`;
    widthLabel.style.left = `${moveEvent.clientX + 12}px`;
    widthLabel.style.top = `${moveEvent.clientY + 12}px`;
    widthLabel.style.display = 'block';
  };
  const onUp = () => {
    resizeHandle.removeEventListener('pointermove', onMove);
    resizeHandle.removeEventListener('pointerup', onUp);
    dragInProgress = false;
    widthLabel.style.display = 'none';
    const source = editableSourceFor(img);
    if (source.textarea) writeTextarea(source.textarea, resizeEdits(source.textarea.value, source.imageIndex, newWidth));
  };
  resizeHandle.addEventListener('pointermove', onMove);
  resizeHandle.addEventListener('pointerup', onUp);
});
