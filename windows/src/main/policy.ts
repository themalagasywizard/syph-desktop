import { app } from 'electron'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { SCOPES, type PolicyState, type Scope, type ScopeMode } from '../shared/types'

/** Same defaults as the Mac: looking is allowed, acting asks first. */
export const DEFAULT_MODES: Record<Scope, ScopeMode> = {
  observe: 'allow', screen: 'allow', apps: 'allow', files_read: 'allow', clipboard: 'allow',
  control: 'ask', files_write: 'ask', shell: 'ask',
}

export function scopeFor(operation: string): Scope | null {
  switch (operation) {
    case 'observe': case 'notify': case 'list_windows': case 'list_apps': return 'observe'
    case 'read_screen': case 'read_ui': case 'read_text': return 'screen'
    case 'click': case 'click_text': case 'press': case 'type_text': case 'press_keys': case 'scroll':
    case 'set_value': case 'drag': case 'move': case 'window': return 'control'
    case 'open_app': case 'quit_app': case 'open_url': return 'apps'
    case 'list_files': case 'read_file': return 'files_read'
    case 'write_file': case 'trash_file': return 'files_write'
    case 'run_shell': return 'shell'
    case 'clipboard_read': case 'clipboard_write': return 'clipboard'
    default: return null
  }
}

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
