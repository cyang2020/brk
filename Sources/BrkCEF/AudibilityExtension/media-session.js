// Runs in the page's own world, before its scripts: the only place a page's Media Session action handlers can be seen.
// It remembers the two the mini player's previous and next buttons need (Arc: `MediaSessionState.hasNextTrack`) and
// nothing else. The page can reach this object through the symbol; all it can do with it is run its own handlers.
(() => {
  if (typeof MediaSession === 'undefined' || globalThis[Symbol.for('brk.mediaSession')]) return;
  const handlers = new Map();
  const native = MediaSession.prototype.setActionHandler;
  MediaSession.prototype.setActionHandler = function setActionHandler(action, handler) {
    const result = native.call(this, action, handler);
    if (action === 'nexttrack' || action === 'previoustrack') { if (handler) handlers.set(action, handler); else handlers.delete(action); }
    return result;
  };
  Object.defineProperty(globalThis, Symbol.for('brk.mediaSession'), {value: Object.freeze({
    tracks: () => ({next: handlers.has('nexttrack'), previous: handlers.has('previoustrack')}),
    run: operation => { const action = operation === 'nextTrack' ? 'nexttrack' : 'previoustrack'; handlers.get(action)?.({action}); },
  })});
})();
