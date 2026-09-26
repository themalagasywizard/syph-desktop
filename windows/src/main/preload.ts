import { contextBridge, ipcRenderer } from 'electron'
import type { SyphBridge } from '../shared/types'

const call = (channel: string) => (...args: unknown[]) => ipcRenderer.invoke(`syph:${channel}`, ...args)

const bridge: SyphBridge = {
  launch: call('launch') as SyphBridge['launch'],
  api: call('api') as SyphBridge['api'],
  getServer: call('getServer') as SyphBridge['getServer'],
  setServer: call('setServer') as SyphBridge['setServer'],
  resolveUrl: call('resolveUrl') as SyphBridge['resolveUrl'],
  openExternal: call('openExternal') as SyphBridge['openExternal'],
  signedIn: call('signedIn') as SyphBridge['signedIn'],
  signedOut: call('signedOut') as SyphBridge['signedOut'],
  bridgeState: call('bridgeState') as SyphBridge['bridgeState'],
  setControl: call('setControl') as SyphBridge['setControl'],
  setScope: call('setScope') as SyphBridge['setScope'],
  resetScopes: call('resetScopes') as SyphBridge['resetScopes'],
  addFolder: call('addFolder') as SyphBridge['addFolder'],
  removeFolder: call('removeFolder') as SyphBridge['removeFolder'],
  revealFolder: call('revealFolder') as SyphBridge['revealFolder'],
  emergencyStop: call('emergencyStop') as SyphBridge['emergencyStop'],
  unlinkDevice: call('unlinkDevice') as SyphBridge['unlinkDevice'],
  consentDecide: call('consentDecide') as SyphBridge['consentDecide'],
  overlayStop: call('overlayStop') as SyphBridge['overlayStop'],
  toggleCommandBar: call('toggleCommandBar') as SyphBridge['toggleCommandBar'],
  hideCommandBar: call('hideCommandBar') as SyphBridge['hideCommandBar'],
  showMain: call('showMain') as SyphBridge['showMain'],
  setBadge: call('setBadge') as SyphBridge['setBadge'],
  notify: call('notify') as SyphBridge['notify'],
  window: call('window') as SyphBridge['window'],
  on(channel, fn) {
    const listener = (_e: unknown, payload: unknown) => fn(payload)
    ipcRenderer.on(`syph:${channel}`, listener)
    return () => { ipcRenderer.removeListener(`syph:${channel}`, listener) }
  },
  broadcast(channel, payload) { ipcRenderer.send('syph:broadcast', channel, payload) },
}

contextBridge.exposeInMainWorld('syph', bridge)
