import { app } from 'electron'
import { spawn } from 'node:child_process'
import path from 'node:path'

export interface ScriptResult { ok: boolean; summary: string; data?: Record<string, unknown> }

function scriptsDir() {
  return app.isPackaged ? path.join(process.resourcesPath, 'ps') : path.join(app.getAppPath(), 'resources', 'ps')
}

const POWERSHELL = path.join(process.env.SystemRoot ?? 'C:\\Windows', 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe')

/** Runs one bundled Windows PowerShell 5.1 script; it prints a single JSON line. */
export function runScript(name: string, args: Record<string, unknown>, timeoutMs = 60_000): Promise<ScriptResult> {
  return new Promise((resolve) => {
    const child = spawn(POWERSHELL, ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', path.join(scriptsDir(), `${name}.ps1`)], {
      env: { ...process.env, SYPH_ARGS: JSON.stringify(args) },
      windowsHide: true,
    })
    let out = ''
    let err = ''
    child.stdout.setEncoding('utf8').on('data', (d) => { out += d })
    child.stderr.setEncoding('utf8').on('data', (d) => { err += d })
    const timer = setTimeout(() => { child.kill(); resolve({ ok: false, summary: `${name} timed out.` }) }, timeoutMs)
    child.on('error', (e) => { clearTimeout(timer); resolve({ ok: false, summary: `PowerShell couldn't start: ${e.message}` }) })
    child.on('close', () => {
      clearTimeout(timer)
      const line = out.trim().split(/\r?\n/).filter(Boolean).pop()
      try {
        resolve(JSON.parse(line ?? '') as ScriptResult)
      } catch {
        resolve({ ok: false, summary: (err.trim().split(/\r?\n/)[0] || `${name} returned nothing.`).slice(0, 300) })
      }
    })
  })
}

export interface ShellOutput { stdout: string; stderr: string; status: number; timedOut: boolean }

/** A user command in PowerShell, run from the first shared folder. */
export function runCommand(command: string, cwd: string, timeoutMs = 120_000): Promise<ShellOutput> {
  return new Promise((resolve) => {
    const prefix = '[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $ProgressPreference = "SilentlyContinue"; '
    const child = spawn(POWERSHELL, ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', prefix + command], {
      cwd, windowsHide: true,
    })
    let stdout = ''
    let stderr = ''
    let timedOut = false
    child.stdout.setEncoding('utf8').on('data', (d) => { if (stdout.length < 60_000) stdout += d })
    child.stderr.setEncoding('utf8').on('data', (d) => { if (stderr.length < 60_000) stderr += d })
    const timer = setTimeout(() => { timedOut = true; child.kill() }, timeoutMs)
    child.on('error', (e) => { clearTimeout(timer); resolve({ stdout, stderr: e.message, status: -1, timedOut }) })
    child.on('close', (code) => { clearTimeout(timer); resolve({ stdout, stderr, status: code ?? -1, timedOut }) })
  })
}

const END = /<<<SYPH-END (\S*)>>>\r?$/m

/**
 * One long-lived PowerShell where variables, the current folder and imported
 * modules carry over between commands (run_shell with session: true). Each
 * command is sent base64-encoded on one line and dot-sourced, so multi-line
 * scripts work; a sentinel line marks its end.
 */
export class ShellSession {
  private child: ReturnType<typeof spawn> | null = null
  private out = ''
  private waiter: ((text: string, code: string) => void) | null = null
  private queue: Promise<unknown> = Promise.resolve()

  private start(cwd: string) {
    const child = spawn(POWERSHELL, ['-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', '-'], { cwd, windowsHide: true })
    child.stdout!.setEncoding('utf8').on('data', (d: string) => {
      this.out += d
      const m = this.out.match(END)
      if (m && this.waiter) {
        const text = this.out.slice(0, m.index)
        this.out = this.out.slice((m.index ?? 0) + m[0].length)
        const w = this.waiter
        this.waiter = null
        w(text, m[1])
      }
    })
    child.stderr!.setEncoding('utf8').on('data', (d: string) => { this.out += d })
    child.on('exit', () => { if (this.child === child) this.child = null })
    child.stdin!.write('[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $ProgressPreference = "SilentlyContinue"\n')
    this.child = child
  }

  run(command: string, cwd: string, timeoutMs = 120_000): Promise<ShellOutput> {
    const next = this.queue.then(() => new Promise<ShellOutput>((resolve) => {
      if (!this.child) this.start(cwd)
      const child = this.child!
      const timer = setTimeout(() => {
        this.waiter = null
        child.kill()
        this.child = null
        resolve({ stdout: this.out.slice(-60_000), stderr: 'The shell session was restarted after the command timed out.', status: -1, timedOut: true })
        this.out = ''
      }, timeoutMs)
      this.waiter = (text, code) => {
        clearTimeout(timer)
        const status = code === 'False' ? 1 : /^-?\d+$/.test(code) ? Number(code) : 0
        resolve({ stdout: text.slice(-60_000), stderr: '', status, timedOut: false })
      }
      const b64 = Buffer.from(command, 'utf8').toString('base64')
      child.stdin!.write(
        `try { . ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${b64}')))) 2>&1 | Out-String -Width 220 } ` +
        `catch { $_ | Out-String -Width 220 }; $__ok = $?; "<<<SYPH-END $(if ($LASTEXITCODE) { $LASTEXITCODE } else { $__ok })>>>"\n`)
    }))
    this.queue = next.catch(() => {})
    return next
  }

  stop() { this.child?.kill(); this.child = null }
}
