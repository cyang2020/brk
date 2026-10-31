import BrkBase
import Foundation

enum BrkTour {
    static func write(in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("brk-101.html")
        try Data(html.utf8).write(to: url, options: .atomic)
        return url
    }

    static let html = #"""
    <!doctype html><html lang="en"><meta charset="utf-8"><title>Brk 101</title>
    <style>
    :root { color-scheme:light dark; font:18px -apple-system,BlinkMacSystemFont,sans-serif; }
    body { margin:48px auto; max-width:760px; padding:0 24px; line-height:1.6; }
    h1 { font-size:38px; } #demo { padding:24px; background:light-dark(#eef1fa,#242735); border-radius:16px; min-height:140px; }
    button { padding:12px 24px; margin:24px 12px 0 0; font:inherit; cursor:pointer; }
    kbd { border:1px solid gray; padding:3px 8px; border-radius:6px; } progress { width:100%; }
    </style>
    <h1>Brk 101</h1><p>A local, account-free tour. Try each shortcut in your browser, then continue.</p>
    <progress id="progress" max="6" value="1"></progress><p id="count"></p><div id="demo"></div>
    <button id="back">Back</button><button id="next">Continue</button><p id="result" aria-live="polite"></p>
    <script>
    const steps=[
      ['Make a tab','Press <kbd>⌘T</kbd>, enter an address, then Return. Press <kbd>⌘L</kbd> to edit this page’s address.'],
      ['Keep a page','Press <kbd>⌘D</kbd> to move a Today tab into Pinned. Drag a pinned tab into Favorites for a site you use everywhere in this profile.'],
      ['Give work a Space','Use the + button at the bottom of the sidebar to create a Space. Each Space keeps its own Pinned and Today tabs. Profiles keep browsing data separate.'],
      ['Read side by side','Press <kbd>⌃⇧=</kbd> to add a split pane, then enter another address. Click a pane before using page commands.'],
      ['Close and restore','Press <kbd>⌘W</kbd>. Today tabs move to Archive; Pinned tabs stay in the sidebar. Use the Library to restore an archived tab or inspect History and Downloads.'],
      ['Bring your sidebar','Use Brk → Import from Another Browser to preview exported files. Preferences → General → Sidebar Data connects a local folder. Use Share… to save selected links as JSON or HTML.']
    ];
    let step=0;
    function show(){document.querySelector('#demo').innerHTML='<h2>'+steps[step][0]+'</h2><p>'+steps[step][1]+'</p>';document.querySelector('#count').textContent='Step '+(step+1)+' of 6';document.querySelector('#progress').value=step+1;document.querySelector('#back').disabled=step===0;document.querySelector('#next').textContent=step===5?'Finish tour':'Continue';}
    document.querySelector('#back').onclick=()=>{if(step>0){step--;show();}};
    document.querySelector('#next').onclick=()=>{if(step<5){step++;show();}else{document.title='Brk 101 complete';document.querySelector('#result').textContent='Tour complete. You can reopen Brk 101 from Help → Getting Started.';document.querySelector('#next').disabled=true;}};
    show();
    </script></html>
    """#
}
