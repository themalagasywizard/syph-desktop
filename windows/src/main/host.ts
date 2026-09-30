import { app } from 'electron'
import { spawn, type ChildProcessWithoutNullStreams } from 'node:child_process'
import { EventEmitter } from 'node:events'
import fs from 'node:fs'
import path from 'node:path'

export class HostCallError extends Error {
  constructor(message: string, readonly code: string) { super(message) }
}

interface Pending { resolve: (value: any) => void; reject: (e: Error) => void; timer: NodeJS.Timeout; method: string }

/**
 * Client for SyphHost.exe, the long-lived native helper (windows/host). One
 * process answers JSON-line requests in order; it is started on first use and
 * restarted if it exits. Events (e.g. human_input) are re-emitted.
 */
export class HostClient extends EventEmitter {
  private child: ChildProcessWithoutNullStreams | null = null
  private ready: Promise<void> | null = null
  private pending = new Map<number, Pending>()
  private nextId = 1
  private buffer = ''
  private crashes: number[] = []
  version = ''

  exePath(): string | null {
    const candidates = [
      process.env.SYPH_HOST,
      app.isPackaged ? path.join(process.resourcesPath, 'host', 'SyphHost.exe') : '',
      path.join(app.getAppPath(), 'host', 'publish', 'SyphHost.exe'),
    ].filter(Boolean) as string[]
    return candidates.find((p) => fs.existsSync(p)) ?? null
  }

  /** True when the helper exists and has not been crashing repeatedly. */
  get available(): boolean {
    if (process.platform !== 'win32' || !this.exePath()) return false
    const recent = this.crashes.filter((t) => Date.now() - t < 60_000)
    return recent.length < 3
  }

  private start(): Promise<void> {
    if (this.ready) return this.ready
    const exe = this.exePath()
    if (!exe) return Promise.reject(new HostCallError('The Syph helper is missing from this install.', 'unavailable'))
    this.ready = new Promise<void>((resolve, reject) => {
      const child = spawn(exe, [], { windowsHide: true, env: { ...process.env, SYPH_APP_PID: String(process.pid) } })
      this.child = child
      this.buffer = ''
      // A single-file build unpacks itself on first launch, which can take a few seconds.
      const timer = setTimeout(() => { reject(new HostCallError('The Syph helper did not start.', 'unavailable')); child.kill() }, 20_000)
      child.stdout.setEncoding('utf8').on('data', (chunk: string) => {
        this.buffer += chunk
        let nl: number
        while ((nl = this.buffer.indexOf('\n')) >= 0) {
          const line = this.buffer.slice(0, nl).trim()
          this.buffer = this.buffer.slice(nl + 1)
          if (!line) continue
          let msg: any
          try { msg = JSON.parse(line) } catch { continue }
          if (msg.event === 'ready') { clearTimeout(timer); this.version = msg.data?.version ?? ''; resolve(); continue }
          if (msg.event) { this.emit(msg.event, msg.data); continue }
          const p = this.pending.get(msg.id)
          if (!p) continue
          this.pending.delete(msg.id)
          clearTimeout(p.timer)
          if (msg.ok) p.resolve(msg.result)
          else p.reject(new HostCallError(String(msg.error ?? 'The Syph helper failed.'), String(msg.code ?? 'failed')))
        }
      })
      child.stderr.setEncoding('utf8').on('data', (d: string) => { if (d.trim()) console.warn('[host]', d.trim().slice(0, 400)) })
      child.on('error', (e) => { clearTimeout(timer); reject(new HostCallError(`The Syph helper couldn't start: ${e.message}`, 'unavailable')) })
      child.on('exit', (code) => {
        clearTimeout(timer)
        if (this.child === child) { this.child = null; this.ready = null }
        if (code !== 0) this.crashes.push(Date.now())
        for (const [id, p] of this.pending) { clearTimeout(p.timer); p.reject(new HostCallError(`The Syph helper stopped during ${p.method}.`, 'external')); this.pending.delete(id) }
        reject(new HostCallError('The Syph helper exited.', 'unavailable'))
      })
    })
    this.ready.catch(() => { this.ready = null })
    return this.ready
  }

  /** Calls one host method. A call that overruns kills the helper (it answers in order) and fails. */
  async call<T = any>(method: string, params: Record<string, unknown> = {}, timeoutMs = 30_000): Promise<T> {
    await this.start()
    const child = this.child
    if (!child) throw new HostCallError('The Syph helper is not running.', 'unavailable')
    const id = this.nextId++
    return new Promise<T>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id)
        reject(new HostCallError(`${method} took too long.`, 'timeout'))
        child.kill()
      }, timeoutMs)
      this.pending.set(id, { resolve, reject, timer, method })
      child.stdin.write(JSON.stringify({ id, method, params }) + '\n')
    })
  }

  stop() {
    this.child?.kill()
    this.child = null
    this.ready = null
  }
}

export const host = new HostClient()
