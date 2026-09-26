import {
  app, BrowserWindow, dialog, globalShortcut, ipcMain, Menu, nativeImage, Notification, screen, shell, Tray,
} from 'electron'
import path from 'node:path'
import type { ConsentDecision, ConsentRequest, LaunchOptions, OverlayState } from '../shared/types'
import { api } from './api'
import { DeviceBridge } from './bridge'

const isDev = !app.isPackaged && process.env.SYPH_DEV === '1'
const argv = process.argv.join(' ')
const flag = (name: string) => new RegExp(`--${name}(=|\\s|$)`).test(argv)
const value = (name: string) => argv.match(new RegExp(`--${name}=([^\\s]+)`))?.[1]

const launch: Omit<LaunchOptions, 'surface'> = {
  demo: flag('demo'),
  section: value('section'),
  demoConsent: flag('demo-consent'),
}
// Automation hook for the end-to-end CI job: --server=… --email=… --password=…
const automation = { server: value('server'), email: value('email'), password: value('password') }

if (!app.requestSingleInstanceLock() && !launch.demo) app.quit()
app.setAppUserModelId('com.syph.desktop')

let main: BrowserWindow | null = null
let commandBar: BrowserWindow | null = null
let consentWin: BrowserWindow | null = null
let glowWin: BrowserWindow | null = null
let pillWin: BrowserWindow | null = null
let tray: Tray | null = null
let waitingCount = 0
let quitting = false

const assets = () => path.join(app.getAppPath(), 'dist', 'renderer')
const iconPath = () => path.join(assets(), 'icon.png')

function load(win: BrowserWindow, surface: string) {
  const query = `surface=${surface}`
  if (isDev) void win.loadURL(`http://localhost:5173/?${query}`)
  else void win.loadFile(path.join(assets(), 'index.html'), { search: query })
}

function surfaceWindow(opts: Electron.BrowserWindowConstructorOptions, surface: string) {
  const win = new BrowserWindow({
    show: false, frame: false, transparent: true, resizable: false, skipTaskbar: true, hasShadow: false,
    alwaysOnTop: true, focusable: true, backgroundColor: '#00000000',
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, sandbox: false },
    ...opts,
  })
  win.setAlwaysOnTop(true, 'screen-saver')
  win.setVisibleOnAllWorkspaces(true)
  load(win, surface)
  return win
}

function send(channel: string, payload?: unknown) {
  for (const win of BrowserWindow.getAllWindows()) if (!win.isDestroyed()) win.webContents.send(`syph:${channel}`, payload)
}

// ---------------------------------------------------------------- consent + overlay

let pendingConsent: { request: ConsentRequest; resolve: (d: ConsentDecision) => void; timer: NodeJS.Timeout } | null = null
let overlay: OverlayState = { visible: false, employee: '', activity: '', tint: 'hsl(224 100% 81%)' }
let hideTimer: NodeJS.Timeout | null = null

function askConsent(request: ConsentRequest): Promise<ConsentDecision> {
  if (pendingConsent) return Promise.resolve('deny')
  return new Promise((resolve) => {
    const timer = setTimeout(() => decideConsent(request.id, 'deny'), request.deadline - Date.now())
    pendingConsent = { request, resolve, timer }
    const area = screen.getPrimaryDisplay().workArea
    const size = { width: 460, height: 400 }
    if (!consentWin || consentWin.isDestroyed()) consentWin = surfaceWindow({ ...size }, 'consent')
    consentWin.setBounds({ x: area.x + area.width - size.width - 12, y: area.y + 70, ...size })
    const show = () => { consentWin?.showInactive(); send('consent', request); shell.beep() }
    if (consentWin.webContents.isLoading()) consentWin.webContents.once('did-finish-load', show); else show()
  })
}

function decideConsent(id: string, decision: ConsentDecision) {
  if (!pendingConsent || pendingConsent.request.id !== id) return
  clearTimeout(pendingConsent.timer)
  const { resolve } = pendingConsent
  pendingConsent = null
  send('consent', null)
  consentWin?.hide()
  resolve(decision)
}

