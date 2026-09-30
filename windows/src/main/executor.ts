import { clipboard, shell } from 'electron'
import fs from 'node:fs'
import path from 'node:path'
import type { DeviceCommand } from '../shared/types'
import type { Policy } from './policy'
import { host, type HostCallError } from './host'
import { runCommand, runScript, type ScriptResult } from './powershell'

export type ExecutionResult = ScriptResult

const fail = (summary: string, data?: Record<string, unknown>): ExecutionResult => ({ ok: false, summary, data })

function str(command: DeviceCommand, key: string): string | undefined {
  const value = command.arguments[key]
  if (value === undefined || value === null || value === '') return undefined
  return String(value)
}

function num(command: DeviceCommand, key: string): number | undefined {
  const value = Number(command.arguments[key])
  return Number.isFinite(value) ? value : undefined
}

/** Operations that only exist with the native helper. */
export const HOST_OPERATIONS = ['set_value', 'drag', 'move', 'read_text', 'list_windows', 'window', 'list_apps', 'element_targets'] as const

/** Arguments that describe a point: an element id, or x/y in screen or last-screenshot pixels. */
function pointArgs(a: Record<string, unknown>, prefix = ''): Record<string, unknown> | undefined {
  const el = a[`${prefix}element`]
  if (el !== undefined && el !== null && el !== '') return { element: Number(el) }
  const x = a[`${prefix}x`], y = a[`${prefix}y`]
  if (x === undefined || y === undefined || x === '' || y === '') return undefined
  return { x: Number(x), y: Number(y), space: a.space === 'image' ? 'image' : 'screen' }
}

function describe(e: any): string {
  if (!e) return ''
  return `${e.role ?? 'control'}${e.name ? ` ‘${e.name}’` : ''}`
}

/**
 * Performs computer commands on this PC. Scope and consent are checked by the
 * bridge before anything here runs; file paths are re-checked here against
 * the shared folders on every call. Screen, input, UI Automation, windows and
 * apps go through SyphHost.exe; the PowerShell scripts remain a fallback for
 * the original operations when the helper is unavailable.
 */
export class Executor {
  constructor(private policy: Policy) {}

  /** Operations beyond the original set that this PC can run right now; reported to the server. */
  capabilities(): string[] {
    return host.available ? [...HOST_OPERATIONS] : []
  }

  /** Calls the native helper and shapes its answer (or error) as a device result. */
  private async host(method: string, params: Record<string, unknown>, summary: (r: any) => string, data?: (r: any) => Record<string, unknown>, timeoutMs?: number): Promise<ExecutionResult> {
    try {
      const r = await host.call(method, params, timeoutMs)
      return { ok: true, summary: summary(r), data: data ? data(r) : r }
    } catch (e) {
      const err = e as HostCallError
      return fail(err.message, { code: err.code ?? 'failed' })
    }
  }

  private needsHost(op: string): ExecutionResult {
    return fail(`${op} needs the Syph helper, which isn't running on this PC. Reinstall Syph or use the other computer operations.`, { code: 'unavailable' })
  }

