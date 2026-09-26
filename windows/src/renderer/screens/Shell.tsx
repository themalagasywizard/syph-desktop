import { useEffect, useState } from 'react'
import {
  Activity as ActivityIcon, ArrowRight, AtSign, BadgeCheck, BookOpen, CheckCircle2, CircleAlert, Lock, Minus,
  MessagesSquare, Monitor, MousePointerClick, Plus, Server, SlidersHorizontal, Sparkles, Square, Users, X, Zap,
} from 'lucide-react'
import type { LucideIcon } from 'lucide-react'
import type { Employee, LinkState } from '../../shared/types'
import { AgentOrb, Backdrop, moodFor, Wordmark } from '../components/Orb'
import { KeyCap, StatusDot, TextField, Spinner } from '../components/ui'
import { syph, isElectron } from '../lib/bridge'
import { alpha, hueFor, palette } from '../lib/theme'
import { go, launch, sel, useStoreShallow, selectEmployee, signIn, useStore, type Section } from '../lib/store'
import { ChatScreen } from './Chat'
import { TeamScreen, HireSheet } from './Team'
import { ApprovalsScreen } from './Approvals'
import { WorkScreen, LibraryScreen } from './Work'
import { ComputerScreen } from './Computer'
import { SettingsScreen } from './Settings'

export const SECTION_META: Record<Section, { title: string; icon: LucideIcon }> = {
  chat: { title: 'Command', icon: MessagesSquare },
  team: { title: 'Team', icon: Users },
  approvals: { title: 'Needs you', icon: BadgeCheck },
  work: { title: 'Work', icon: ActivityIcon },
  library: { title: 'Library', icon: BookOpen },
  computer: { title: 'This PC', icon: Monitor },
  settings: { title: 'Settings', icon: SlidersHorizontal },
}

export function App() {
  const phase = useStore((s) => s.phase)
  useEffect(() => {
    void launch()
    void syph.bridgeState().then((b) => useStore.setState({ bridge: b }))
    const offs = [
      syph.on('bridge', (b) => useStore.setState({ bridge: b })),
      syph.on('navigate', (section: Section) => go(section)),
    ]
    const keys = (e: KeyboardEvent) => {
      if (!e.ctrlKey || e.altKey) return
      const n = Number(e.key)
      if (n >= 1 && n <= 7) { e.preventDefault(); go((['chat', 'team', 'approvals', 'work', 'library', 'computer', 'settings'] as Section[])[n - 1]) }
      if (e.key.toLowerCase() === 'k') { e.preventDefault(); void syph.toggleCommandBar() }
      if (e.key.toLowerCase() === 'n') { e.preventDefault(); useStore.setState({ section: 'team', showHire: true }) }
    }
    window.addEventListener('keydown', keys)
    return () => { offs.forEach((o) => o()); window.removeEventListener('keydown', keys) }
  }, [])

  return (
    <div style={{ position: 'relative', height: '100%', display: 'flex', flexDirection: 'column' }}>
      <Backdrop intensity={phase === 'ready' ? 0.55 : 1} />
      <TitleBar />
      <div style={{ position: 'relative', flex: 1, minHeight: 0 }}>
        {(phase === 'restoring' || phase === 'loading') && <LaunchGate message={phase === 'restoring' ? 'Restoring your session' : 'Loading your workspace'} />}
        {phase === 'signedOut' && <SignIn />}
        {phase === 'ready' && <Main />}
      </div>
    </div>
  )
}

/** Frameless window chrome in Windows 11's shape: drag strip plus caption buttons. */
function TitleBar() {
  const caption = (Icon: LucideIcon, action: 'minimize' | 'maximize' | 'close', label: string) => (
    <button className="no-drag caption" aria-label={label} title={label} onClick={() => void syph.window(action)}
      style={{ width: 46, height: 32, display: 'grid', placeItems: 'center', color: palette.text2 }}>
      <Icon size={action === 'maximize' ? 11 : 14} strokeWidth={1.5} />
    </button>
  )
  return (
    <div className="drag" style={{ position: 'absolute', top: 0, left: 0, right: 0, height: 32, zIndex: 50, display: 'flex', justifyContent: 'flex-end' }}>
      <style>{'.caption:hover{background:rgba(255,255,255,0.08);color:#fff}.caption:last-child:hover{background:#c42b1c;color:#fff}'}</style>
      {isElectron && <>{caption(Minus, 'minimize', 'Minimize')}{caption(Square, 'maximize', 'Maximize')}{caption(X, 'close', 'Close')}</>}
    </div>
  )
}

