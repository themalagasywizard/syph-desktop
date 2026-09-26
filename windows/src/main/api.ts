import { app, net, safeStorage } from 'electron'
import fs from 'node:fs'
import path from 'node:path'
import { randomUUID } from 'node:crypto'
import type { ApiResult } from '../shared/types'

export const DEFAULT_SERVER = 'https://srv1982864.hstgr.cloud'

/**
 * HTTP client for the Syph API. Requests run in the main process so the
 * session cookie never touches the renderer; it is kept encrypted at rest
 * with the OS keystore (DPAPI on Windows).
 */
class ApiClient {
  private cookies = new Map<string, string>()
  private _server = DEFAULT_SERVER
  private loaded = false

  private get file() { return path.join(app.getPath('userData'), 'session.bin') }
  private get settingsFile() { return path.join(app.getPath('userData'), 'settings.json') }

  private load() {
    if (this.loaded) return
    this.loaded = true
    try {
      const settings = JSON.parse(fs.readFileSync(this.settingsFile, 'utf8'))
      if (typeof settings.server === 'string' && settings.server) this._server = settings.server
    } catch { /* first run */ }
    try {
      const raw = fs.readFileSync(this.file)
      const text = safeStorage.isEncryptionAvailable() ? safeStorage.decryptString(raw) : raw.toString('utf8')
      for (const [k, v] of Object.entries(JSON.parse(text) as Record<string, string>)) this.cookies.set(k, v)
    } catch { /* no session */ }
  }

  private persist() {
    try {
      const text = JSON.stringify(Object.fromEntries(this.cookies))
      const data = safeStorage.isEncryptionAvailable() ? safeStorage.encryptString(text) : Buffer.from(text, 'utf8')
      fs.mkdirSync(path.dirname(this.file), { recursive: true })
      fs.writeFileSync(this.file, data)
    } catch { /* best effort */ }
  }

  get server() { this.load(); return this._server }

  set server(value: string) {
    this.load()
    this._server = value.trim().replace(/\/+$/, '') || DEFAULT_SERVER
    this.cookies.clear()
    this.persist()
    fs.mkdirSync(path.dirname(this.settingsFile), { recursive: true })
    fs.writeFileSync(this.settingsFile, JSON.stringify({ server: this._server }))
  }

  clearSession() { this.cookies.clear(); this.persist() }

  baseUrl(): URL {
    const url = new URL(this.server)
    const host = url.hostname.toLowerCase()
    const privateHost = ['localhost', '127.0.0.1'].includes(host) || host.endsWith('.ts.net') || host.startsWith('100.')
    if (url.protocol !== 'https:' && !(url.protocol === 'http:' && privateHost)) {
      throw new Error('The server address isn’t valid. Use an https:// address.')
    }
    return url
  }

  resolve(p: string): string {
    if (/^[a-z]+:\/\//i.test(p)) return p
    return new URL(p, this.baseUrl()).toString()
  }

  async request<T>(method: string, p: string, body?: unknown, opts: { idempotent?: boolean; timeout?: number } = {}): Promise<ApiResult<T>> {
    this.load()
    let url: string
    try { url = new URL(p, this.baseUrl()).toString() } catch (e) { return { ok: false, status: 0, error: (e as Error).message } }
    const headers: Record<string, string> = { 'Content-Type': 'application/json', Accept: 'application/json' }
    if (this.cookies.size) headers.Cookie = [...this.cookies].map(([k, v]) => `${k}=${v}`).join('; ')
    if (opts.idempotent) headers['Idempotency-Key'] = randomUUID()
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), (opts.timeout ?? 30) * 1000)
    try {
      const response = await net.fetch(url, {
        method, headers, body: body === undefined ? undefined : JSON.stringify(body), signal: controller.signal,
      })
      this.absorbCookies(response.headers)
      const text = await response.text()
      let data: unknown
      try { data = text ? JSON.parse(text) : undefined } catch { data = undefined }
      if (!response.ok) {
        const detail = data && typeof data === 'object' && 'detail' in data ? String((data as { detail: unknown }).detail) : ''
        return { ok: false, status: response.status, error: detail || `Syph returned HTTP ${response.status}.` }
      }
      return { ok: true, status: response.status, data: data as T }
    } catch (e) {
      const err = e as Error
      const message = err.name === 'AbortError' ? 'Syph didn’t respond in time.' : 'Syph couldn’t be reached. Check your connection.'
      return { ok: false, status: 0, error: message }
    } finally {
      clearTimeout(timer)
    }
  }

  private absorbCookies(headers: Headers) {
    const raw = typeof (headers as any).getSetCookie === 'function' ? (headers as any).getSetCookie() as string[] : (headers.get('set-cookie') ? [headers.get('set-cookie') as string] : [])
    let changed = false
    for (const line of raw) {
      const [pair, ...attrs] = line.split(';')
      const eq = pair.indexOf('=')
      if (eq < 0) continue
      const name = pair.slice(0, eq).trim()
      const value = pair.slice(eq + 1).trim()
      const expired = attrs.some((a) => /max-age=0/i.test(a) || /expires=thu, 01 jan 1970/i.test(a)) || value === ''
      if (expired) this.cookies.delete(name); else this.cookies.set(name, value)
      changed = true
    }
    if (changed) this.persist()
  }
}

export const api = new ApiClient()
