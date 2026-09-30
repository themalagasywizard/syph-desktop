import {
  ClipboardList, Eye, FolderOpen, FolderPlus, Laptop, LayoutGrid, Link2Off, MinusCircle, Monitor, MousePointerClick,
  Power, ScanText, ShieldCheck, Terminal, FileEdit, Folder, Keyboard, Globe, FileSpreadsheet, FolderSearch, type LucideIcon,
} from 'lucide-react'
import type { LocalAction, Scope, ScopeMode } from '../../shared/types'
import { AgentOrb } from '../components/Orb'
import { Card, Eyebrow, IconButton, KeyCap, Monogram, Segmented, StatusDot, Switch } from '../components/ui'
import { syph } from '../lib/bridge'
import { alpha, palette, statusColor } from '../lib/theme'
import { setTool, useStore } from '../lib/store'

export const SCOPE_META: Record<Scope, { title: string; detail: string; icon: LucideIcon; risk: number }> = {
  observe: { title: 'See what’s open', detail: 'Foreground app, window titles, running apps.', icon: Eye, risk: 0 },
  screen: { title: 'See the screen', detail: 'Screenshots of the screen with its controls numbered, sent to your AI model so it can act. Password fields are blacked out before anything leaves this PC.', icon: ScanText, risk: 1 },
  control: { title: 'Click and type', detail: 'Move the pointer, click, type and press shortcuts while you watch.', icon: MousePointerClick, risk: 2 },
  apps: { title: 'Open apps and links', detail: 'Launch, focus and close apps; open links in your browser.', icon: LayoutGrid, risk: 1 },
  browser: { title: 'Use Syph’s browser', detail: 'A separate Edge profile the employee reads and fills in directly. Sign in to sites there once; your own browser is untouched.', icon: Globe, risk: 2 },
  office: { title: 'Excel, Word and Outlook', detail: 'Read and write open workbooks and documents, read mail, and draft emails for you to send. Never sends by itself.', icon: FileSpreadsheet, risk: 2 },
  clipboard: { title: 'Clipboard', detail: 'Read and write the clipboard.', icon: ClipboardList, risk: 0 },
  files_read: { title: 'Read shared files', detail: 'List, search and read files, only inside the folders you share below.', icon: Folder, risk: 1 },
  files_outside: { title: 'Read other files', detail: 'Search and read files elsewhere in your user folder. Syph’s session, passwords and browser secrets stay off-limits.', icon: FolderSearch, risk: 2 },
  files_write: { title: 'Change shared files', detail: 'Create, overwrite and recycle files inside shared folders.', icon: FileEdit, risk: 2 },
  shell: { title: 'Run PowerShell commands', detail: 'Run PowerShell as you. The most powerful scope — keep it on Ask.', icon: Terminal, risk: 3 },
}
const ORDER: Scope[] = ['observe', 'screen', 'control', 'apps', 'browser', 'office', 'clipboard', 'files_read', 'files_outside', 'files_write', 'shell']
const DEFAULTS: Record<Scope, ScopeMode> = {
  observe: 'allow', screen: 'allow', apps: 'allow', files_read: 'allow', clipboard: 'allow',
  control: 'ask', files_write: 'ask', shell: 'ask', browser: 'ask', office: 'ask', files_outside: 'ask',
}

export function ComputerScreen() {
  return (
    <div className="scroll" style={{ flex: 1 }}>
      <div style={{ padding: '40px 28px 28px', display: 'flex', flexDirection: 'column', gap: 26 }}>
        <Hero />
        <ReadinessStrip />
        <div style={{ display: 'flex', gap: 22, alignItems: 'flex-start' }}>
          <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 26 }}>
            <ScopeGrid />
            <Folders />
          </div>
          <div style={{ width: 360, flex: 'none', display: 'flex', flexDirection: 'column', gap: 26 }}>
            <WhoCanDrive />
            <ActionLog />
            <LinkedDevices />
          </div>
        </div>
      </div>
    </div>
  )
}

