// The preload bridge contract: channel names used by main and preload, and the shape of window.arc.
export const IPC = { ping: 'arc:ping' } as const;

export interface ArcApi {
  ping(): Promise<'pong'>;
}

declare global {
  interface Window {
    arc: ArcApi;
  }
}
