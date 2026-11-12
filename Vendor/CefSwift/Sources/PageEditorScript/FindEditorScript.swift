import Foundation

/// The page side of find's selection capture, scoped search and replacement: one expression whose value is a function taking a JSON request
/// and answering JSON. CEF's renderer evaluates it as each document's context is created and keeps the function, never on window; BrkCore
/// keeps it on the global of Chrome's isolated world for the document. Shared by both engines, so it lives outside CefKit.
public enum FindEditorScript {
    public static let source = #"""
(() => {
    const parse = JSON.parse, stringify = JSON.stringify;
    const tickets = new Map(), results = new Map();
    let composing = false, revision = 0;
    const changed = () => { revision++; };
    document.addEventListener('compositionstart', () => { composing = true; changed(); }, true);
    document.addEventListener('compositionend', () => { composing = false; changed(); }, true);
    document.addEventListener('input', changed, true);
    document.addEventListener('selectionchange', () => {
        for (const t of tickets.values()) if (!same(t.signature,signature(t))) {changed();break;}
    }, true);
    const observer = new MutationObserver(changed);
    let observing = false;
    function sync() { if (observer.takeRecords().length) changed(); }
    function fail(message) { return {status:'refused', message}; }
    function permitted() {
        try { void top.document.documentElement; return true; }
        catch (_) { return false; }
    }
    function kind(el) {
        if (!el || el.getRootNode() !== document || el.closest('[inert]')) return null;
        if (el instanceof HTMLInputElement) {
            return ['text','search','url','tel'].includes(el.type) && !el.disabled && !el.readOnly ? 'input' : null;
        }
        if (el instanceof HTMLTextAreaElement) return !el.disabled && !el.readOnly ? 'textArea' : null;
        if (el.isContentEditable) {
            while (el.parentElement?.isContentEditable) el = el.parentElement;
            if (el.querySelector('[contenteditable],input,textarea,select,button,img,br,div,p,table,ul,ol') ||
                el.getAttribute('aria-readonly') === 'true' || el.getAttribute('role') === 'textbox') return null;
            return 'contentEditable';
        }
        return null;
    }
    function root(el) { while (el?.parentElement?.isContentEditable) el = el.parentElement; return el; }
    function protectedControl(el) {
        return el instanceof HTMLInputElement && (!['text','search','url','tel'].includes(el.type) || el.disabled || el.readOnly) ||
            el instanceof HTMLTextAreaElement && (el.disabled || el.readOnly) ||
            el?.closest('[aria-readonly="true"],[inert]');
    }
    function text(t) { return t.kind === 'contentEditable' ? t.el.textContent : t.el.value; }
    function signature(t) {
        if (t.kind && t.kind !== 'contentEditable') return [t.el.selectionStart, t.el.selectionEnd, t.el.selectionDirection].join(':');
        const s = getSelection();
        return s && s.rangeCount ? [s.anchorNode,s.anchorOffset,s.focusNode,s.focusOffset] : null;
    }
    function same(a,b) { return Array.isArray(a) ? Array.isArray(b) && a.every((v,i)=>v===b[i]) : a===b; }
    function stamp(t) { sync(); t.rev=revision; t.signature=signature(t); if(t.kind) t.text=text(t); }
    function valid(t) {
        sync();
        return t && permitted() && !composing && t.el?.isConnected && !protectedControl(t.el) &&
            (!t.kind || kind(t.el)===t.kind && root(document.activeElement)===t.el && text(t)===t.text) && t.rev===revision && same(t.signature,signature(t));
    }
    function matches(value, query, sensitive) {
        if (!query) return [];
        // RegExp is only the Unicode case-folding engine. Every metacharacter is escaped; offsets remain UTF-16.
        const escaped = query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        return Array.from(value.matchAll(new RegExp(escaped, sensitive ? 'gu':'giu')), m=>[m.index,m.index+m[0].length]);
    }
    function select(t, start, end) {
        if (t.kind !== 'contentEditable') t.el.setSelectionRange(start,end);
        else {
            const walker=document.createTreeWalker(t.el,NodeFilter.SHOW_TEXT); let n, pos=0, a=null,b=null;
            while ((n=walker.nextNode())) {
                if (!a && start<=pos+n.length) a=[n,start-pos];
                if (end<=pos+n.length) {b=[n,end-pos]; break;} pos+=n.length;
            }
            if (!a || !b) return false;
            const r=document.createRange();r.setStart(...a);r.setEnd(...b);
            const s=getSelection();s.removeAllRanges();s.addRange(r);
        }
        stamp(t); return true;
    }
    function capture(a) {
        if(!permitted()) return fail('Selection in cross-origin frames is not supported.');
        if(composing) return fail('Finish composing text before using Find.');
        let el=document.activeElement;
        if(protectedControl(el)) return fail('This control is protected or read-only.');
        if(el?.tagName==='IFRAME' || el?.shadowRoot) return fail('Select text in a supported page field.');
        const k=kind(el); if(k==='contentEditable') el=root(el);
        const s=getSelection();
        let selected=''; let range=null;
        if(k && k!=='contentEditable') selected=el.value.slice(el.selectionStart,el.selectionEnd);
        else if(s?.rangeCount) {
            range=s.getRangeAt(0).cloneRange();
            if(protectedControl(range.startContainer.parentElement) || protectedControl(range.endContainer.parentElement)) return fail('This selection is protected.');
            selected=s.toString();
            if(!k) el=range.commonAncestorContainer.nodeType===1 ? range.commonAncestorContainer : range.commonAncestorContainer.parentElement;
        }
        if(!el) return fail('Select text in the page first.');
        if(!observing) {observer.observe(document,{subtree:true,childList:true,characterData:true,attributes:true});observing=true;}
        const t={el,kind:k,range,index:-1,query:null}; stamp(t); tickets.clear(); tickets.set(a.ticket,t);
        return {status:'selection',text:selected,editable:k};
    }
    function search(a) {
        const t=tickets.get(a.ticket);
        if(!valid(t) || !t.kind) return fail('The editable selection changed. Select the field again.');
        const list=matches(text(t),a.query,a.caseSensitive);
        t.index=a.step ? (t.index+(a.forward?1:-1)+list.length)%list.length : 0;
        t.query=a.query;
        if(list.length) {select(t,...list[t.index]); t.el.scrollIntoView({block:'nearest'});}
        return {status:'matches',count:list.length,ordinal:list.length?t.index+1:0};
    }
    function jump(a) {
        const t=tickets.get(a.ticket);
        if(!valid(t)) return fail('The selection changed. Select text in the page again.');
        if(t.range) {
            if(!t.range.startContainer.isConnected || !t.range.endContainer.isConnected) return fail('The selection is no longer on this page.');
            t.el.scrollIntoView({block:'center'});
            const r=t.range.getBoundingClientRect(); window.scrollBy(0,r.top-innerHeight/2);
        } else { t.el.scrollIntoView({block:'center'}); }
        return {status:'jumped'};
    }
    function replace(a) {
        const t=tickets.get(a.ticket);
        if(!valid(t) || !t.kind) return fail('The editable selection changed. Select the field again.');
        if(!a.query) return fail('Enter text to find first.');
        if(a.replacement.includes('\n') || a.replacement.includes('\r')) return fail('Replacement must be one line.');
        const initial=text(t), list=matches(initial,a.query,a.caseSensitive);
        let plan=list;
        if(!a.all) {
            if(t.index<0 || t.query!==a.query || !list[t.index]) return fail('Find a match in this field first.');
            plan=[list[t.index]];
        }
        let applied=0, expected=initial;
        for(const [start,end] of plan.slice().reverse()) {
            if(!valid(t)) return {status:'partial',applied,message:'The field changed during replacement.'};
            t.el.focus({preventScroll:true});
            if(!select(t,start,end)) return {status:'partial',applied,message:'The selection is no longer editable.'};
            const before=new InputEvent('beforeinput',{bubbles:true,cancelable:true,composed:true,inputType:'insertText',data:a.replacement});
            if(!t.el.dispatchEvent(before)) return {status:'partial',applied,message:'The page cancelled replacement.'};
            if(!valid(t)) return {status:'partial',applied,message:'The page changed the selection before replacement.'};
            const wanted=expected.slice(0,start)+a.replacement+expected.slice(end);
            const accepted=document.execCommand('insertText',false,a.replacement);
            // A true return proves the native edit command ran, even if a synchronous input handler rewrites it.
            if(accepted) applied++;
            if(!accepted || !t.el.isConnected || text(t)!==wanted) {
                tickets.clear(); return {status:'partial',applied,message:'The page changed or refused the remaining edits.'};
            }
            expected=wanted; stamp(t);
        }
        tickets.clear(); return {status:'edited',applied};
    }
    return raw => {
        let a;
        try {
            a=parse(raw);
            if(a.op==='release') {tickets.clear();observer.disconnect();observing=false;return stringify({status:'released'});}
            if(a.op==='replace' && results.has(a.request)) return results.get(a.request);
            if(a.op==='replace') results.set(a.request,stringify({status:'unconfirmed'}));
            let r;
            switch(a.op) {
                case 'revision':
                    if(!observing){observer.observe(document,{subtree:true,childList:true,characterData:true,attributes:true});observing=true;}
                    sync();r={status:'revision',revision};break;
                case 'capture':r=capture(a);break;
                case 'search':r=search(a);break;
                case 'jump':r=jump(a);break;
                case 'validate':r={status:valid(tickets.get(a.ticket))?'valid':'invalid'};break;
                case 'replace':r=replace(a);break;
                default:r=fail('This find operation is unavailable.');
            }
            const out=stringify(r);
            if(a.op==='replace') results.set(a.request,out);
            return out;
        } catch (_) {
            const out=stringify({status:a?.op==='replace'?'unconfirmed':'refused',message:'This page does not support this operation.'});
            if(a?.op==='replace') results.set(a.request,out);
            return out;
        }
    };
})()
"""#
}