  async run(command: DeviceCommand): Promise<ExecutionResult> {
    const a = command.arguments
    const useHost = host.available
    try {
      switch (command.operation) {
        case 'observe':
          if (!useHost) return await runScript('observe', {})
          return await this.host('observe', {}, (r) => `${r.front?.app || 'Nothing'} is in front${r.front?.title ? ` (‘${r.front.title}’)` : ''}; ${r.windows.length} windows open.`, (r) => ({
            app: r.front?.app, window: r.front?.title, platform: 'windows',
            windows: r.windows.map((w: any) => ({ app: w.app, title: w.title, handle: w.handle, state: w.state, monitor: w.monitor })),
            running_apps: r.apps, monitors: r.monitors.map((m: any) => ({ index: m.index, width: m.width, height: m.height, primary: m.primary, scale: m.scalePercent })),
            screen: r.monitors[0] ? { width: r.monitors[0].width, height: r.monitors[0].height } : undefined,
            pointer: r.cursor, focused: r.focused,
          }))
        case 'read_screen':
          if (!useHost) return await runScript('screen', { thumbnail: true }, 90_000)
          return await this.host('ocr', { thumbnail: true, monitor: a.monitor }, (r) => r.note && !r.lines.length ? `Captured the screen. ${r.note}` : `Read ${r.lines.length} lines of text on screen.`, undefined, 60_000)
        case 'read_ui':
          if (!useHost) return await runScript('ui', {})
          return await this.host('ui.elements', { limit: num(command, 'limit') ?? 250, window: str(command, 'window') }, (r) => `Found ${r.elements.length} controls in ${r.app}${r.window ? ` - ${r.window}` : ''}.`)
        case 'press': {
          const el = num(command, 'element')
          const title = str(command, 'title') ?? str(command, 'text')
          if (!useHost) return title ? await runScript('ui', { press: title, limit: 600 }) : fail('press needs a title.')
          if (el !== undefined) return await this.host('ui.act', { id: el, action: 'invoke' }, (r) => `Pressed ${describe(r.element) || `element ${el}`}.`)
          if (!title) return fail('press needs a title or an element id.')
          const found = await host.call('ui.find', { name: title })
          if (!found.element) return fail(`No control named ‘${title}’ in the front window.`, { visible: (found.candidates ?? []).join(' · ') })
          return await this.host('ui.act', { id: found.element.id, action: 'invoke' }, () => `Pressed ${describe(found.element)}.`)
        }
        case 'click': {
          const at = pointArgs(a)
          if (!at) return fail('click needs x and y, or an element id.')
          if (!useHost) return at.element !== undefined ? this.needsHost('Clicking an element') : await runScript('input', { mode: 'click', ...at, button: str(command, 'button') ?? 'left', count: num(command, 'count') ?? 1 })
          return await this.host('input.click', { ...at, button: str(command, 'button') ?? 'left', count: num(command, 'count') ?? 1, modifiers: a.modifiers }, (r) => `Clicked at ${r.x}, ${r.y}.`)
        }
        case 'click_text': return await this.clickText(command, useHost)
        case 'type_text': {
          const text = str(command, 'text')
          if (!text) return fail('type_text needs text.')
          if (!useHost) return await runScript('input', { mode: 'type', text })
          return await this.host('input.type', { text, element: num(command, 'element') }, (r) => `Typed ${text.length} characters${r.focused ? ` into ${describe(r.focused)}` : ''}.`)
        }
        case 'set_value': {
          const el = num(command, 'element')
          if (!useHost) return this.needsHost('set_value')
          if (el === undefined) return fail('set_value needs an element id from a snapshot or read_ui.')
          const text = str(command, 'text') ?? str(command, 'value') ?? ''
          return await this.host('ui.act', { id: el, action: 'set_value', value: text }, (r) => `Set ${describe(r.element)} to ${text.length} characters.`)
        }
        case 'press_keys': {
          const keys = str(command, 'keys')
          if (!keys) return fail('press_keys needs keys, like ctrl+s.')
          if (!useHost) return await runScript('input', { mode: 'keys', keys })
          return await this.host('input.keys', { keys, hold: num(command, 'hold') }, () => `Pressed ${keys}.`)
        }
        case 'scroll': {
          const direction = str(command, 'direction') ?? 'down', amount = num(command, 'amount') ?? 5
          if (!useHost) return await runScript('input', { mode: 'scroll', direction, amount })
          return await this.host('input.scroll', { direction, amount, ...(pointArgs(a) ?? {}) }, () => `Scrolled ${direction}.`)
        }
        case 'move': {
          const at = pointArgs(a)
          if (!at) return fail('move needs x and y, or an element id.')
          if (!useHost) return this.needsHost('move')
          return await this.host('input.move', at, (r) => `Moved the pointer to ${r.x}, ${r.y}.`)
        }
        case 'drag': {
          const from = pointArgs(a, 'from_'), to = pointArgs(a, 'to_')
          if (!from || !to) return fail('drag needs from_x/from_y (or from_element) and to_x/to_y (or to_element).')
          if (!useHost) return this.needsHost('drag')
          return await this.host('input.drag', { from, to, button: str(command, 'button') ?? 'left' }, (r) => `Dragged from ${r.from.x}, ${r.from.y} to ${r.to.x}, ${r.to.y}.`)
        }
        case 'read_text': {
          const el = num(command, 'element')
          if (el === undefined) return fail('read_text needs an element id (a document, editor or field) from a snapshot or read_ui.')
          if (!useHost) return this.needsHost('read_text')
          return await this.host('ui.text', { id: el, max: 200_000 }, (r) => `Read ${r.length} characters from element ${el}.`, (r) => ({ content: String(r.text).slice(0, 100_000), length: r.length }))
        }
        case 'list_windows':
          if (!useHost) return await runScript('observe', {})
          return await this.host('windows.list', { limit: 60 }, (r) => `${r.windows.length} windows open.`)
        case 'window': {
          if (!useHost) return this.needsHost('window')
          const action = str(command, 'action') ?? 'focus'
          const target = { window: str(command, 'window') ?? str(command, 'app') ?? str(command, 'title'), handle: num(command, 'handle') }
          return await this.host('window.act', { ...target, action, x: num(command, 'x'), y: num(command, 'y'), w: num(command, 'w') ?? num(command, 'width'), h: num(command, 'h') ?? num(command, 'height'), monitor: num(command, 'monitor') },
            (r) => r.closed ? `Closed ‘${r.window.title}’.` : `${action.replace(/_/g, ' ')}: ‘${r.window.title}’ (${r.window.w}×${r.window.h} at ${r.window.x}, ${r.window.y}).`)
        }
        case 'list_apps':
          if (!useHost) return this.needsHost('list_apps')
          return await this.host('apps.list', { query: str(command, 'query') ?? str(command, 'app') }, (r) => `${r.apps.length} apps in Start.`)
        case 'open_app': {
          const app = str(command, 'app')
          if (!app) return fail('open_app needs an app name.')
          if (!useHost) return await runScript('apps', { mode: 'open', app })
          return await this.hostResult('apps.open', { app }, 30_000)
        }
        case 'quit_app': {
          const app = str(command, 'app')
          if (!app) return fail('quit_app needs an app name.')
          if (!useHost) return await runScript('apps', { mode: 'quit', app })
          return await this.hostResult('apps.quit', { app })
        }
        case 'open_url': return await this.openUrl(command)
        case 'list_files': return this.listFiles(command)
        case 'read_file': return this.readFile(command)
        case 'write_file': return this.writeFile(command)
        case 'trash_file': return await this.trashFile(command)
        case 'run_shell': return await this.runShell(command)
        case 'applescript': return fail('AppleScript only runs on a Mac. On this PC, use run_shell with a PowerShell command.')
        case 'clipboard_read': {
          const text = clipboard.readText()
          return { ok: true, summary: text ? `Read ${text.length} characters from the clipboard.` : 'The clipboard has no text.', data: { content: text.slice(0, 20_000) } }
        }
        case 'clipboard_write': {
          const text = str(command, 'text') ?? str(command, 'content') ?? ''
          clipboard.writeText(text)
          return { ok: true, summary: `Copied ${text.length} characters to the clipboard.` }
        }
        case 'notify': return { ok: true, summary: 'Showed the notice.' }
        default: return fail(`This PC doesn't know how to ${command.operation}.`)
      }
    } catch (e) {
      return fail((e as Error).message)
    }
  }

