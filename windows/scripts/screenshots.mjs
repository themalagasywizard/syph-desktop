// Renders every screen and surface from the demo fixture in headless Chromium.
import { chromium } from 'playwright-core'
import { spawn } from 'node:child_process'
import fs from 'node:fs'

const out = process.argv[2] ?? 'shots'
fs.mkdirSync(out, { recursive: true })
// npx is a .cmd on Windows, which Node only spawns through a shell.
const server = spawn('npx', ['vite', 'preview', '--port', '4173', '--strictPort'], { stdio: 'ignore', shell: process.platform === 'win32' })
await new Promise((r) => setTimeout(r, 2500))
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' })
const page = await browser.newPage({ viewport: { width: 1320, height: 840 }, deviceScaleFactor: 1 })
const errors = []
page.on('pageerror', (e) => errors.push(e.message))
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()) })
for (const section of ['chat', 'team', 'approvals', 'work', 'library', 'computer', 'settings']) {
  await page.goto(`http://localhost:4173/?surface=main&section=${section}`)
  await page.waitForTimeout(1200)
  await page.screenshot({ path: `${out}/${section}.png` })
}
for (const [surface, w, h] of [['commandbar', 700, 440], ['consent', 460, 400], ['pill', 540, 72]]) {
  await page.setViewportSize({ width: w, height: h })
  await page.goto(`http://localhost:4173/?surface=${surface}`)
  // Stand in for a desktop wallpaper behind the transparent window.
  await page.addStyleTag({ content: 'html{background:radial-gradient(circle at 30% 20%,#2a3b66,#0d1322 60%,#07090f)}' })
  await page.waitForTimeout(900)
  await page.screenshot({ path: `${out}/${surface}.png`, omitBackground: true })
}
await browser.close()
server.kill()
console.log(errors.length ? `ERRORS:\n${[...new Set(errors)].join('\n')}` : 'no console errors')
