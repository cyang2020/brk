document.getElementById('save').onclick=()=>chrome.storage.local.set({text:document.getElementById('text').value},()=>document.getElementById('status').textContent='Saved');
