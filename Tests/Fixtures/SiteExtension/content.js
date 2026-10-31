document.documentElement.setAttribute('data-brk-extension','installed');chrome.runtime.onMessage.addListener(message=>{if(message.command)document.title='extension-command:'+message.command});
