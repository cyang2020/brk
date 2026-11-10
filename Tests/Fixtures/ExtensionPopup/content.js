document.documentElement.dataset.extensionId = chrome.runtime.id;
chrome.runtime.onMessage.addListener(message => {
  if (message.receipt) {
    document.documentElement.dataset.popupReceipt = JSON.stringify(message.receipt);
    document.getElementById('receipt').textContent = JSON.stringify(message.receipt);
  }
});
