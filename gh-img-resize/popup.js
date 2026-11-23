const widthInput = document.getElementById('default-width');
chrome.storage.sync.get({ defaultWidth: 400 }, (settings) => { widthInput.value = settings.defaultWidth; });
widthInput.addEventListener('change', () => {
  chrome.storage.sync.set({ defaultWidth: Math.max(0, Number(widthInput.value) || 0) });
});
