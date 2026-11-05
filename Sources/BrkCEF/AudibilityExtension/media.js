// This registry lives only in the bundled extension's isolated world. No DOM or window message bridge.
(() => {
  if (globalThis.__brkMedia) return;
  const ids = new WeakMap(), players = new Map();
  function elements(root) {
    const result = [...root.querySelectorAll('audio,video')];
    for (const node of root.querySelectorAll('*')) if (node.shadowRoot) result.push(...elements(node.shadowRoot));
    return result;
  }
  const registry = {
    snapshot() {
      const current = new Set();
      const result = elements(document).filter(e => e.readyState > 0).slice(0, 64).map(e => {
        let id = ids.get(e);
        if (!id) { id = crypto.randomUUID(); ids.set(e, id); }
        players.set(id, new WeakRef(e)); current.add(id);
        return {element:id, kind:e.localName, paused:e.paused, ended:e.ended, silent:e.muted, pictureInPicture:document.pictureInPictureElement === e};
      });
      for (const id of players.keys()) if (!current.has(id)) players.delete(id);
      return result;
    },
    async control(id, operation, volume) {
      const player = players.get(id)?.deref();
      if (!player?.isConnected) throw Error('Player is no longer in this document');
      switch (operation) {
        case 'play': await HTMLMediaElement.prototype.play.call(player); break;
        case 'pause': HTMLMediaElement.prototype.pause.call(player); break;
        case 'enterPictureInPicture':
          if (!(player instanceof HTMLVideoElement)) throw Error('This player has no video');
          await HTMLVideoElement.prototype.requestPictureInPicture.call(player); break;
        case 'exitPictureInPicture':
          if (document.pictureInPictureElement !== player) break;
          await document.exitPictureInPicture(); break;
        case 'setVolume': player.volume = Math.min(1, Math.max(0, volume)); break;
        default: throw Error('Unknown media operation');
      }
      return {paused:player.paused, pictureInPicture:document.pictureInPictureElement === player};
    }
  };
  Object.defineProperty(globalThis, '__brkMedia', {value:Object.freeze(registry)});
})();
