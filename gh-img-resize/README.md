# GitHub Image Resizer

Chrome extension for images in GitHub comments and PR descriptions.

- **Drag to resize:** in the Preview tab, hover an image and drag the blue square in its corner. It writes `width="N"` into the markdown.
- **Default upload width:** new uploads get a set width (400px to start). Change it in the toolbar popup; 0 turns it off.

## Install

1. Open `chrome://extensions` and turn on Developer mode.
2. Click **Load unpacked** and pick this folder.
3. Hard-refresh any open GitHub tabs.

After editing the code, click the reload icon on the extension, then hard-refresh GitHub.

## Test

```bash
node --test gh-img-resize/lib.test.js
```

## Known limits

- Preview images are matched to the markdown by order. If the counts differ (for example, an image inside a code block), no handle shows. The reason is logged to the console as `[gh-img-resize] no handle:`.
- Posted comments may also show a handle, because GitHub keeps a hidden edit box next to them. Dragging there only changes what you see.
