import { app } from 'electron'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { SCOPES, type PolicyState, type Scope, type ScopeMode } from '../shared/types'

/** Same defaults as the Mac: looking is allowed, acting asks first. */
export const DEFAULT_MODES: Record<Scope, ScopeMode> = {
  observe: 'allow', screen: 'allow', apps: 'allow', files_read: 'allow', clipboard: 'allow',
  control: 'ask', files_write: 'ask', shell: 'ask',
  browser: 'ask', office: 'ask', files_outside: 'ask',
}

export function scopeFor(operation: string): Scope | null {
  switch (operation) {
    case 'observe': case 'notify': case 'list_windows': case 'list_apps': return 'observe'
    case 'read_screen': case 'read_ui': case 'read_text': case 'snapshot': case 'wait_for': return 'screen'
    case 'click': case 'click_text': case 'press': case 'type_text': case 'press_keys': case 'scroll':
    case 'set_value': case 'drag': case 'move': case 'window': case 'act': return 'control'
    case 'open_app': case 'quit_app': case 'open_url': return 'apps'
    case 'list_files': case 'read_file': case 'find_files': return 'files_read'
    case 'browser_open': case 'browser_snapshot': case 'browser_read': case 'browser_click': case 'browser_type':
    case 'browser_select': case 'browser_check': case 'browser_keys': case 'browser_scroll': case 'browser_back':
    case 'browser_tab': case 'browser_wait': return 'browser'
    case 'excel_list': case 'excel_read': case 'excel_write': case 'excel_save': case 'word_read': case 'word_write':
    case 'word_save': case 'outlook_list': case 'outlook_read': case 'outlook_search': case 'outlook_draft': return 'office'
    case 'write_file': case 'trash_file': return 'files_write'
    case 'run_shell': return 'shell'
    case 'clipboard_read': case 'clipboard_write': return 'clipboard'
    default: return null
  }
}

/** Reading operations that may reach outside the shared folders, with the argument holding the path. */
const OUTSIDE_READS: Record<string, string> = { read_file: 'path', list_files: 'path', excel_read: 'path', word_read: 'path' }

/** The owner's local choices, persisted on this PC only. */
export class Policy {
  state: PolicyState
  onChange: (() => void) | null = null

  private get file() { return path.join(app.getPath('userData'), 'computer.json') }

  constructor() {
    const fallback: PolicyState = {
      controlEnabled: false,
      modes: { ...DEFAULT_MODES },
      sharedFolders: [path.join(os.homedir(), 'Documents', 'Syph')],
    }
    try {
      const saved = JSON.parse(fs.readFileSync(this.file, 'utf8')) as Partial<PolicyState>
      this.state = {
        controlEnabled: !!saved.controlEnabled,
        modes: { ...DEFAULT_MODES, ...(saved.modes ?? {}) },
        sharedFolders: saved.sharedFolders?.length ? saved.sharedFolders : fallback.sharedFolders,
      }
    } catch {
      this.state = fallback
    }
    for (const folder of this.state.sharedFolders) {
      try { fs.mkdirSync(folder, { recursive: true }) } catch { /* may be removable media */ }
    }
  }

  private save() {
    try {
      fs.mkdirSync(path.dirname(this.file), { recursive: true })
      fs.writeFileSync(this.file, JSON.stringify(this.state, null, 2))
    } catch { /* best effort */ }
    this.onChange?.()
  }

  /** The scope a command needs: reading outside the shared folders is its own, stricter scope. */
  scopeForCommand(operation: string, args: Record<string, unknown>): Scope | null {
    const base = scopeFor(operation)
    if (operation === 'find_files' && args.everywhere === true) return 'files_outside'
    const key = OUTSIDE_READS[operation]
    const raw = key ? args[key] : undefined
    if (typeof raw === 'string' && raw.trim() && !this.resolveShared(raw) && !this.isForbidden(raw)) return 'files_outside'
    return base
  }

  /** Places Syph never reads, whatever the owner allows: its own session, and credential and browser-secret stores. */
  isForbidden(raw: string): boolean {
    const p = path.resolve(raw.replace(/^~(?=$|[\\/])/, os.homedir())).toLowerCase()
    const own = app.getPath('userData').toLowerCase()
    const blocked = [own, '\\microsoft\\credentials', '\\microsoft\\protect', '\\microsoft\\crypto', '\\microsoft\\vault',
      'login data', 'cookies', 'web data', 'local state', '.kdbx', '\\.ssh', '\\windows\\system32\\config']
    return blocked.some((b) => p.includes(b))
  }

  /** A readable path: inside the shared folders, or anywhere not forbidden when outside reads were allowed. */
  resolveReadable(raw: unknown, outsideAllowed: boolean): string | null {
    const shared = this.resolveShared(raw)
    if (shared) return shared
    if (!outsideAllowed || typeof raw !== 'string' || this.isForbidden(raw)) return null
    const p = path.resolve(raw.trim().replace(/^~(?=$|[\\/])/, os.homedir()))
    try { return fs.realpathSync.native(p) } catch { return null }
  }

  mode(scope: Scope): ScopeMode { return this.state.modes[scope] ?? DEFAULT_MODES[scope] }
  setMode(scope: Scope, mode: ScopeMode) { if (SCOPES.includes(scope)) { this.state.modes[scope] = mode; this.save() } }
  resetModes() { this.state.modes = { ...DEFAULT_MODES }; this.save() }
  setEnabled(on: boolean) { this.state.controlEnabled = on; this.save() }

  addFolder(folder: string) {
    const resolved = path.resolve(folder)
    if (!this.state.sharedFolders.some((f) => path.resolve(f).toLowerCase() === resolved.toLowerCase())) {
      this.state.sharedFolders.push(resolved); this.save()
    }
  }

  removeFolder(folder: string) {
    this.state.sharedFolders = this.state.sharedFolders.filter((f) => f !== folder); this.save()
  }

  /** The wire form reported to the server. AppleScript's scope is off: it is Mac-only. */
  wireScopes(): Record<string, string> {
    return { ...Object.fromEntries(SCOPES.map((s) => [s, this.mode(s)])), automation: 'off' }
  }

  /** Resolves a path the agent gave; returns it only if it sits inside a shared folder. */
  resolveShared(raw: unknown): string | null {
    if (typeof raw !== 'string' || !raw.trim()) return null
    let p = raw.trim().replace(/^~(?=$|[\\/])/, os.homedir())
    if (!path.isAbsolute(p)) {
      const first = this.state.sharedFolders[0]
      if (!first) return null
      p = path.join(first, p)
    }
    const real = realpathLoose(path.resolve(p))
    for (const folder of this.state.sharedFolders) {
      const root = realpathLoose(path.resolve(folder))
      const a = real.toLowerCase(), b = root.toLowerCase()
      if (a === b || a.startsWith(b.endsWith(path.sep) ? b : b + path.sep)) return real
    }
    return null
  }
}

/** realpath for paths that may not exist yet: resolve the deepest existing parent. */
function realpathLoose(p: string): string {
  let current = p
  const tail: string[] = []
  while (true) {
    try { return path.join(fs.realpathSync.native(current), ...tail) } catch {
      const parent = path.dirname(current)
      if (parent === current) return p
      tail.unshift(path.basename(current))
      current = parent
    }
  }
}