function Hero() {
  const bridge = useStore((s) => s.bridge)
  const on = !!bridge?.policy.controlEnabled
  const running = bridge?.current
  const tint = on ? palette.mint : palette.ice
  const link = bridge?.link ?? 'idle'
  const [linkText, linkColor] = link === 'online' ? ['Linked', palette.mint] : link === 'linking' ? ['Linking', palette.amber] : link === 'offline' ? ['Reconnecting', palette.coral] : ['Not linked', palette.text3]
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 26, padding: 26, borderRadius: 24, transition: 'background .4s',
      background: `linear-gradient(135deg, ${alpha(tint, 0.07)}, rgba(255,255,255,0.015))`,
      boxShadow: `inset 0 0 0 0.9px ${alpha(tint, 0.3)}`,
    }}>
      <div style={{ width: 140, height: 140, display: 'grid', placeItems: 'center', flex: 'none', position: 'relative' }}>
        {on && <div style={{ position: 'absolute', width: 180, height: 180, borderRadius: '50%', background: `radial-gradient(${alpha(palette.mint, 0.18)}, transparent 60%)` }} />}
        <AgentOrb mood={running ? 'working' : on ? 'idle' : 'offline'} tint={tint} size={112} />
      </div>
      <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 10 }}>
        <Eyebrow color={on ? palette.mint : palette.text3} style={{ whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>This PC · {bridge?.hostName ?? 'PC'}</Eyebrow>
        <div className="t-display" style={{ fontSize: 28 }}>
          {running ? `${running.employee || 'An employee'} is working here` : on ? 'Your team can work on this PC' : 'Computer control is off'}
        </div>
        <div className="t-body c2" style={{ maxWidth: 560, lineHeight: 1.55 }}>
          {on
            ? 'They see only what the scopes below allow. Everything they do glows on screen and is logged. Press Ctrl+Alt+. anywhere to stop instantly.'
            : 'Turn it on to let employees read your screen, open apps, click, type and work with shared files — always within the limits you set.'}
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginTop: 4 }}>
          {on
            ? <button className="btn-ghost" style={{ color: palette.coral }} onClick={() => void syph.emergencyStop()}><Power size={14} />Turn off</button>
            : <button className="btn-signal" onClick={() => void syph.setControl(true)}><Power size={14} />Allow computer control</button>}
          <span style={{ display: 'flex', gap: 4 }}><KeyCap k="Ctrl" /><KeyCap k="Alt" /><KeyCap k="." /></span>
          <span className="t-caption c3">kill switch</span>
          <span style={{ flex: 1 }} />
          <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
            <StatusDot color={linkColor} pulsing={link === 'linking'} size={6} /><span className="t-caption" style={{ color: linkColor }}>{linkText}</span>
          </span>
        </div>
      </div>
    </div>
  )
}

function ReadinessStrip() {
  const items: [LucideIcon, string, string][] = [
    [ScanText, 'On-device OCR', 'Screen text is read by Windows itself; no image leaves the PC.'],
    [ShieldCheck, 'Runs as you', 'No admin rights. Elevated (UAC) windows stay out of reach.'],
    [Keyboard, 'Always stoppable', 'Stop in the top bar, the tray, or Ctrl+Alt+. from any app.'],
  ]
  return (
    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 12 }}>
      {items.map(([Icon, title, detail]) => (
        <Card key={title} radius={14} pad={14} style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <Icon size={18} color={palette.mint} style={{ flex: 'none' }} />
          <div style={{ minWidth: 0 }}>
            <div className="t-headline">{title}</div>
            <div className="t-caption c3 clamp2">{detail}</div>
          </div>
        </Card>
      ))}
    </div>
  )
}

function ScopeGrid() {
  const bridge = useStore((s) => s.bridge)
  const modes = bridge?.policy.modes ?? DEFAULTS
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12, opacity: bridge?.policy.controlEnabled ? 1 : 0.55, transition: 'opacity .3s' }}>
      <div style={{ display: 'flex', alignItems: 'center' }}>
        <Eyebrow style={{ flex: 1 }}>What they may do</Eyebrow>
        <button className="btn-ghost sm" onClick={() => void syph.resetScopes()}>Safe defaults</button>
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(300px, 1fr))', gap: 12 }}>
        {ORDER.map((scope) => {
          const meta = SCOPE_META[scope]
          const mode = modes[scope] ?? DEFAULTS[scope]
          const c = mode === 'off' ? palette.text3 : mode === 'ask' ? palette.amber : palette.mint
          const riskColor = meta.risk <= 1 ? palette.mint : meta.risk === 2 ? palette.amber : palette.coral
          const Icon = meta.icon
          return (
            <Card key={scope} hl={mode === 'allow'} radius={14} pad={14} style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <span style={{ width: 30, height: 30, borderRadius: 8, display: 'grid', placeItems: 'center', background: alpha(c, 0.12), flex: 'none' }}>
                  <Icon size={14} color={c} />
                </span>
                <div>
                  <div className="t-headline">{meta.title}</div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 2, marginTop: 2 }}>
                    {[0, 1, 2, 3].map((l) => <span key={l} style={{ width: 9, height: 3, borderRadius: 2, background: l <= meta.risk ? riskColor : palette.faint }} />)}
                    <span style={{ fontSize: 9.5, fontWeight: 500, color: palette.text3, marginLeft: 4 }}>{['Low', 'Low', 'Medium', 'High'][meta.risk]}</span>
                  </div>
                </div>
              </div>
              <div className="t-caption c2" style={{ flex: 1 }}>{meta.detail}</div>
              <Segmented value={mode} onChange={(v) => void syph.setScope(scope, v)}
                options={[{ value: 'off', label: 'Off' }, { value: 'ask', label: 'Ask' }, { value: 'allow', label: 'Allow' }]} />
            </Card>
          )
        })}
      </div>
    </div>
  )
}

