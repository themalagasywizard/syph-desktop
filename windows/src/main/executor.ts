import { clipboard, shell } from 'electron'
import fs from 'node:fs'
import path from 'node:path'
import type { DeviceCommand } from '../shared/types'
import type { Policy } from './policy'
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

/**
 * Performs computer commands on this PC. Scope and consent are checked by the
 * bridge before anything here runs; file paths are re-checked here against
 * the shared folders on every call.
 */
export class Executor {
  constructor(private policy: Policy) {}

  async run(command: DeviceCommand): Promise<ExecutionResult> {
    try {
      switch (command.operation) {
        case 'observe': return await runScript('observe', {})
        case 'read_screen': return await runScript('screen', { thumbnail: true }, 90_000)
        case 'read_ui': return await runScript('ui', {})
        case 'press': {
          const title = str(command, 'title') ?? str(command, 'text')
          return title ? await runScript('ui', { press: title, limit: 600 }) : fail('press needs a title.')
        }
        case 'click': {
          const x = num(command, 'x'), y = num(command, 'y')
          if (x === undefined || y === undefined) return fail('click needs x and y.')
          return await runScript('input', { mode: 'click', x, y, button: str(command, 'button') ?? 'left', count: num(command, 'count') ?? 1 })
        }
        case 'click_text': return await this.clickText(command)
        case 'type_text': {
          const text = str(command, 'text')
          return text ? await runScript('input', { mode: 'type', text }) : fail('type_text needs text.')
        }
        case 'press_keys': {
          const keys = str(command, 'keys')
          return keys ? await runScript('input', { mode: 'keys', keys }) : fail('press_keys needs keys, like ctrl+s.')
        }
        case 'scroll': return await runScript('input', { mode: 'scroll', direction: str(command, 'direction') ?? 'down', amount: num(command, 'amount') ?? 5 })
        case 'open_app': {
          const app = str(command, 'app')
          return app ? await runScript('apps', { mode: 'open', app }) : fail('open_app needs an app name.')
        }
        case 'quit_app': {
          const app = str(command, 'app')
          return app ? await runScript('apps', { mode: 'quit', app }) : fail('quit_app needs an app name.')
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

  private async clickText(command: DeviceCommand): Promise<ExecutionResult> {
    const query = str(command, 'text')
    if (!query) return fail('click_text needs text.')
    const reading = await runScript('screen', { thumbnail: false }, 90_000)
    if (!reading.ok) return reading
    const lines = ((reading.data?.lines as Array<{ text: string; x: number; y: number; w: number; left: number }>) ?? [])
    const needle = query.toLowerCase().trim()
    const exact = lines.find((l) => l.text.toLowerCase().trim() === needle)
    const line = exact ?? lines.filter((l) => l.text.toLowerCase().includes(needle)).sort((a, b) => a.text.length - b.text.length)[0]
    if (!line) {
      return fail(`'${query}' isn't visible on screen.`, { visible: lines.slice(0, 30).map((l) => l.text).join(' · ') })
    }
    // Aim at the matched words inside the line, by character offset.
    const at = line.text.toLowerCase().indexOf(needle)
    const perChar = line.w / Math.max(1, line.text.length)
    const x = at >= 0 ? Math.round(line.left + (at + needle.length / 2) * perChar) : line.x
    const clicked = await runScript('input', { mode: 'click', x, y: line.y, count: num(command, 'count') ?? 1 })
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