function showOverlay(employee: string, activity: string, tint: string) {
  if (hideTimer) { clearTimeout(hideTimer); hideTimer = null }
  overlay = { visible: true, employee: employee || 'Your employee', activity, tint }
  const display = screen.getPrimaryDisplay()
  if (!glowWin || glowWin.isDestroyed()) {
    glowWin = surfaceWindow({ focusable: false }, 'glow')
    glowWin.setIgnoreMouseEvents(true)
  }
  if (!pillWin || pillWin.isDestroyed()) pillWin = surfaceWindow({ width: 540, height: 72, focusable: false }, 'pill')
  glowWin.setBounds(display.bounds)
  pillWin.setBounds({ x: Math.round(display.workArea.x + display.workArea.width / 2 - 270), y: display.workArea.y + 6, width: 540, height: 72 })
  const reveal = (win: BrowserWindow) => {
    const go = () => { win.showInactive(); send('overlay', overlay) }
    if (win.webContents.isLoading()) win.webContents.once('did-finish-load', go); else go()
  }
  reveal(glowWin); reveal(pillWin)
}

function hideOverlay(delayMs: number) {
  if (hideTimer) clearTimeout(hideTimer)
  hideTimer = setTimeout(() => {
    overlay = { ...overlay, visible: false }
    send('overlay', overlay)
    setTimeout(() => { if (!overlay.visible) { glowWin?.hide(); pillWin?.hide() } }, 450)
  }, delayMs)
}

const bridge = new DeviceBridge({
  broadcast: (state) => { send('bridge', state); refreshTray() },
  askConsent,
  cancelConsent: () => { if (pendingConsent) decideConsent(pendingConsent.request.id, 'deny') },
  showOverlay,
  hideOverlay,
})

// ---------------------------------------------------------------- windows

function createMain() {
  main = new BrowserWindow({
    width: 1320, height: 840, minWidth: 1040, minHeight: 660, show: false,
    frame: false, backgroundColor: '#050507', title: 'Syph', icon: iconPath(),
    backgroundMaterial: 'mica',
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, sandbox: false },
  })
  load(main, 'main')
  main.once('ready-to-show', () => main?.show())
  main.on('close', (e) => {
    // Closing keeps Syph in the tray so employees can still reach this PC.
    if (!quitting && !launch.demo) { e.preventDefault(); main?.hide() }
  })
  main.webContents.setWindowOpenHandler(({ url }) => { void shell.openExternal(url); return { action: 'deny' } })
}

function showMain(section?: string) {
  if (!main || main.isDestroyed()) createMain()
  main!.show(); main!.focus()
  if (section) send('navigate', section)
}

function toggleCommandBar() {
  if (commandBar && !commandBar.isDestroyed() && commandBar.isVisible()) { commandBar.hide(); return }
  const area = screen.getDisplayNearestPoint(screen.getCursorScreenPoint()).workArea
  const size = { width: 700, height: 440 }
  if (!commandBar || commandBar.isDestroyed()) {
    commandBar = surfaceWindow({ ...size, skipTaskbar: true }, 'commandbar')
    commandBar.on('blur', () => commandBar?.hide())
  }
  commandBar.setBounds({ x: Math.round(area.x + area.width / 2 - size.width / 2), y: Math.round(area.y + area.height * 0.16), ...size })
  const go = () => { commandBar?.show(); commandBar?.focus(); send('commandbar-opened') }
  if (commandBar.webContents.isLoading()) commandBar.webContents.once('did-finish-load', go); else go()
}

function refreshTray() {
  if (!tray) return
  const state = bridge.state()
  const on = state.policy.controlEnabled
  tray.setToolTip(`Syph — ${waitingCount ? `${waitingCount} waiting on you` : 'all clear'}${state.current ? ` · ${state.current.employee} is working here` : ''}`)
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: 'Open Syph', click: () => showMain() },
    { label: 'Command bar\tAlt+Space', click: toggleCommandBar },
    { label: waitingCount ? `Needs you (${waitingCount})` : 'Needs you', click: () => showMain('approvals') },
    { type: 'separator' },
    { label: 'Computer control', type: 'checkbox', checked: on, click: () => (on ? bridge.emergencyStop() : bridge.policy.setEnabled(true)) },
    { label: 'This PC…', click: () => showMain('computer') },
    { type: 'separator' },
    { label: 'Quit Syph', click: () => { quitting = true; app.quit() } },
  ]))
}

// ---------------------------------------------------------------- IPC

function handle(channel: string, fn: (...args: any[]) => unknown) {
  ipcMain.handle(`syph:${channel}`, (event, ...args) => fn(event, ...args))
}