function Folders() {
  const folders = useStore((s) => s.bridge?.policy.sharedFolders ?? [])
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
      <div style={{ display: 'flex', alignItems: 'center' }}>
        <Eyebrow style={{ flex: 1 }}>Shared folders</Eyebrow>
        <button className="btn-ghost sm" onClick={() => void syph.addFolder()}><FolderPlus size={12} />Share a folder</button>
      </div>
      <div className="t-caption c3">File scopes only ever reach inside these folders. Commands run from the first one.</div>
      {folders.map((f) => (
        <Card key={f} radius={10} pad={10} style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <Folder size={20} color="#e8b04b" fill="rgba(232,176,75,0.25)" style={{ flex: 'none' }} />
          <div style={{ flex: 1, minWidth: 0 }}>
            <div className="t-callout">{f.split(/[\\/]/).filter(Boolean).pop()}</div>
            <div className="t-caption c3 ellipsis">{f}</div>
          </div>
          <IconButton icon={FolderOpen} label="Show in File Explorer" size={22} onClick={() => void syph.revealFolder(f)} />
          <IconButton icon={MinusCircle} label="Stop sharing" size={22} onClick={() => void syph.removeFolder(f)} />
        </Card>
      ))}
    </div>
  )
}

function WhoCanDrive() {
  const employees = useStore((s) => s.employees)
  return (
    <Card radius={16} pad={16} style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
      <Eyebrow>Who can use this PC</Eyebrow>
      {employees.map((e) => {
        const on = !!e.toolIds?.includes('computer')
        return (
          <div key={e.id} style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <Monogram employee={e} size={26} />
            <div style={{ flex: 1 }}>
              <div className="t-callout">{e.name}</div>
              <div className="t-caption c3">{e.autonomyLevel === 'conservative' ? 'Asks before every action' : 'Acts within your scopes'}</div>
            </div>
            <Switch on={on} onChange={(v) => void setTool('computer', v, e)} label={`${e.name} can use this PC`} />
          </div>
        )
      })}
      {!employees.length && <div className="t-caption c3">Hire an employee first.</div>}
    </Card>
  )
}

function ActionLog() {
  const bridge = useStore((s) => s.bridge)
  const row = (a: LocalAction, live: boolean) => {
    const c = statusColor(a.status)
    const Icon = a.scope ? SCOPE_META[a.scope]?.icon ?? Monitor : Monitor
    return (
      <div key={a.id + (live ? '-live' : '')} style={{ display: 'flex', gap: 10 }}>
        <span style={{ width: 22, height: 22, borderRadius: '50%', display: 'grid', placeItems: 'center', background: alpha(c, 0.12), flex: 'none' }}>
          <Icon size={11} color={c} />
        </span>
        <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
          <div style={{ display: 'flex', gap: 6, alignItems: 'baseline' }}>
            <span style={{ fontSize: 11.5, fontWeight: 600 }}>{a.employee || 'Employee'}</span>
            <span className="t-caption c3" style={{ flex: 1 }}>{a.operation.replace(/_/g, ' ')}</span>
            <span className="t-caption cf">{live ? 'now' : new Date(a.startedAt).toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })}</span>
          </div>
          <div className="t-caption c2 clamp2">{a.summary}</div>
          {a.thumbnail && <img src={a.thumbnail} alt="" style={{ maxHeight: 110, objectFit: 'contain', alignSelf: 'flex-start', borderRadius: 6, boxShadow: 'inset 0 0 0 0.5px var(--hairline)' }} />}
        </div>
      </div>
    )
  }
  return (
    <Card radius={16} pad={16} style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
      <div style={{ display: 'flex', alignItems: 'center' }}>
        <Eyebrow style={{ flex: 1 }}>Live on this PC</Eyebrow>
        {bridge?.current && <StatusDot color={palette.ice} pulsing size={6} />}
      </div>
      {bridge?.current && row(bridge.current, true)}
      {bridge?.log.slice(0, 14).map((a) => row(a, false))}
      {!bridge?.log.length && !bridge?.current && <div className="t-caption c3">Nothing yet. Try asking an employee: “Read my screen and tell me what’s open.”</div>}
    </Card>
  )
}

function LinkedDevices() {
  const bridge = useStore((s) => s.bridge)
  return (
    <Card radius={16} pad={16} style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
      <Eyebrow>Linked computers</Eyebrow>
      {bridge?.devices.map((d) => {
        const Icon = d.platform === 'windows' ? Monitor : Laptop
        return (
          <div key={d.id} style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <Icon size={16} color={d.online ? palette.mint : palette.text3} style={{ flex: 'none' }} />
            <div style={{ flex: 1, minWidth: 0 }}>
              <div className="t-callout ellipsis">{d.name}{d.id === bridge.deviceId ? ' (this PC)' : ''}</div>
              <div className="t-caption c3 ellipsis">{d.platform === 'windows' ? 'Windows' : 'macOS'} · {d.online ? 'online' : 'offline'}</div>
            </div>
            {d.id !== bridge.deviceId && <IconButton icon={Link2Off} label="Unlink" size={22} onClick={() => void syph.unlinkDevice(d.id)} />}
          </div>
        )
      })}
      {!bridge?.devices.length && <div className="t-caption c3">No computers linked yet.</div>}
    </Card>
  )
}
