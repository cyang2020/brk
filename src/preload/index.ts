import { contextBridge, ipcRenderer } from 'electron';
import { IPC, type ArcApi } from '../shared/ipc';

const api: ArcApi = {
  ping: () => ipcRenderer.invoke(IPC.ping),
};

contextBridge.exposeInMainWorld('arc', api);
