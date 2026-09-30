import type {
  BridgeState, ConsentRequest, LaunchOptions, OverlayState, Scope, ScopeMode, SyphBridge,
} from '../../shared/types'
import { demoDevices, demoLog } from './fixture'

/**
 * In Electron, `window.syph` comes from the preload script. In a plain
 * browser (design review, screenshots) this mock stands in, driven by the
 * query string: ?surface=main&section=chat&consent=1
 */
function mockBridge(): SyphBridge {
  const params = new URLSearchParams(location.search)
  const listeners = new Map<string, Set<(p: any) => void>>()
  const emit = (channel: string, payload: unknown) => listeners.get(channel)?.forEach((fn) => fn(payload))
  const modes: Record<Scope, ScopeMode> = {
    observe: 'allow', screen: 'allow', apps: 'allow', files_read: 'allow', clipboard: 'allow',
    control: 'ask', files_write: 'ask', shell: 'ask', browser: 'ask', office: 'ask', files_outside: 'ask',
  }
  const state: BridgeState = {
    deviceId: 'dev-1', link: 'online', current: null, log: demoLog, devices: demoDevices, hostName: 'STUDIO-PC',
    policy: { controlEnabled: true, modes, sharedFolders: ['C:\\Users\\Ryan\\Documents\\Syph', 'C:\\Users\\Ryan\\Desktop\\Invoices'] },
  }
  const push = () => emit('bridge', { ...state, policy: { ...state.policy, modes: { ...state.policy.modes } } })
  const consent: ConsentRequest = {
    id: 'demo', employee: 'Ines', scope: 'shell', operation: 'run_shell', headline: 'Run a PowerShell command',
    detail: 'New-Item -ItemType Directory -Force ~\\Documents\\Syph\\Invoices; Move-Item ~\\Downloads\\*invoice*.pdf ~\\Documents\\Syph\\Invoices',
    deadline: Date.now() + 51_000,
  }
  const overlay: OverlayState = { visible: true, employee: 'Atlas', activity: 'Reading the shipping sheet in Excel', tint: 'hsl(40 100% 77.5%)' }
  setTimeout(() => {
    if (params.get('surface') === 'consent') emit('consent', consent)
    if (params.get('surface') === 'pill' || params.get('surface') === 'glow') emit('overlay', overlay)
  }, 50)
  const noop = async () => {}
  return {
    launch: async () => ({ demo: true, section: params.get('section') ?? undefined, surface: params.get('surface') ?? 'main' } as LaunchOptions),
    api: async () => ({ ok: false, status: 0, error: 'Offline demo' }),
    getServer: async () => 'https://srv1982864.hstgr.cloud',
    setServer: noop, resolveUrl: async (p) => p, openExternal: async (u) => { window.open(u) },
    signedIn: noop, signedOut: noop,
    bridgeState: async () => state,
    setControl: async (on) => { state.policy.controlEnabled = on; push() },
    setScope: async (s, m) => { state.policy.modes[s] = m; push() },
    resetScopes: noop, addFolder: noop,
    removeFolder: async (p) => { state.policy.sharedFolders = state.policy.sharedFolders.filter((f) => f !== p); push() },
    revealFolder: noop, emergencyStop: async () => { state.policy.controlEnabled = false; push() },
    unlinkDevice: noop, consentDecide: noop, overlayStop: noop,
    toggleCommandBar: noop, hideCommandBar: noop, showMain: noop, setBadge: noop, notify: noop, window: noop,
    on(channel, fn) {
      if (!listeners.has(channel)) listeners.set(channel, new Set())
      listeners.get(channel)!.add(fn)
      return () => listeners.get(channel)!.delete(fn)
    },
    broadcast: noop,
  }
}

export const syph: SyphBridge = window.syph ?? mockBridge()
export const isElectron = !!window.syph