  /** Host methods that already answer in {ok, summary, data} form. */
  private async hostResult(method: string, params: Record<string, unknown>, timeoutMs?: number): Promise<ExecutionResult> {
    try {
      const r = await host.call(method, params, timeoutMs)
      return { ok: !!r.ok, summary: String(r.summary ?? ''), data: r.data ?? {} }
    } catch (e) {
      const err = e as HostCallError
      return fail(err.message, { code: err.code ?? 'failed' })
    }
  }

  private async clickText(command: DeviceCommand, useHost: boolean): Promise<ExecutionResult> {
    const query = str(command, 'text')
    if (!query) return fail('click_text needs text.')
    const count = num(command, 'count') ?? 1
    if (useHost) {
      // A control with that name is exact and immune to OCR mistakes; try it first.
      try {
        const found = await host.call('ui.find', { name: query })
        const el = found.element
        if (el && el.w > 0 && String(el.name).toLowerCase().includes(query.toLowerCase().trim())) {
          const r = await host.call('input.click', { element: el.id, count })
          return { ok: true, summary: `Clicked ${describe(el)}.`, data: { x: r.x, y: r.y, element: el.id } }
        }
      } catch { /* fall back to OCR */ }
    }
    const reading = useHost
      ? await this.host('ocr', { thumbnail: false }, () => '', undefined, 60_000)
      : await runScript('screen', { thumbnail: false }, 90_000)
    if (!reading.ok) return reading
    const lines = ((reading.data?.lines as Array<{ text: string; x: number; y: number; w: number; left: number }>) ?? [])
    const needle = query.toLowerCase().trim()
    const exact = lines.find((l) => l.text.toLowerCase().trim() === needle)
    const line = exact ?? lines.filter((l) => l.text.toLowerCase().includes(needle)).sort((x, y) => x.text.length - y.text.length)[0]
    if (!line) {
      return fail(`'${query}' isn't visible on screen.`, { visible: lines.slice(0, 30).map((l) => l.text).join(' · ') })
    }
    // Aim at the matched words inside the line, by character offset.
    const at = line.text.toLowerCase().indexOf(needle)
    const perChar = line.w / Math.max(1, line.text.length)
    const x = at >= 0 ? Math.round(line.left + (at + needle.length / 2) * perChar) : line.x
    const clicked = useHost
      ? await this.host('input.click', { x, y: line.y, count }, () => '')
      : await runScript('input', { mode: 'click', x, y: line.y, count })
    return clicked.ok ? { ok: true, summary: `Clicked '${line.text}'.`, data: { x, y: line.y } } : clicked
  }

