document.documentElement.setAttribute('data-brk-extension','installed');
chrome.runtime.onMessage.addListener(message=>{
  if(!message.command)return;
  const count=Number(document.documentElement.getAttribute('data-brk-extension-commands')||'0');
  document.documentElement.setAttribute('data-brk-extension-commands',String(count+1));
  document.title='extension-command:'+message.command;
});
