document.getElementById('save').addEventListener('click', async () => {
  const text = document.getElementById('text').value;
  const [tab] = await chrome.tabs.query({active: true, currentWindow: true});
  const receipt = {text, tabId: tab.id, extensionId: chrome.runtime.id, popupURL: location.href};
  await chrome.storage.local.set({receipt});
  await chrome.tabs.sendMessage(tab.id, {receipt});
  document.getElementById('status').textContent = 'Saved: ' + text;
});
document.getElementById('options').addEventListener('click', () => chrome.runtime.openOptionsPage());