function LaunchGate({ message }: { message: string }) {
  return (
    <div className="fade-in" style={{ position: 'absolute', inset: 0, display: 'grid', placeItems: 'center' }}>
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 22 }}>
        <AgentOrb mood="working" size={88} />
        <div className="t-callout c2">{message}</div>
      </div>
    </div>
  )
}

function SignIn() {
  const { isSigningIn, error } = useStoreShallow((s) => ({ isSigningIn: s.isSigningIn, error: s.error }))
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [server, setServer] = useState('')
  const [showServer, setShowServer] = useState(false)
  useEffect(() => { void syph.getServer().then((s) => setServer(s.includes('srv1982864') ? '' : s)) }, [])
  const submit = () => { if (email && password) void signIn(email.trim(), password) }
  const feature = (Icon: LucideIcon, t: string) => (
    <span className="t-callout c2" style={{ display: 'flex', alignItems: 'center', gap: 7 }}><Icon size={14} color={palette.ice} />{t}</span>
  )
  return (
    <div className="fade-in" style={{ position: 'absolute', inset: 0, display: 'flex' }}>
      <div style={{ flex: 1, padding: 56, display: 'flex', flexDirection: 'column' }}>
        <Wordmark size={12} />
        <div style={{ flex: 1 }} />
        <div className="t-display" style={{ fontSize: 44, letterSpacing: '-0.03em' }}>Your AI team,<br />now on your PC.</div>
        <div style={{ fontSize: 15, color: palette.text2, lineHeight: 1.6, maxWidth: 440, marginTop: 14 }}>
          Command your employees, clear what needs you, and — when you allow it — let them work right here on this computer while you watch.
        </div>
        <div style={{ display: 'flex', gap: 18, marginTop: 28 }}>
          {feature(Zap, 'Instruct')}{feature(BadgeCheck, 'Approve')}{feature(MousePointerClick, 'Act on your PC')}
        </div>
        <div style={{ flex: 1 }} />
        <div className="t-caption cf">© 2026 Syph Software</div>
      </div>
      <div style={{ display: 'grid', placeItems: 'center', padding: 56 }}>
        <div style={{
          width: 400, padding: 32, borderRadius: 24, display: 'flex', flexDirection: 'column', gap: 16,
          background: 'rgba(14,16,21,0.75)', backdropFilter: 'blur(30px)', boxShadow: 'inset 0 0 0 0.75px var(--hairline), 0 20px 40px rgba(0,0,0,0.5)',
        }}>
          <AgentOrb mood={isSigningIn ? 'working' : 'idle'} size={56} />
          <div className="t-title" style={{ marginTop: 6 }}>Sign in</div>
          <div className="t-callout c2">Use the same account as the web console, Mac and iPhone apps.</div>
          <TextField value={email} onChange={setEmail} placeholder="Email" icon={AtSign} autoFocus />
          <TextField value={password} onChange={setPassword} placeholder="Password" secure icon={Lock} onSubmit={submit} />
          {error && <div className="t-caption" style={{ color: palette.coral, display: 'flex', gap: 6 }}><CircleAlert size={13} style={{ flex: 'none', marginTop: 1 }} />{error}</div>}
          <button className="btn-signal" onClick={submit} disabled={!email || !password || isSigningIn}>
            {isSigningIn && <Spinner size={13} color={palette.void} />}{isSigningIn ? 'Signing in' : 'Continue'}<ArrowRight size={14} />
          </button>
          <button className="t-caption c3" style={{ textAlign: 'left' }} onClick={() => setShowServer(!showServer)}>{showServer ? '▾' : '▸'} Server</button>
          {showServer && (
            <div style={{ display: 'flex', gap: 8 }}>
              <div style={{ flex: 1 }}><TextField value={server} onChange={setServer} placeholder="https://srv1982864.hstgr.cloud" icon={Server} /></div>
              <button className="btn-ghost sm" onClick={() => void syph.setServer(server)}>Use</button>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

function Main() {
  const section = useStore((s) => s.section)
  const showHire = useStore((s) => s.showHire)
  return (
    <div style={{ position: 'absolute', inset: 0, display: 'flex' }}>
      <Sidebar />
      <div className="divider-v" />
      <div key={section} className="fade-in" style={{ flex: 1, minWidth: 0, position: 'relative', display: 'flex', flexDirection: 'column' }}>
        {section === 'chat' && <ChatScreen />}
        {section === 'team' && <TeamScreen />}
        {section === 'approvals' && <ApprovalsScreen />}
        {section === 'work' && <WorkScreen />}
        {section === 'library' && <LibraryScreen />}
        {section === 'computer' && <ComputerScreen />}
        {section === 'settings' && <SettingsScreen />}
      </div>
      <Toasts />
      {showHire && <HireSheet />}
    </div>
  )
}

function Sidebar() {
  const s = useStore()
  const waiting = sel.waiting(s)
  const badge = (x: Section) => (x === 'approvals' ? waiting.length : x === 'chat' ? sel.activeCount(s) : 0)
  return (
    <div style={{ width: 232, flex: 'none', display: 'flex', flexDirection: 'column', background: 'rgba(5,5,7,0.6)', position: 'relative' }}>
      <div style={{ padding: '38px 18px 18px' }}><Wordmark size={11} /></div>
      <button className="no-drag" onClick={() => void syph.toggleCommandBar()} style={{
        margin: '0 12px 14px', padding: '8px 10px', borderRadius: 9, display: 'flex', alignItems: 'center', gap: 8,
        background: 'var(--field)', boxShadow: 'inset 0 0 0 0.75px var(--hairline)',
      }}>
        <Sparkles size={14} color={palette.ice} />
        <span className="t-callout c3" style={{ flex: 1, textAlign: 'left', whiteSpace: 'nowrap' }}>Ask your team…</span>
        <KeyCap k="Alt ␣" />
      </button>
      <div style={{ padding: '0 8px', display: 'flex', flexDirection: 'column', gap: 2 }}>
        {(['chat', 'team', 'approvals', 'work', 'library', 'computer'] as Section[]).map((x) => (
          <SidebarRow key={x} section={x} badge={badge(x)} selected={s.section === x} />
        ))}
      </div>
      <div className="eyebrow" style={{ padding: '22px 20px 8px' }}>Team</div>
      <div className="scroll" style={{ flex: 1, padding: '0 8px', display: 'flex', flexDirection: 'column', gap: 2 }}>
        {s.employees.map((e) => <EmployeeRow key={e.id} employee={e} />)}
        <button onClick={() => useStore.setState({ showHire: true })} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '6px 10px', color: palette.text3 }}>
          <span style={{ width: 24, height: 24, borderRadius: '50%', border: '0.75px dashed var(--hairline-strong)', display: 'grid', placeItems: 'center' }}><Plus size={11} /></span>
          <span className="t-callout">Hire</span>
        </button>
      </div>
      <div style={{ padding: '10px 12px' }}><ComputerTile /></div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '12px 14px', boxShadow: 'inset 0 0.5px 0 var(--hairline)' }}>
        {s.user && (
          <>
            <span style={{ width: 26, height: 26, borderRadius: '50%', background: 'rgba(255,255,255,0.08)', display: 'grid', placeItems: 'center', fontSize: 11, fontWeight: 600 }}>
              {s.user.name.slice(0, 1).toUpperCase()}
            </span>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div className="t-callout ellipsis">{s.user.name}</div>
              <div className="t-caption c3 ellipsis">{s.user.email}</div>
            </div>
          </>
        )}
        <button className="icon-btn" style={{ width: 28, height: 28 }} title="Settings" onClick={() => go('settings')}><SlidersHorizontal size={14} /></button>
      </div>
    </div>
  )
}