  private async openUrl(command: DeviceCommand): Promise<ExecutionResult> {
    const raw = str(command, 'url')
    if (!raw) return fail('open_url needs a url.')
    const fixed = raw.includes('://') || raw.startsWith('mailto:') ? raw : `https://${raw}`
    let url: URL
    try { url = new URL(fixed) } catch { return fail('That link is not valid.') }
    if (!['http:', 'https:', 'mailto:', 'tel:'].includes(url.protocol)) return fail('Only web, mail and similar links can be opened.')
    await shell.openExternal(url.toString())
    return { ok: true, summary: `Opened ${url.hostname || fixed}.` }
  }

  private outside(p: string) {
    return `'${p}' is outside the folders the owner shared (${this.policy.state.sharedFolders.join(', ')}).`
  }

  private listFiles(command: DeviceCommand): ExecutionResult {
    const raw = str(command, 'path')
    if (!raw) {
      const entries = this.policy.state.sharedFolders.map((f) => ({ name: path.basename(f), path: f, kind: 'folder' }))
      return { ok: true, summary: `${entries.length} shared folder${entries.length === 1 ? '' : 's'}.`, data: { entries } }
    }
    const dir = this.policy.resolveShared(raw)
    if (!dir) return fail(this.outside(raw))
    const entries = fs.readdirSync(dir, { withFileTypes: true }).filter((e) => !e.name.startsWith('.')).slice(0, 300).map((e) => {
      const full = path.join(dir, e.name)
      let size = 0, modified = ''
      try { const st = fs.statSync(full); size = st.size; modified = st.mtime.toISOString() } catch { /* locked */ }
      return { name: e.name, path: full, kind: e.isDirectory() ? 'folder' : 'file', size, modified }
    })
    return { ok: true, summary: `${entries.length} items in ${path.basename(dir)}.`, data: { entries, path: dir } }
  }

  private readFile(command: DeviceCommand): ExecutionResult {
    const raw = str(command, 'path')
    if (!raw) return fail('read_file needs a path.')
    const file = this.policy.resolveShared(raw)
    if (!file) return fail(this.outside(raw))
    const data = fs.readFileSync(file)
    const slice = data.subarray(0, 400_000)
    if (slice.includes(0)) return fail(`${path.basename(file)} isn't a text file.`)
    return { ok: true, summary: `Read ${path.basename(file)} (${data.length} bytes).`, data: { content: slice.toString('utf8'), path: file, bytes: data.length } }
  }

  private writeFile(command: DeviceCommand): ExecutionResult {
    const raw = str(command, 'path')
    if (!raw) return fail('write_file needs a path.')
    const file = this.policy.resolveShared(raw)
    if (!file) return fail(this.outside(raw))
    const content = str(command, 'content') ?? ''
    fs.mkdirSync(path.dirname(file), { recursive: true })
    const tmp = `${file}.syph-tmp`
    fs.writeFileSync(tmp, content, 'utf8')
    fs.renameSync(tmp, file)
    return { ok: true, summary: `Saved ${path.basename(file)}.`, data: { path: file, bytes: Buffer.byteLength(content) } }
  }

  private async trashFile(command: DeviceCommand): Promise<ExecutionResult> {
    const raw = str(command, 'path')
    if (!raw) return fail('trash_file needs a path.')
    const file = this.policy.resolveShared(raw)
    if (!file) return fail(this.outside(raw))
    if (this.policy.state.sharedFolders.some((f) => path.resolve(f).toLowerCase() === file.toLowerCase())) {
      return fail('A shared folder itself can\'t be moved to the Recycle Bin.')
    }
    await shell.trashItem(file)
    return { ok: true, summary: `Moved ${path.basename(file)} to the Recycle Bin.` }
  }

  private async runShell(command: DeviceCommand): Promise<ExecutionResult> {
    const line = str(command, 'command')
    if (!line) return fail('run_shell needs a command.')
    const cwd = this.policy.state.sharedFolders.find((f) => fs.existsSync(f)) ?? process.env.USERPROFILE ?? 'C:\\'
    const out = await runCommand(line, cwd)
    const data = { stdout: out.stdout, stderr: out.stderr, exit_code: out.status, shell: 'powershell' }
    if (out.timedOut) return fail('Command timed out.', data)
    if (out.status !== 0) {
      const reason = out.stderr.trim().split(/\r?\n/)[0] || `exit ${out.status}`
      return fail(`Command failed: ${reason}`, data)
    }
    const first = out.stdout.trim().split(/\r?\n/)[0] ?? ''
    return { ok: true, summary: first ? `Command finished: ${first.slice(0, 120)}` : 'Command finished.', data }
  }
}
