import CCef

extension CefBrowser {
    /// Execute in CEF's focused frame, so frame editors retain their own selection and undo stack.
    public func transformSelection(_ mode: String) {
        guard ["upper", "lower", "capitalize"].contains(mode) else { return }
        withEditingFrame { frame in
            let script = """
            (()=>{const e=document.activeElement;if(!e||e.disabled||e.readOnly||e.type==='password')return;
            let text;if(e.tagName==='INPUT'||e.tagName==='TEXTAREA'){if(e.selectionStart===null)return;text=e.value.slice(e.selectionStart,e.selectionEnd)}
            else if(e.isContentEditable)text=getSelection().toString();else return;if(!text)return;
            text='\(mode)'==='upper'?text.toLocaleUpperCase():'\(mode)'==='lower'?text.toLocaleLowerCase():text.toLocaleLowerCase().replace(/(^|\\s)(\\S)/gu,(_,a,b)=>a+b.toLocaleUpperCase());
            document.execCommand('insertText',false,text)})()
            """
            CefStringUtil.withCefString(script) { code in
                CefStringUtil.withCefString("") { url in frame.pointee.execute_java_script?(frame, code, url, 0) }
            }
        }
    }
}