function SidebarRow({ section, badge, selected }: { section: Section; badge: number; selected: boolean }) {
  const { title, icon: Icon } = SECTION_META[section]
  return (
    <button onClick={() => go(section)} className="side-row" style={{
      position: 'relative', display: 'flex', alignItems: 'center', gap: 10, padding: '7px 10px', borderRadius: 8,
      background: selected ? 'rgba(255,255,255,0.07)' : undefined, transition: 'background .15s',
    }}>
      <style>{'.side-row:hover{background:rgba(255,255,255,0.035)}'}</style>
      {selected && <span style={{ position: 'absolute', left: -4, width: 2.5, height: 14, borderRadius: 2, background: palette.ice, boxShadow: `0 0 6px ${palette.ice}` }} />}
      <Icon size={15} strokeWidth={1.75} color={selected ? palette.ice : palette.text2} />
      <span style={{ fontSize: 13, fontWeight: selected ? 600 : 400, color: selected ? palette.text : palette.text2, flex: 1, textAlign: 'left' }}>{title}</span>
      {badge > 0 && (
        <span style={{
          fontSize: 10.5, fontWeight: 700, padding: '1.5px 6px', borderRadius: 999,
          color: section === 'approvals' ? palette.void : palette.mint,
          background: section === 'approvals' ? palette.amber : alpha(palette.mint, 0.15),
        }}>{badge}</span>
      )}
    </button>
  )
}