handle('launch', (event) => {
  const url = new URL(event.sender.getURL())
  return { ...launch, surface: url.searchParams.get('surface') ?? 'main' } satisfies LaunchOptions
})
handle('api', (_e, method: string, p: string, body?: unknown, opts?: { idempotent?: boolean; timeout?: number }) => api.request(method, p, body, opts))
handle('getServer', () => api.server)
handle('setServer', (_e, url: string) => { api.server = url })
handle('resolveUrl', (_e, p: string) => api.resolve(p))
handle('openExternal', (_e, url: string) => { if (/^(https?:|mailto:)/i.test(url)) return shell.openExternal(url) })
handle('signedIn', () => { if (!launch.demo) bridge.start() })
handle('signedOut', () => { bridge.stop(); api.clearSession() })
handle('bridgeState', () => bridge.state())
handle('setControl', (_e, on: boolean) => (on ? bridge.policy.setEnabled(true) : bridge.emergencyStop()))
handle('setScope', (_e, scope, mode) => bridge.policy.setMode(scope, mode))
handle('resetScopes', () => bridge.policy.resetModes())
handle('addFolder', async () => {
  const res = await dialog.showOpenDialog(main ?? undefined as any, { title: 'Share folders with your employees', properties: ['openDirectory', 'multiSelections', 'createDirectory'], buttonLabel: 'Share' })
  if (!res.canceled) res.filePaths.forEach((f) => bridge.policy.addFolder(f))
})
handle('removeFolder', (_e, p: string) => bridge.policy.removeFolder(p))
handle('revealFolder', (_e, p: string) => shell.openPath(p))
handle('emergencyStop', () => bridge.emergencyStop())
handle('unlinkDevice', (_e, id: string) => bridge.unlink(id))
handle('consentDecide', (_e, id: string, decision: ConsentDecision) => decideConsent(id, decision))
handle('overlayStop', () => bridge.emergencyStop())
handle('toggleCommandBar', () => toggleCommandBar())
handle('hideCommandBar', () => commandBar?.hide())
handle('showMain', (_e, section?: string) => showMain(section))
handle('setBadge', (_e, count: number) => {
  waitingCount = count
  refreshTray()
  if (main && process.platform === 'win32') {
    main.setOverlayIcon(count ? badgeIcon() : null, count ? `${count} waiting on you` : '')
  }
})
handle('notify', (_e, title: string, body: string) => {
  if (Notification.isSupported()) {
    const n = new Notification({ title, body, icon: iconPath() })
    n.on('click', () => showMain('approvals'))
    n.show()
  }
})
handle('window', (_e, action: 'minimize' | 'maximize' | 'close') => {
  if (!main) return
  if (action === 'minimize') main.minimize()
  else if (action === 'maximize') (main.isMaximized() ? main.unmaximize() : main.maximize())
  else main.close()
})
ipcMain.on('syph:broadcast', (_e, channel: string, payload: unknown) => send(channel, payload))

function badgeIcon() {
  // A small amber dot for the taskbar overlay.
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><circle cx="8" cy="8" r="7" fill="#E3A55F"/></svg>`
  return nativeImage.createFromDataURL(`data:image/svg+xml;base64,${Buffer.from(svg).toString('base64')}`)
}

// ---------------------------------------------------------------- lifecycle

app.on('second-instance', () => showMain())

app.whenReady().then(async () => {
  Menu.setApplicationMenu(null)
  if (automation.server) api.server = automation.server
  if (launch.demo) {
    bridge.policy.onChange = null
  }
  createMain()
  tray = new Tray(nativeImage.createFromPath(iconPath()).resize({ width: 16, height: 16 }))
  tray.on('click', () => showMain())
  refreshTray()

  globalShortcut.register('Alt+Space', toggleCommandBar)
  globalShortcut.register('Control+Alt+.', () => bridge.emergencyStop())

  if (automation.email && automation.password) {
    // CI only: sign in, then the renderer restores the session like a normal launch.
    for (let i = 0; i < 10; i++) {
      const res = await api.request('POST', '/api/v1/auth/login', { email: automation.email, password: automation.password })
      if (res.ok) { bridge.policy.setEnabled(true); break }
      await new Promise((r) => setTimeout(r, 3000))
    }
  }
  if (launch.demo && launch.demoConsent) {
    setTimeout(() => {
      showOverlay('Atlas', 'Reading the shipping sheet in Excel', 'hsl(40 100% 77%)')
      void askConsent({
        id: 'demo', employee: 'Ines', scope: 'shell', operation: 'run_shell', headline: 'Run a PowerShell command',
        detail: "New-Item -ItemType Directory -Force ~\\Documents\\Syph\\Invoices; Move-Item ~\\Downloads\\*invoice*.pdf ~\\Documents\\Syph\\Invoices",
        deadline: Date.now() + 60_000,
      })
    }, 1200)
  }
})

app.on('before-quit', () => { quitting = true })
app.on('will-quit', () => globalShortcut.unregisterAll())
app.on('window-all-closed', () => { if (launch.demo) app.quit() })
