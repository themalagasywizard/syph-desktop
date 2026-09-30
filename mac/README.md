# Syph for Mac

A native SwiftUI macOS client for Syph. It talks to the same backend as the web
console and the iPhone app (`/api/v1/*`, session cookie), and adds one thing
the other clients cannot: **with your permission, your AI employees can work
on this Mac.**

Part of the Syph native apps — see also the [iPhone app](https://github.com/themalagasywizard/Syph-IOS) and
[Syph for Windows](../windows/README.md), which shares this design and
the same computer-control contract.

## Build and run

Requirements: macOS 14+, Xcode 16 or newer.

```bash
open mac/Syph-Mac.xcodeproj   # scheme "Syph", destination "My Mac"
```

Sign in with your Syph account. The server defaults to
`https://srv1982864.hstgr.cloud`; change it under **Server** on the sign-in
screen (for local development, `http://localhost:8000`).

CI builds every push that touches `mac/` (`.github/workflows/mac-build.yml`)
and uploads an unsigned `Syph.app` artifact.

The app is **not sandboxed**: driving other apps (Accessibility, AppleEvents,
shell) is impossible inside the App Sandbox. Distribute it signed with
Developer ID and notarized, not through the Mac App Store.

## What is in it

| Area | What it does |
| --- | --- |
| Command | Chat with an employee, live run timeline with each tool step, inline approvals, threads and recent activity. ↩ sends, ⇧↩ new line. |
| Team | Employee tiles with a live presence orb, detail panel (mission, autonomy, tools, schedule), pause/resume/wake, hire flow. |
| Needs you | Decision inbox. ⌘↩ approves, ⌘⌫ declines. Notifications when the app is in the background. |
| Work | Activity timeline across the team and recurring schedules (toggle/delete). |
| Library | Search and preview documents, download in any format the backend produced. |
| This Mac | Computer control center (below). |
| Settings | Account, AI model provider/key/test, connected tools (Google connect opens the browser), shortcuts. |
| Menu bar | Who is working, approve/decline, the computer-control switch. The app keeps running when the window closes. |
| Command bar | **⌥Space** from any app: tell an employee what to do; ⇥ switches employee, ⌘↩ sends and opens the thread. Also ⌘K. |
| Desktop widget | The Syph orb, anywhere on your desktop (drag it; it remembers where). Click it and it opens into a small chat with one employee — live steps, Stop, approvals, files as chips — without the main window and without taking focus from the app you're in. It tells the employee which app and window you're using (a chip you can switch off), so "fix this" works. ⇥ / ‹ › switch employee, ↩ sends, esc closes, ⌘O opens the full app on the same conversation. **⌥⇧Space** opens it from anywhere; **⇧⌘D** or the orb button in the sidebar turns the app into the widget; the menu bar has Widget / Hide widget; right-click the orb to start in widget mode. |

## Computer control

The Mac registers itself as a **device** (`PUT /api/v1/devices/{id}`) and
long-polls for commands (`GET /api/v1/devices/{id}/commands/next`). On the
server, the `computer` tool queues a command and waits for the Mac's result.
Employees only get the tool when **computer** is on in their tools (This Mac →
*Who can use this Mac*, or the employee's tools).

The Mac is the enforcement point:

- **Master switch.** Off means nothing is delivered; turning it off cancels any
  queued commands on the server.
- **Scopes**, each Off / Ask / Allow: see what's open, read the screen (on-device
  OCR — only text leaves the Mac, plus a small thumbnail kept for your log),
  click and type, open apps and links, clipboard, read shared files, change
  shared files, AppleScript, terminal. Risky scopes default to **Ask**.
- **Ask** shows a floating consent panel (never steals focus) with the exact
  command, script, path or text: *Decline*, *Allow once*, *Always allow*. It
  declines by itself after 60 s.
- **Shared folders.** File operations resolve symlinks and refuse anything
  outside the folders you share. Default: `~/Documents/Syph`.
- **While an employee acts,** the screen edge glows in their colour and a pill
  at the top says who is driving and what they're doing, with **Stop**.
- **Kill switch:** **⌃⌥⌘.** anywhere, the pill's Stop button, the menu bar
  switch, or *Employees → Stop Computer Control*.
- Every action is logged locally (This Mac → *Live on this Mac*) and on the
  server (`GET /api/v1/devices/commands/recent`).

macOS permissions: **Accessibility** (click, type, read controls) and **Screen
Recording** (read the screen). This Mac shows their state and a *Grant* button.
AppleScript triggers macOS's own per-app Automation prompt.

Operations the server may request: `observe`, `read_screen`, `read_ui`,
`click`, `click_text`, `press`, `type_text`, `press_keys`, `scroll`,
`open_app`, `quit_app`, `open_url`, `list_files`, `read_file`, `write_file`,
`trash_file`, `run_shell`, `applescript`, `clipboard_read`,
`clipboard_write`, `notify`.

## Verification

CI (`.github/workflows/mac-build.yml`, macOS 15 runner, Xcode 26.3) on every push:

1. **Builds** the app.
2. **Screenshots** every section from a fixture (`-SyphDemo YES -SyphSection <name>`,
   `-SyphDemoConsent YES` for the consent panel and driving overlay). Manual
   runs commit them to [`docs/ui/mac/`](../docs/mac-screenshots/).
3. **End-to-end computer control** (`CI/device_contract_e2e.py`): a stand-in
   for the API speaks the device wire contract; the real app signs in through a
   DEBUG-only launch hook, links itself, and executes 16 real commands — files
   inside and outside shared folders, zsh, AppleScript, clipboard, open/quit
   TextEdit, a refused `file://` link, screen OCR and Accessibility reading.
   The server half of the contract is covered by the backend's
   `tests/test_devices.py`.

## Layout

```
mac/
  Syph-Mac.xcodeproj
  Config/SyphMac.entitlements      non-sandboxed, AppleEvents
  Syph-Mac/
    App/            entry point, scenes, menus, AppModel, global hotkeys
    Core/API        wire models and HTTP client
    Core/Store      WorkspaceStore (same endpoints as the iOS store)
    Core/Design     tokens, components, AgentOrb, backdrop
    Computer/       DeviceBridge, policy, executor, OCR, input, AX, consent, overlay
    Features/       Chat, Team, Approvals, Work/Library, Computer, Settings, Shell
  CI/device_contract_e2e.py        end-to-end harness used by CI
```
