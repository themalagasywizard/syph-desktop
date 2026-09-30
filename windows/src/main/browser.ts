import { app } from 'electron'
import fs from 'node:fs'
import path from 'node:path'
import type { BrowserContext, Download, Page } from 'playwright-core'
import type { ScriptResult } from './powershell'

type Result = ScriptResult
const fail = (summary: string, data?: Record<string, unknown>): Result => ({ ok: false, summary, data })

/**
 * Collects the page's interactive elements, gives each a stable data-syph-ref,
 * and returns them with the visible text. Runs inside the page.
 */
const SNAPSHOT_SCRIPT = `(() => {
  const w = window; w.__syphNext = w.__syphNext || 1;
  const sel = 'a[href],button,input:not([type=hidden]),select,textarea,summary,[role=button],[role=link],[role=checkbox],[role=radio],[role=tab],[role=menuitem],[role=option],[role=switch],[role=combobox],[role=textbox],[role=searchbox],[contenteditable=""],[contenteditable=true],[onclick],[tabindex]:not([tabindex="-1"])';
  const clean = (s) => String(s || '').replace(/\\s+/g, ' ').trim();
  const out = [];
  for (const el of document.querySelectorAll(sel)) {
    const r = el.getBoundingClientRect();
    if (r.width < 2 || r.height < 2) continue;
    const st = getComputedStyle(el);
    if (st.visibility === 'hidden' || st.display === 'none' || Number(st.opacity) === 0) continue;
    let ref = el.getAttribute('data-syph-ref');
    if (!ref) { ref = String(w.__syphNext++); el.setAttribute('data-syph-ref', ref); }
    const tag = el.tagName.toLowerCase();
    const type = (el.getAttribute('type') || '').toLowerCase();
    const role = el.getAttribute('role') || (tag === 'a' ? 'link' : tag === 'input' ? (type || 'text') : tag);
    const label = el.labels && el.labels[0] ? el.labels[0].innerText : '';
    const name = clean(el.getAttribute('aria-label') || label || el.getAttribute('placeholder') || el.innerText || el.getAttribute('title') || el.getAttribute('alt') || el.getAttribute('name')).slice(0, 120);
    const secret = type === 'password' || /card|cvc|cvv|iban|otp|one-time/i.test(el.getAttribute('autocomplete') || '');
    const item = { ref: Number(ref), role, name };
    if ((tag === 'input' || tag === 'textarea' || tag === 'select') && !secret) item.value = clean(el.value).slice(0, 200);
    if (secret) item.secret = true;
    if (el.checked) item.checked = true;
    if (el.disabled) item.disabled = true;
    if (tag === 'a' && el.href) item.href = el.href.slice(0, 200);
    if (tag === 'select') item.options = Array.from(el.options).slice(0, 30).map((o) => clean(o.text));
    const inView = r.bottom > 0 && r.right > 0 && r.top < innerHeight && r.left < innerWidth;
    if (!inView) item.offscreen = true;
    item.box = [Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height)];
    out.push(item);
    if (out.length >= 400) break;
  }
  const text = clean(document.body ? document.body.innerText : '');
  return { title: document.title, url: location.href, elements: out, text,
           scroll: { y: Math.round(scrollY), height: document.documentElement.scrollHeight, viewport: innerHeight } };
})()`

/** Numbered boxes over in-view elements and black boxes over secrets, for the screenshot only. */
const MARKS_SCRIPT = `((items) => {
  const layer = document.createElement('div');
  layer.id = '__syph_marks';
  layer.style.cssText = 'position:fixed;inset:0;pointer-events:none;z-index:2147483647';
  const colors = ['#007aff', '#ff2d55', '#34c759', '#ff9500', '#af52de', '#00aaaa'];
  items.forEach((it, i) => {
    const [x, y, w, h] = it.box;
    const box = document.createElement('div');
    const c = colors[i % colors.length];
    box.style.cssText = 'position:fixed;left:' + x + 'px;top:' + y + 'px;width:' + w + 'px;height:' + h + 'px;' +
      (it.secret ? 'background:#000;' : 'outline:1.5px solid ' + c + ';');
    if (!it.secret) {
      const tag = document.createElement('span');
      tag.textContent = it.ref;
      tag.style.cssText = 'position:absolute;left:0;top:-14px;background:' + c + ';color:#fff;font:bold 11px/14px Segoe UI,Arial;padding:0 3px;border-radius:2px';
      box.appendChild(tag);
    }
    layer.appendChild(box);
  });
  document.documentElement.appendChild(layer);
})`

/**
 * The agent's own browser: a separate Edge (or Chrome) profile the owner signs
 * into once, driven through the DevTools protocol. Pages are read and acted on
 * through the DOM — far more reliable than pixels — while the window stays
 * visible so the owner can watch. Downloads land in the first shared folder.
 */
export class SyphBrowser {
  private context: BrowserContext | null = null
  private current: Page | null = null
  private downloads: Array<{ file: string; url: string }> = []

