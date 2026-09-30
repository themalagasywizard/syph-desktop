# Syph for Windows

The Windows desktop client for Syph, built to feel identical to
[Syph for Mac](../mac/README.md): same design tokens, same animated
agent orbs, same screens, same command bar and consent flow. Like the Mac
app, it adds one thing the web and iPhone can't do: **with your permission,
your AI employees can work on this PC.**

> **Status:** builds and runs on Windows in CI (GitHub `windows-latest`): the
> native helper's self-test drives Notepad end to end and the device-contract
> test runs every operation against the real app. The agent eval
> (`ci/agent_eval.py`) needs a real server and model and is run on demand.

## Install

Download `Syph-1.0.0-setup.exe` (installs per user, no admin rights) or
`Syph-1.0.0-portable.exe` (nothing installed). Until the build is code-signed,
Windows SmartScreen will warn: **More info → Run anyway**.

## Build

Requirements: Node 20+, npm, and the .NET 8 SDK for the native helper. The
helper and the app build on Windows, macOS or Linux (no Wine needed; the icon
and version info are stamped with `resedit`); the NSIS installer is built on
Windows (CI does this).

```bash
cd windows
npm install
npm run dist            # → release/Syph-1.0.0-setup.exe and -portable.exe
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
commands, reports which operations it supports (`capabilities`), and enforces
the owner's limits locally.

### How an employee works on this PC

1. **Looks.** `snapshot` captures the monitor with the front window, boxes and
   numbers every control (set-of-marks), and lists those controls (role, name,
   value, state) in the screenshot's pixels. The model sees the image.
   Password fields are blacked out before anything leaves the PC.
2. **Acts by id.** `click {element: 14}`, `type_text`, `set_value`, `press`,
   `drag`, `scroll`, `window`, or a batch of steps with `act`. Unicode typing
   works in every language; UI Automation patterns work on windows behind others.
3. **Checks.** Every action waits for the screen to settle and returns a fresh
   snapshot with a `changed` flag, so there's no extra "look" round trip.
4. **Uses a program instead of pixels when one exists:** Syph's own browser
   (a separate Edge profile driven over the DevTools protocol: numbered page
   elements, full page text, downloads into the shared folder), Excel / Word /
   Outlook through COM (whole sheets and documents in one call, email as
   drafts only), Windows Search for files, and a persistent PowerShell session.
5. **Yields.** If the owner touches the mouse or keyboard mid-action, the action
   stops at once, the pill says *Paused*, and nothing runs until they've left
   the PC alone for 8 seconds.

Longer jobs go to a **computer operator** on the server (`computer_task`): its
own run with a desktop-specific prompt, a budget of hundreds of steps, and
recipes of how similar tasks were done before on this PC.

### Limits the owner controls

- **Master switch**; turning it off cancels queued commands on the server.
  **Ctrl+Alt+.** stops everything from any app, including an action in progress.
- **Scopes**, each Off / Ask / Allow: see what's open, see the screen, click
  and type, open apps and links, Syph's browser, Excel/Word/Outlook, clipboard,
  read shared files, read other files, change shared files, run PowerShell.
  Acting scopes default to **Ask**; the owner can Always allow them.
- **Always asked, whatever the scope:** pressing anything that pays, orders,
  sends, deletes, publishes, signs or unsubscribes; destructive or system
  PowerShell (recursive deletes, installs, services, users, firewall, running
  downloaded code); force-quitting apps. The consent panel shows the exact
  target and has no "Always" for these.
- **Never done:** typing into password, card or one-time-code fields; reading
  Syph's own session and settings, Windows credential stores, browser secret
  stores or SSH keys; commands that touch Syph's process or settings; closing
  or moving Syph's windows.
- **Files:** writing only inside shared folders (default `Documents\Syph`);
  reading elsewhere is its own scope; paths are resolved through symlinks and
  junctions before they are checked.
- The scope settings are stored encrypted with DPAPI, so a PowerShell command
  running as the owner can't rewrite them.
- Elevated (UAC) windows and the secure desktop stay out of reach: Syph runs as
  the owner without admin rights, by design.

### Pieces

| Piece | What it does |
| --- | --- |
| `host/` — **SyphHost.exe** (C# .NET 8, self-contained) | One long-lived process: capture (every monitor, one window, GPU-drawn apps), Windows OCR, UI Automation with stable element ids, SendInput (Unicode, chords, drag, hold), window management, Start-menu apps, waits, Office COM, Windows Search, the owner-input watcher. JSON lines over stdio. `SyphHost.exe --selftest` drives Notepad end to end. |
| `src/main/host.ts` | Starts the helper on first use, restarts it if it exits, per-call timeouts. |
| `src/main/executor.ts` | Every operation; the PowerShell scripts in `resources/ps/` remain a fallback for the original ones if the helper is missing. |
| `src/main/browser.ts` | Syph's browser (playwright-core over the installed Edge or Chrome). |
| `src/main/guard.ts` | The always-ask / never-do rules above. |
| `src/main/policy.ts` | Scopes, shared folders, readable paths, the encrypted store. |

The session cookie is kept encrypted with Windows DPAPI (`safeStorage`).

## Testing

| What | How |
| --- | --- |
| Types, scope table, guard rules | `npm run typecheck && npm test` |
| Native helper on a real desktop | `npm run build:host`, then `host\publish\SyphHost.exe --selftest` |
| Every operation through the real app | `ci/device_contract_e2e.py` with `SYPH_PLATFORM=windows` (a stand-in API; see the workflow) |
| The agent doing real chores | `ci/agent_eval.py` against a real server: run the *Syph for Windows* workflow manually with **agent_eval** and the `SYPH_EVAL_SERVER`, `SYPH_EVAL_EMAIL`, `SYPH_EVAL_PASSWORD`, `SYPH_EVAL_EMPLOYEE` secrets |

Code signing: set `WINDOWS_CSC_LINK` (base64 .pfx) and
`WINDOWS_CSC_KEY_PASSWORD`; CI then signs SyphHost.exe, the app, the installer
and the portable exe. Without them the build is unsigned.

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

- Code-signing certificate (the pipeline is ready for it).
- Run the agent eval against the production model on a Windows 11 PC with
  Office installed, and tune from its failures.
- Multi-monitor snapshots show the monitor with the front window; `monitor: "all"`
  is available but the model is not yet told when other monitors hold the task.