function EmployeeRow({ employee }: { employee: Employee }) {
  const s = useStore()
  const waiting = sel.waiting(s).some((a) => a.employeeId === employee.id)
  const run = s.working[employee.id]
  const mood = moodFor(employee, run, waiting)
  const selected = sel.selectedEmployee(s)?.id === employee.id && s.section === 'chat'
  const sub = mood === 'working' ? (run?.phase ? run.phase[0].toUpperCase() + run.phase.slice(1) : 'Working')
    : mood === 'attention' ? 'Needs you' : mood === 'paused' ? 'Paused' : employee.role || 'Idle'
  return (
    <button className="side-row" onClick={() => { selectEmployee(employee); go('chat') }} style={{
      display: 'flex', alignItems: 'center', gap: 10, padding: '5px 10px', borderRadius: 8, background: selected ? 'rgba(255,255,255,0.06)' : undefined,
    }}>
      <AgentOrb mood={mood} tint={hueFor(employee.id)} size={24} />
      <div style={{ minWidth: 0, textAlign: 'left' }}>
        <div className="t-callout ellipsis">{employee.name}</div>
        <div className="ellipsis" style={{ fontSize: 10.5, color: palette.text3 }}>{sub}</div>
      </div>
    </button>
  )
}

export function linkText(link?: LinkState) {
  return link === 'online' ? 'Linked to your workspace' : link === 'linking' ? 'Linking…' : link === 'offline' ? 'Reconnecting…' : 'Not linked'
}

function ComputerTile() {
  const bridge = useStore((s) => s.bridge)
  const enabled = !!bridge?.policy.controlEnabled
  const running = !!bridge?.current
  const tint = enabled ? palette.mint : palette.text3
  return (
    <button onClick={() => go('computer')} style={{
      width: '100%', display: 'flex', alignItems: 'center', gap: 10, padding: 10, borderRadius: 11,
      background: 'rgba(255,255,255,0.03)', boxShadow: 'inset 0 0 0 0.75px var(--hairline)',
    }}>
      <span style={{ width: 28, height: 28, borderRadius: 7, display: 'grid', placeItems: 'center', background: alpha(tint, 0.12) }}>
        {running ? <MousePointerClick size={13} color={tint} /> : <Monitor size={13} color={tint} />}
      </span>
      <div style={{ flex: 1, minWidth: 0, textAlign: 'left' }}>
        <div style={{ fontSize: 11.5, fontWeight: 600 }}>{running ? 'Working on this PC' : enabled ? 'PC control on' : 'PC control off'}</div>
        <div style={{ fontSize: 10.5, color: palette.text3 }}>{linkText(bridge?.link)}</div>
      </div>
      <StatusDot color={bridge?.link === 'online' ? (enabled ? palette.mint : palette.amber) : palette.coral} pulsing={running} size={6} />
    </button>
  )
}

function Toasts() {
  const { error, toast } = useStoreShallow((s) => ({ error: s.error, toast: s.toast }))
  useEffect(() => {
    if (!toast) return
    const t = setTimeout(() => { if (useStore.getState().toast === toast) useStore.setState({ toast: null }) }, 3000)
    return () => clearTimeout(t)
  }, [toast])
  const item = (text: string, Icon: LucideIcon, tint: string, dismiss: () => void) => (
    <div className="fade-in" style={{
      display: 'flex', alignItems: 'center', gap: 10, padding: '10px 14px', borderRadius: 999, background: 'rgba(20,23,32,0.95)',
      boxShadow: `inset 0 0 0 0.75px ${alpha(tint, 0.35)}, 0 6px 16px rgba(0,0,0,0.4)`,
    }}>
      <Icon size={15} color={tint} />
      <span className="t-callout clamp2">{text}</span>
      <button onClick={dismiss} style={{ color: palette.text3 }}><X size={11} strokeWidth={3} /></button>
    </div>
  )
  return (
    <div style={{ position: 'absolute', bottom: 20, left: 232, right: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8, pointerEvents: 'none' }}>
      <div style={{ pointerEvents: 'auto', display: 'flex', flexDirection: 'column', gap: 8, alignItems: 'center' }}>
        {error && item(error, CircleAlert, palette.coral, () => useStore.setState({ error: null }))}
        {toast && item(toast, CheckCircle2, palette.mint, () => useStore.setState({ toast: null }))}
      </div>
    </div>
  )
}


