// What only a real action popup can see: the tab it was opened on is this window's active tab, opening it granted activeTab on that tab alone.
// The result goes into the page's title through the grant it is testing, so without the grant the page's title never changes.
(async () => {
  const [active] = await chrome.tabs.query({active: true, currentWindow: true});
  const win = await chrome.windows.getCurrent();
  const all = await chrome.tabs.query({currentWindow: true});
  const others = all.filter(tab => tab.id !== active.id);
  let denied = [];
  for (const tab of others) {
    try {
      await chrome.scripting.executeScript({target: {tabId: tab.id}, func: () => { document.title = 'granted-on-another-tab'; }});
      denied.push('granted');
    } catch (error) {
      denied.push('denied');
    }
  }
  const report = {popup: location.href, activeURL: active.url || null, tabId: active.id, windowType: win.type, tabs: all.length,
                  otherURLs: others.map(tab => tab.url || null), others: denied};
  document.getElementById('state').textContent = JSON.stringify(report);
  await chrome.scripting.executeScript({target: {tabId: active.id}, args: [report], func: report => { document.title = 'activeTab:' + JSON.stringify(report); }});
})();
