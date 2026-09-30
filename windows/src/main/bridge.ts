import { app } from 'electron'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { randomUUID } from 'node:crypto'
import type {
  BridgeState, ConsentDecision, ConsentRequest, DeviceCommand, DeviceRecord, LinkState, LocalAction, Scope,
} from '../shared/types'
import { api } from './api'
import { Executor, type ExecutionResult } from './executor'
import { host as nativeHost } from './host'
import { Policy } from './policy'

export interface BridgeHost {
  broadcast(state: BridgeState): void
  askConsent(request: ConsentRequest): Promise<ConsentDecision>
  cancelConsent(): void
  showOverlay(employee: string, activity: string, tint: string): void
  hideOverlay(delayMs: number): void
}

const SCOPE_TITLES: Record<Scope, string> = {
  observe: 'See what’s open', screen: 'Read the screen', control: 'Click and type', apps: 'Open apps and links',
  clipboard: 'Clipboard', files_read: 'Read shared files', files_write: 'Change shared files', shell: 'Run PowerShell commands',
  browser: 'Use Syph’s browser', office: 'Work in Excel, Word and Outlook', files_outside: 'Read files outside shared folders',
}

/** Stable hue per employee id — the same hash the Mac app and renderer use. */
export function hueFor(id: string): string {
  let hash = 1469598103934665603n
  for (const byte of Buffer.from(id, 'utf8')) hash = ((hash ^ BigInt(byte)) * 1099511628211n) & 0xffffffffffffffffn
  const hues = [0.62, 0.55, 0.47, 0.72, 0.8, 0.08, 0.4]
  return `hsl(${Math.round(hues[Number(hash % BigInt(hues.length))] * 360)} 100% 77.5%)`
}

