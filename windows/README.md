# Syph for Windows

The Windows desktop client for Syph, built to feel identical to
[Syph for Mac](../mac/README.md): same design tokens, same animated
agent orbs, same screens, same command bar and consent flow. Like the Mac
app, it adds one thing the web and iPhone can't do: **with your permission,
your AI employees can work on this PC.**

> **Status:** the app builds and every screen has been rendered from demo
> data, but it has **not yet been run on Windows**. Treat computer control as
> untested until a Windows run confirms it.

## Install

Download `Syph-1.0.0-portable.exe` and double-click it — nothing is
installed. The app isn't code-signed yet, so Windows SmartScreen will warn:
**More info → Run anyway**.

## Build

Requirements: Node 20+, npm. Builds on Windows, macOS or Linux (no Wine
needed; the icon and version info are stamped with `resedit`).

```bash
cd windows
npm install
npm run dist            # → release/Syph-1.0.0-portable.exe
npm start               # build and run with Electron
npm run typecheck
```

Design review without Windows: `npm run build && npm run shots` renders every
screen and floating surface from the demo fixture in headless Chromium.
Launching with `--demo --section=computer` (and `--demo-consent`) shows the
same fixture in the real app.

## What's in it

| Area | What it does |
| --- | --- |
| Command | Chat with an employee, live run timeline, inline approvals, threads and recent activity. Enter sends, Shift+Enter new line. |
| Team | Employee tiles with presence orbs, detail panel (mission, autonomy, tools, schedule), pause/resume/wake, hire flow. |
| Needs you | Decision inbox. Ctrl+Enter approves, Ctrl+Backspace declines. Toast notifications and a taskbar badge. |
| Work / Library | Activity timeline and schedules; document search, preview and download. |
| This PC | Computer control center (below). |
| Settings | Account, AI model provider/key/test, connected tools, shortcuts. |
| Tray | Open, command bar, needs-you count, computer-control switch, quit. Closing the window keeps Syph in the tray. |
| Command bar | **Alt+Space** from any app; Tab switches employee, Ctrl+Enter sends and opens the thread. Also Ctrl+K. |

## Computer control

Same device contract as the Mac (`/api/v1/devices/*`, see
`jarvis/docs/COMPUTER_CONTROL.md`). The PC links itself, long-polls for
commands, and enforces the owner's limits locally:

- **Master switch**; turning it off cancels queued commands on the server.
- **Scopes**, each Off / Ask / Allow: see what's open, read the screen, click
  and type, open apps and links, clipboard, read shared files, change shared
  files, run PowerShell. Risky scopes default to **Ask**.
- **Ask** shows a floating consent panel with the exact command or text:
  Decline, Allow once, Always allow. It declines by itself after 60 s.
- **Shared folders** only (default `Documents\Syph`); paths are resolved
  through symlinks and junctions.
- While an employee acts, the **screen edge glows** in their colour and a
  pill says who is driving, with **Stop**. **Ctrl+Alt+.** stops everything
  from any app.

How it works on Windows (no native modules; Windows PowerShell 5.1 scripts in
`resources/ps/`):

| Capability | Implementation |
| --- | --- |
| Read the screen | GDI capture + **Windows OCR** (`Windows.Media.Ocr`), on-device; lines with click-ready coordinates |
| Read / press controls | **UI Automation** on the foreground window |
| Click, type, keys, scroll | `SetCursorPos` / `mouse_event`, `SendKeys`, `keybd_event` (DPI-aware, physical pixels) |
| Open / quit apps | Start menu entries (`Get-StartApps`), then `Start-Process`; quit via `CloseMainWindow` |
| Shell | PowerShell, run from the first shared folder |
| AppleScript | Mac-only: refused with a message pointing to PowerShell |

Elevated (UAC) windows are out of reach, since the app runs as you without
admin rights. The session cookie is kept encrypted with Windows DPAPI
(`safeStorage`).

## Layout

```
windows/
  src/main/        Electron main: API client, device bridge, policy, executor, windows, tray, shortcuts
  src/renderer/    React UI: design system, store, screens, floating surfaces (command bar, consent, glow, pill)
  src/shared/      wire models and the preload bridge contract
  resources/ps/    PowerShell scripts for observe, screen/OCR, UI Automation, input, apps
  scripts/         esbuild for main, screenshot renderer, afterPack icon stamping
  build/           icon.ico / icon.png
```

## Still to do

- Run on Windows 10/11 and add a Windows CI job (build, screenshots, the same
  end-to-end device-contract test the Mac passes).
- NSIS installer (needs a Windows runner or Wine) and code signing.
