# Syph Desktop

The desktop apps for [Syph](https://github.com/themalagasywizard/Syph-IOS) —
AI employees for small businesses — on **macOS** and **Windows**. Both talk to
the same Syph API as the web console and iPhone app, share one design system,
and add what only a desktop can: **with your permission, your AI employees can
work on your computer** while you watch, with a kill switch always one
shortcut away.

| | [Syph for Mac](mac/README.md) | [Syph for Windows](windows/README.md) |
| --- | --- | --- |
| Stack | SwiftUI, macOS 14+ | Electron + React, Windows 10/11 x64 |
| Build | `open mac/Syph-Mac.xcodeproj` | `cd windows && npm install && npm run dist` |
| Command bar | ⌥Space | Alt+Space |
| Kill switch | ⌃⌥⌘. | Ctrl+Alt+. |
| Screen reading | ScreenCaptureKit + Vision OCR | SyphHost: capture + Windows OCR + numbered snapshots the model sees |
| Controls | Accessibility API | UI Automation (stable element ids), SendInput, browser + Office automation |
| Shell | zsh + AppleScript | PowerShell |
| Verified | CI build, screenshots, 16/16 end-to-end on a real Mac | CI on windows-latest: native self-test, end-to-end device contract, screenshots |

## Shared behaviour

- **Screens:** Command (chat with live run timeline), Team, Needs you
  (approvals), Work, Library, This Mac / This PC, Settings; a menu-bar / tray
  companion; a global command bar.
- **Computer control:** the computer links itself as a device
  (`/api/v1/devices/*`) and runs what employees queue, under local
  **Off / Ask / Allow** scopes, a consent panel for ask-first actions,
  shared-folder limits for files, an on-screen glow and "is using your
  computer" pill while acting, and a local and server-side action log. Server
  side: `jarvis/docs/COMPUTER_CONTROL.md`.
- **Design:** void canvas, hairline glass, ice-blue signal, mint for done,
  amber for needs-you, and an animated agent orb per employee, in the same
  colour on every platform.

## Layout

```
mac/        Syph for Mac (Xcode project, SwiftUI sources, CI end-to-end harness)
windows/    Syph for Windows (Electron main, React renderer, PowerShell scripts)
docs/       Mac screenshots from CI
.github/    Mac CI: build, screenshots, end-to-end computer control
```