export function headline(c: DeviceCommand): string {
  const a = c.arguments as Record<string, string | undefined>
  const base = (p?: string) => (p ? path.basename(p) : 'a file')
  switch (c.operation) {
    case 'run_shell': return 'Run a PowerShell command'
    case 'write_file': return `Write ${base(a.path)}`
    case 'trash_file': return `Move ${base(a.path)} to the Recycle Bin`
    case 'type_text': return 'Type into the front app'
    case 'press_keys': return `Press ${a.keys ?? 'a shortcut'}`
    case 'click': case 'click_text': return `Click ${a.text ? `‘${a.text}’` : 'on screen'}`
    case 'press': return `Press ‘${a.title ?? 'a button'}’`
    case 'open_app': return `Open ${a.app ?? 'an app'}`
    case 'quit_app': return `Quit ${a.app ?? 'an app'}`
    case 'open_url': { try { return `Open ${new URL(String(a.url)).hostname}` } catch { return 'Open a link' } }
    case 'read_screen': case 'read_ui': return 'Read your screen'
    case 'set_value': return 'Fill in a field'
    case 'drag': return 'Drag on screen'
    case 'move': return 'Move the pointer'
    case 'read_text': return 'Read the text of a window'
    case 'window': return `${String(a.action ?? 'focus').replace(/_/g, ' ').replace(/^\w/, (x) => x.toUpperCase())} ${a.window ?? a.app ?? 'a window'}`
    case 'list_windows': return 'See what’s open'
    case 'list_apps': return 'See installed apps'
    case 'browser_open': { try { return `Open ${new URL(/^[a-z]+:/i.test(String(a.url)) ? String(a.url) : `https://${a.url}`).hostname} in Syph’s browser` } catch { return 'Open a web page' } }
    case 'browser_type': return 'Type into a web page'
    case 'browser_click': return 'Click on a web page'
    case 'excel_write': return 'Change a spreadsheet in Excel'
    case 'word_write': return 'Change a document in Word'
    case 'excel_save': case 'word_save': return a.save_as ? `Save as ${base(a.save_as)}` : 'Save the open file'
    case 'outlook_draft': return `Draft an email${a.to ? ` to ${a.to}` : ''} in Outlook`
    case 'outlook_list': case 'outlook_read': case 'outlook_search': return 'Read your Outlook mail'
    case 'excel_read': case 'word_read': return a.path ? `Read ${base(a.path)}` : 'Read the open Office file'
    case 'find_files': return a.everywhere ? `Search all your files for ‘${a.query}’` : `Search shared folders for ‘${a.query}’`
    default: return c.operation.replace(/_/g, ' ').replace(/^\w/, (s) => s.toUpperCase())
  }
}

export function detail(c: DeviceCommand): string {
  const a = c.arguments as Record<string, unknown>
  return String(a.command ?? a.text ?? a.path ?? a.url ?? a.keys ?? a.app ?? a.title ?? '')
}

/**
 * Links this PC to the workspace and runs what employees ask of it.
 * register → heartbeat every 25 s → long-poll /commands/next.
 */
export class DeviceBridge {
  readonly policy = new Policy()
  readonly deviceId: string
  private executor = new Executor(this.policy)
  private link: LinkState = 'idle'
  private linkError = ''
  private current: LocalAction | null = null
  private log: LocalAction[] = []
  private devices: DeviceRecord[] = []
  private running = false
  private heartbeatTimer: NodeJS.Timeout | null = null
  private syncTimer: NodeJS.Timeout | null = null
  private abortCurrent = false

  constructor(private host: BridgeHost) {
    const idFile = path.join(app.getPath('userData'), 'device-id')
    let id = ''
    try { id = fs.readFileSync(idFile, 'utf8').trim() } catch { /* new install */ }
    if (!/^[0-9a-f-]{36}$/.test(id)) {
      id = randomUUID()
      fs.mkdirSync(path.dirname(idFile), { recursive: true })
      fs.writeFileSync(idFile, id)
    }
    this.deviceId = id
    this.policy.onChange = () => { this.emit(); this.scheduleSync() }
  }

  get isRunning() { return this.current !== null }

  state(): BridgeState {
    return {
      deviceId: this.deviceId, link: this.link, linkError: this.linkError, current: this.current, log: this.log,
      devices: this.devices, policy: this.policy.state, hostName: os.hostname(),
    }
  }

  private emit() { this.host.broadcast(this.state()) }

  private setLink(link: LinkState, error = '') {
    if (this.link === link && this.linkError === error) return
    this.link = link; this.linkError = error; this.emit()
  }

  start() {
    if (this.running) return
    this.running = true
    this.setLink('linking')
    void this.pollLoop()
    this.heartbeatTimer = setInterval(() => void this.heartbeat(), 25_000)
  }

  stop() {
    this.running = false
    if (this.heartbeatTimer) clearInterval(this.heartbeatTimer)
    this.heartbeatTimer = null
    this.setLink('idle')
  }

  /** Stop button, tray switch and Ctrl+Alt+. all land here. */
  emergencyStop() {
    this.abortCurrent = true
    this.policy.setEnabled(false)
    // Stop mid-action: killing the helper halts typing or dragging at once;
    // it restarts on the next command.
    if (this.current) nativeHost.stop()
    this.host.cancelConsent()
    this.host.hideOverlay(0)
    if (this.current) {
      this.record({ ...this.current, status: 'cancelled', summary: 'Stopped by you.', finishedAt: Date.now() })
      this.current = null
      this.emit()
    }
  }

  private registration() {
    return {
      name: os.hostname() || 'PC',
      platform: 'windows',
      model: (os.cpus()[0]?.model ?? 'PC').replace(/\s+/g, ' ').trim().slice(0, 110),
      osVersion: `${os.version()} ${os.release()}`.slice(0, 60),
      appVersion: app.getVersion(),
      controlEnabled: this.policy.state.controlEnabled,
      scopes: this.policy.wireScopes(),
      capabilities: this.executor.capabilities(),
    }
  }

  private async register() {
    const res = await api.request<DeviceRecord>('PUT', `/api/v1/devices/${this.deviceId}`, this.registration())
    if (!res.ok) throw Object.assign(new Error(res.error ?? 'Could not link this PC.'), { status: res.status })
    await this.refreshDevices()
  }

  private async heartbeat() {
    const res = await api.request<DeviceRecord>('POST', `/api/v1/devices/${this.deviceId}/heartbeat`, {
      controlEnabled: this.policy.state.controlEnabled, scopes: this.policy.wireScopes(),
      capabilities: this.executor.capabilities(),
    })
    if (res.ok) this.setLink('online')
    else if (res.status === 404) { try { await this.register() } catch { /* next beat */ } }
    else if (res.status === 401) this.setLink('offline', 'Signed out')
    else this.setLink('offline', res.error)
  }

  private scheduleSync() {
    if (!this.running) return
    if (this.syncTimer) clearTimeout(this.syncTimer)
    this.syncTimer = setTimeout(() => { void this.heartbeat(); void this.refreshDevices() }, 300)
  }

  async refreshDevices() {
    const res = await api.request<DeviceRecord[]>('GET', '/api/v1/devices')
    if (res.ok && res.data) { this.devices = res.data; this.emit() }
  }

  async unlink(id: string) {
    await api.request('DELETE', `/api/v1/devices/${id}`)
    await this.refreshDevices()
  }

  private async pollLoop() {
    let backoff = 2000
    while (this.running) {
      try {
        if (this.link !== 'online') {
          await this.register()
          this.setLink('online')
          backoff = 2000
        }
        if (!this.policy.state.controlEnabled) { await sleep(3000); continue }
        const res = await api.request<{ command: DeviceCommand | null }>('GET', `/api/v1/devices/${this.deviceId}/commands/next?wait=20`, undefined, { timeout: 40 })
        if (!res.ok) throw Object.assign(new Error(res.error ?? 'Poll failed'), { status: res.status })
        backoff = 2000
        if (res.data?.command) await this.handle(res.data.command)
      } catch (e) {
        const status = (e as { status?: number }).status
        if (status === 401) { this.setLink('offline', 'Signed out'); this.running = false; return }
        this.setLink('offline', (e as Error).message)
        await sleep(backoff)
        backoff = Math.min(backoff * 2, 30_000)
      }
    }
  }

  private async handle(command: DeviceCommand) {
    this.abortCurrent = false
    const scope = this.policy.scopeForCommand(command.operation, command.arguments)
    let action: LocalAction = {
      id: command.id, employee: command.employeeName, employeeId: command.employeeId, operation: command.operation,
      scope, status: 'running', summary: headline(command), detail: detail(command), startedAt: Date.now(),
    }
    this.current = action
    this.emit()

    if (!scope) return this.finish(action, 'failed', { ok: false, summary: command.operation === 'applescript' ? 'AppleScript only runs on a Mac.' : `Unknown operation ${command.operation}.` })
    const mode = this.policy.mode(scope)
    if (mode === 'off') return this.finish(action, 'denied', { ok: false, summary: `'${SCOPE_TITLES[scope]}' is switched off on this PC.` })
    if (mode === 'ask') {
      const decision = await this.host.askConsent({
        id: command.id, employee: command.employeeName || 'An employee', scope, operation: command.operation,
        headline: headline(command), detail: detail(command), deadline: Date.now() + 60_000,
      })
      if (decision === 'deny') return this.finish(action, 'denied', { ok: false, summary: 'You declined on your PC.' })
      if (decision === 'always') this.policy.setMode(scope, 'allow')
    }
    if (this.abortCurrent || !this.policy.state.controlEnabled) {
      return this.finish(action, 'denied', { ok: false, summary: 'Computer control was switched off.' })
    }

    const tint = command.employeeId ? hueFor(command.employeeId) : 'hsl(224 100% 81%)'
    const visible = scope !== 'observe' && scope !== 'clipboard'
    if (visible) this.host.showOverlay(command.employeeName, action.summary, tint)
    if (command.operation === 'notify') this.host.showOverlay(command.employeeName, String(command.arguments.text ?? 'Heads up'), 'hsl(158 58% 68%)')
    void this.report(command.id, 'running', action.summary, {})
    const result = await this.executor.run(command, scope)
    if (visible || command.operation === 'notify') this.host.hideOverlay(command.operation === 'notify' ? 5000 : 1400)
    if (this.abortCurrent) return this.finish(action, 'failed', { ok: false, summary: 'Stopped by the owner.' })
    action = { ...action }
    return this.finish(action, result.ok ? 'succeeded' : 'failed', result)
  }

  private async finish(action: LocalAction, status: string, result: ExecutionResult) {
    const data = result.data ?? {}
    const done: LocalAction = {
      ...action, status, summary: result.summary, finishedAt: Date.now(),
      thumbnail: typeof data._image === 'string' ? `data:image/jpeg;base64,${data._image}` : undefined,
    }
    this.record(done)
    if (this.current?.id === action.id) this.current = null
    this.emit()
    await this.report(action.id, status, result.summary, data)
  }

  private record(action: LocalAction) {
    this.log = [action, ...this.log.filter((a) => a.id !== action.id)].slice(0, 120)
  }

  private async report(commandId: string, status: string, summary: string, data: Record<string, unknown>) {
    await api.request('POST', `/api/v1/devices/${this.deviceId}/commands/${commandId}`, {
      status, summary: summary.slice(0, 3900), data,
    })
  }
}

function sleep(ms: number) { return new Promise((r) => setTimeout(r, ms)) }