  constructor(private downloadsDir: () => string | null) {}

  private profileDir() { return path.join(app.getPath('userData'), 'browser-profile') }

  private async launch(): Promise<BrowserContext> {
    const { chromium } = await import('playwright-core')
    const tries: Array<'msedge' | 'chrome'> = ['msedge', 'chrome']
    let lastError: unknown
    for (const channel of tries) {
      try {
        const ctx = await chromium.launchPersistentContext(this.profileDir(), {
          channel, headless: false, viewport: null, acceptDownloads: true,
          args: ['--start-maximized', '--no-first-run', '--no-default-browser-check'],
        })
        ctx.on('close', () => { if (this.context === ctx) { this.context = null; this.current = null } })
        ctx.on('page', (p) => { this.current = p; this.watch(p) })
        for (const p of ctx.pages()) this.watch(p)
        return ctx
      } catch (e) { lastError = e }
    }
    throw new Error(`Couldn't start Edge or Chrome for Syph's browser (${(lastError as Error)?.message?.split('\n')[0] ?? 'not installed'}).`)
  }

  private watch(p: Page) {
    p.on('download', (d: Download) => void this.saveDownload(d))
  }

  private async saveDownload(d: Download) {
    const dir = this.downloadsDir()
    if (!dir) { await d.cancel(); return }
    const target = path.join(dir, 'Downloads', d.suggestedFilename().replace(/[\\/:*?"<>|]/g, '_'))
    fs.mkdirSync(path.dirname(target), { recursive: true })
    await d.saveAs(target)
    this.downloads.push({ file: target, url: d.url() })
  }

  private async page(): Promise<Page> {
    if (!this.context) this.context = await this.launch()
    if (this.current && !this.current.isClosed()) return this.current
    const pages = this.context.pages()
    this.current = pages[pages.length - 1] ?? await this.context.newPage()
    return this.current
  }

  private async settle(p: Page) {
    try { await p.waitForLoadState('domcontentloaded', { timeout: 10_000 }) } catch { /* slow page: look anyway */ }
    try { await p.waitForLoadState('networkidle', { timeout: 2_500 }) } catch { /* long-polling sites never idle */ }
  }

  /** The page as the agent sees it: numbered controls, text, and a marked screenshot. */
  async snapshot(opts: { image?: boolean; textLimit?: number } = {}): Promise<Result> {
    const p = await this.page()
    await this.settle(p)
    const view = await p.evaluate(SNAPSHOT_SCRIPT) as any
    let image: string | undefined
    if (opts.image !== false) {
      const inView = view.elements.filter((e: any) => !e.offscreen)
      await p.evaluate(`${MARKS_SCRIPT}(${JSON.stringify(inView)})`).catch(() => {})
      try {
        image = (await p.screenshot({ type: 'jpeg', quality: 70, scale: 'css', timeout: 10_000 })).toString('base64')
      } finally {
        await p.evaluate(`document.getElementById('__syph_marks')?.remove()`).catch(() => {})
      }
    }
    const tabs = this.context!.pages().map((t, i) => ({ index: i, title: '', url: t.url(), active: t === p }))
    for (const t of tabs) { try { t.title = await this.context!.pages()[t.index].title() } catch { /* closing */ } }
    const limit = opts.textLimit ?? 8_000
    const elements = view.elements.map(({ box, ...rest }: any) => rest)
    const recent = this.downloads.splice(0)
    return {
      ok: true,
      summary: `${view.title || view.url}: ${elements.length} numbered elements${recent.length ? `; downloaded ${recent.map((d) => path.basename(d.file)).join(', ')}` : ''}.`,
      data: {
        title: view.title, url: view.url, tabs, elements,
        text: view.text.length > limit ? view.text.slice(0, limit) + '…' : view.text, text_length: view.text.length,
        scroll: view.scroll, downloads: recent.length ? recent : undefined,
        ...(image ? { _image: image } : {}),
      },
    }
  }

  private locator(p: Page, ref: unknown) {
    const n = Number(ref)
    if (!Number.isInteger(n) || n <= 0) throw new Error('Give the element ref number from browser_snapshot.')
    return p.locator(`[data-syph-ref="${n}"]`).first()
  }

  private async afterAction(summary: string): Promise<Result> {
    const shot = await this.snapshot()
    return { ok: true, summary: `${summary} Now: ${shot.summary}`, data: shot.data }
  }

  async run(op: string, a: Record<string, unknown>): Promise<Result> {
    try {
      switch (op) {
        case 'browser_open': {
          const raw = String(a.url ?? '').trim()
          if (!raw) return fail('browser_open needs a url.')
          const url = new URL(/^[a-z]+:/i.test(raw) ? raw : `https://${raw}`)
          if (!['http:', 'https:'].includes(url.protocol)) return fail('Syph’s browser only opens web pages (http and https).')
          const p = a.new_tab ? await (await this.page(), this.context!.newPage()) : await this.page()
          this.current = p
          await p.goto(url.toString(), { waitUntil: 'domcontentloaded', timeout: 45_000 })
          await p.bringToFront()
          return await this.afterAction(`Opened ${url.hostname}.`)
        }
        case 'browser_snapshot': return await this.snapshot()
        case 'browser_read': {
          const shot = await this.snapshot({ image: false, textLimit: Math.min(Number(a.limit ?? 60_000), 100_000) })
          const { elements, ...rest } = shot.data as any
          return { ok: true, summary: `Read ${rest.text_length} characters from ${rest.title || rest.url}.`, data: { ...rest, content: rest.text, text: undefined } }
        }
        case 'browser_click': {
          const p = await this.page()
          if (a.ref !== undefined) await this.locator(p, a.ref).click({ timeout: 10_000 })
          else if (a.text) await p.getByText(String(a.text), { exact: false }).first().click({ timeout: 10_000 })
          else return fail('browser_click needs a ref (or text).')
          return await this.afterAction(`Clicked ${a.ref !== undefined ? `#${a.ref}` : `‘${a.text}’`}.`)
        }
        case 'browser_type': {
          const p = await this.page()
          const el = this.locator(p, a.ref)
          const text = String(a.text ?? '')
          if (a.append) await el.pressSequentially(text, { delay: 10 })
          else await el.fill(text, { timeout: 10_000 })
          if (a.submit) await el.press('Enter')
          return await this.afterAction(`Typed into #${a.ref}${a.submit ? ' and submitted' : ''}.`)
        }
        case 'browser_select': {
          const p = await this.page()
          const el = this.locator(p, a.ref)
          const value = String(a.value ?? a.text ?? '')
          try { await el.selectOption({ label: value }, { timeout: 5_000 }) } catch { await el.selectOption(value, { timeout: 5_000 }) }
          return await this.afterAction(`Chose ‘${value}’ in #${a.ref}.`)
        }
        case 'browser_check': {
          const p = await this.page()
          const el = this.locator(p, a.ref)
          if (a.checked === false) await el.uncheck({ timeout: 10_000 }); else await el.check({ timeout: 10_000 })
          return await this.afterAction(`${a.checked === false ? 'Unticked' : 'Ticked'} #${a.ref}.`)
        }
        case 'browser_keys': {
          const p = await this.page()
          const keys = String(a.keys ?? '').split(/[\s,]+/).filter(Boolean)
          for (const k of keys) await p.keyboard.press(k.split('+').map((x) => ({ ctrl: 'Control', cmd: 'Control', alt: 'Alt', shift: 'Shift', enter: 'Enter', esc: 'Escape', tab: 'Tab' }[x.toLowerCase()] ?? (x.length === 1 ? x : x[0].toUpperCase() + x.slice(1)))).join('+'))
          return await this.afterAction(`Pressed ${keys.join(', ')}.`)
        }
        case 'browser_scroll': {
          const p = await this.page()
          if (a.ref !== undefined) await this.locator(p, a.ref).scrollIntoViewIfNeeded({ timeout: 5_000 })
          else {
            const dir = String(a.direction ?? 'down')
            const pages = Number(a.amount ?? 1)
            await p.evaluate(`window.scrollBy(0, ${(dir === 'up' ? -1 : 1) * pages} * innerHeight * 0.85)`)
          }
          return await this.afterAction('Scrolled.')
        }
        case 'browser_back': {
          const p = await this.page()
          await p.goBack({ timeout: 15_000 })
          return await this.afterAction('Went back.')
        }
        case 'browser_tab': {
          const ctx = this.context ?? (await this.page(), this.context!)
          const pages = ctx.pages()
          const i = Number(a.index)
          if (!Number.isInteger(i) || !pages[i]) return fail(`There is no tab ${a.index}; browser_snapshot lists tabs.`)
          if (a.close) { await pages[i].close(); this.current = null; return await this.afterAction(`Closed tab ${i}.`) }
          this.current = pages[i]
          await pages[i].bringToFront()
          return await this.afterAction(`Switched to tab ${i}.`)
        }
        case 'browser_wait': {
          const p = await this.page()
          const timeout = Math.min(60, Number(a.timeout ?? 15)) * 1000
          if (a.text) await p.getByText(String(a.text), { exact: false }).first().waitFor({ timeout })
          else await p.waitForLoadState('networkidle', { timeout })
          return await this.afterAction(a.text ? `‘${a.text}’ appeared.` : 'The page settled.')
        }
        default: return fail(`Unknown browser operation ${op}.`)
      }
    } catch (e) {
      const message = (e as Error).message.split('\n')[0]
      return fail(/data-syph-ref/.test(message) ? `That element is gone or hidden (${message.slice(0, 160)}). Take browser_snapshot for fresh refs.` : message.slice(0, 400))
    }
  }

  async close() {
    const ctx = this.context
    this.context = null
    this.current = null
    await ctx?.close().catch(() => {})
  }
}
