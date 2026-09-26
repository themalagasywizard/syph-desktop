import { useEffect, useMemo, useRef, useState } from 'react'
import {
  CheckCircle2, Hand, PauseCircle, Send, Square, UserPlus, User, type LucideIcon,
} from 'lucide-react'
import type { ConsentDecision, ConsentRequest, OverlayState } from '../../shared/types'
import { AgentOrb } from '../components/Orb'
import { KeyCap, Monogram } from '../components/ui'
import { syph } from '../lib/bridge'
import { hueFor, palette } from '../lib/theme'
import { launch, pauseAll, refresh, sel, send, useStore, type Section } from '../lib/store'
import { SCOPE_META } from '../screens/Computer'
import { SECTION_META } from '../screens/Shell'

const glass = {
  background: 'linear-gradient(to bottom, rgba(16,18,26,0.96), rgba(7,7,10,0.97))',
  backdropFilter: 'blur(28px) saturate(1.4)',
} as const

// ------------------------------------------------------------------ command bar

interface BarAction { id: string; icon: LucideIcon; title: string; detail: string; perform: () => void }

/** Alt+Space from any app: tell an employee what to do without leaving what you're doing. */
export function CommandBar() {
  const s = useStore()
  const [text, setText] = useState('')
  const [targetId, setTargetId] = useState<string | null>(null)
  const [sent, setSent] = useState<string | null>(null)
  const input = useRef<HTMLInputElement>(null)
  const target = sel.employee(s, targetId) ?? sel.selectedEmployee(s)
  const close = () => void syph.hideCommandBar()

  useEffect(() => {
    void launch()
    void syph.bridgeState().then((b) => useStore.setState({ bridge: b }))
    const offBridge = syph.on('bridge', (b) => useStore.setState({ bridge: b }))
    const off = syph.on('commandbar-opened', () => {
      setSent(null); setText(''); setTargetId(null)
      const st = useStore.getState()
      if (!st.demo) void (st.phase === 'ready' ? refresh() : launch())
      setTimeout(() => input.current?.focus(), 30)
    })
    return () => { off(); offBridge() }
  }, [])

  const cycle = () => {
    if (!s.employees.length) return
    const i = s.employees.findIndex((e) => e.id === target?.id)
    setTargetId(s.employees[(i + 1) % s.employees.length].id)
  }
  const submit = async (openAfter: boolean) => {
    const body = text.trim()
    if (!target || !body) return
    setText('')
    if (await send(body, target.id)) {
      setSent(`Sent to ${target.name}. They’re on it.`)
      if (openAfter) { void syph.showMain('chat'); close() } else setTimeout(close, 1100)
    } else setText(body)
  }

  const actions = useMemo<BarAction[]>(() => {
    const q = text.toLowerCase().trim()
    const jumps: BarAction[] = (Object.keys(SECTION_META) as Section[]).map((x) => ({
      id: `go-${x}`, icon: SECTION_META[x].icon, title: `Go to ${SECTION_META[x].title}`, detail: '', perform: () => { void syph.showMain(x); close() },
    }))
    const on = !!s.bridge?.policy.controlEnabled
    const extras: BarAction[] = [
      { id: 'hire', icon: UserPlus, title: 'Hire an employee', detail: '', perform: () => { void syph.showMain('team'); close() } },
      { id: 'pause', icon: PauseCircle, title: 'Pause all employees', detail: '', perform: () => { void pauseAll(); close() } },
      { id: 'stop', icon: Hand, title: on ? 'Stop computer control' : 'Allow computer control', detail: '', perform: () => { void (on ? syph.emergencyStop() : syph.setControl(true)); close() } },
    ]
    const people: BarAction[] = s.employees.map((e) => ({ id: `emp-${e.id}`, icon: User, title: `Talk to ${e.name}`, detail: e.role, perform: () => setTargetId(e.id) }))
    if (!q) return [...(sel.waiting(s).length ? [jumps[2]] : []), ...extras, ...people.slice(0, 3)]
    const list: BarAction[] = target ? [{ id: 'send', icon: Send, title: `Send to ${target.name}`, detail: text, perform: () => void submit(false) }] : []
    return [...list, ...[...jumps, ...extras, ...people].filter((a) => a.title.toLowerCase().includes(q) || a.detail.toLowerCase().includes(q)).slice(0, 5)]
  }, [text, s.employees, s.bridge, target?.id, s.approvals]) // eslint-disable-line react-hooks/exhaustive-deps

  const hint = (k: string, l: string) => <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}><KeyCap k={k} /><span className="t-caption c3">{l}</span></span>
  return (
    <div style={{ height: '100%', padding: 10 }}>
      <div className="pop-in" onKeyDown={(e) => {
        if (e.key === 'Escape') close()
        if (e.key === 'Tab') { e.preventDefault(); cycle() }
        if (e.key === 'Enter' && e.ctrlKey) { e.preventDefault(); void submit(true) }
      }} style={{
        height: '100%', display: 'flex', flexDirection: 'column', borderRadius: 22, overflow: 'hidden', ...glass,
        boxShadow: 'inset 0 0 0 1px rgba(157,184,255,0.3), 0 20px 50px rgba(0,0,0,0.55)',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '18px 20px' }}>
          <AgentOrb mood={s.isSending ? 'working' : 'idle'} tint={target ? hueFor(target.id) : palette.ice} size={34} />
          <input ref={input} autoFocus value={text} onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter' && !e.ctrlKey) void submit(false) }}
            placeholder={target ? `Tell ${target.name} what to do…` : 'Ask your team…'}
            style={{ flex: 1, border: 0, outline: 0, background: 'transparent', color: palette.text, fontSize: 21, userSelect: 'text' }} />
          {target && (
            <button onClick={cycle} title="Tab to switch employee" style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '5px 8px', borderRadius: 999, background: 'rgba(255,255,255,0.06)' }}>
              <Monogram employee={target} size={20} /><span className="t-callout">{target.name}</span><KeyCap k="Tab" />
            </button>
          )}
        </div>
        <div style={{ height: 0.5, background: 'var(--hairline)' }} />
        <div className="scroll" style={{ flex: 1, padding: 8 }}>
          {sent ? (
            <div className="fade-in" style={{ display: 'flex', alignItems: 'center', gap: 10, padding: 12 }}>
              <CheckCircle2 size={16} color={palette.mint} /><span className="t-callout">{sent}</span>
            </div>
          ) : actions.map((a) => (
            <button key={a.id} className="bar-row" onClick={a.perform} style={{ width: '100%', display: 'flex', alignItems: 'center', gap: 12, padding: 8, borderRadius: 10, textAlign: 'left' }}>
              <span style={{ width: 28, height: 28, borderRadius: 7, display: 'grid', placeItems: 'center', background: 'rgba(157,184,255,0.1)', flex: 'none' }}>
                <a.icon size={14} color={palette.ice} />
              </span>
              <div style={{ minWidth: 0 }}>
                <div className="t-callout">{a.title}</div>
                {a.detail && <div className="t-caption c3 ellipsis">{a.detail}</div>}
              </div>
            </button>
          ))}
          <style>{'.bar-row:hover{background:rgba(255,255,255,0.06)}'}</style>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '10px 18px', background: 'rgba(0,0,0,0.2)' }}>
          {hint('Enter', 'send')}{hint('Ctrl Enter', 'send & open')}{hint('Tab', 'switch employee')}{hint('Esc', 'close')}
          <span style={{ flex: 1 }} />
          {sel.waiting(s).length > 0 && <span className="t-caption" style={{ color: palette.amber }}>{sel.waiting(s).length} waiting on you</span>}
        </div>
      </div>
    </div>
  )
}

// ------------------------------------------------------------------ consent

export function ConsentPanel() {
  const [request, setRequest] = useState<ConsentRequest | null>(null)
  const [now, setNow] = useState(Date.now())
  useEffect(() => syph.on('consent', (r: ConsentRequest | null) => setRequest(r)), [])
  useEffect(() => { const t = setInterval(() => setNow(Date.now()), 500); return () => clearInterval(t) }, [])
  if (!request) return null
  const decide = (d: ConsentDecision) => { void syph.consentDecide(request.id, d); setRequest(null) }
  const meta = SCOPE_META[request.scope]
  return (
    <div style={{ padding: 12 }}>
      <div className="pop-in" onKeyDown={(e) => { if (e.key === 'Escape') decide('deny') }} style={{
        display: 'flex', flexDirection: 'column', gap: 14, padding: 18, borderRadius: 20, ...glass,
        boxShadow: 'inset 0 0 0 1px rgba(227,165,95,0.45), 0 24px 48px rgba(0,0,0,0.5)',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <AgentOrb mood="attention" tint={palette.amber} size={38} />
          <div style={{ flex: 1, minWidth: 0 }}>
            <div className="t-caption c2">{request.employee} wants to</div>
            <div style={{ fontSize: 15, fontWeight: 600 }} className="clamp2">{request.headline}</div>
          </div>
          <span className="t-mono c3">{Math.max(0, Math.round((request.deadline - now) / 1000))}s</span>
        </div>
        {request.detail && (
          <div className="t-mono selectable" style={{ maxHeight: 90, overflowY: 'auto', padding: 10, borderRadius: 10, background: 'rgba(0,0,0,0.4)', boxShadow: 'inset 0 0 0 0.75px var(--hairline)', whiteSpace: 'pre-wrap', wordBreak: 'break-word', color: 'rgba(244,245,247,0.9)' }}>
            {request.detail}
          </div>
        )}
        <div className="t-caption c3" style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          {meta && <meta.icon size={12} />}Scope: {meta?.title ?? request.scope}
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          <button className="btn-ghost" style={{ color: palette.coral }} onClick={() => decide('deny')}>Decline</button>
          <span style={{ flex: 1 }} />
          <button className="btn-ghost" onClick={() => decide('always')}>Always allow</button>
          <button className="btn-signal" autoFocus onClick={() => decide('once')}>Allow once</button>
        </div>
      </div>
    </div>
  )
}

// ------------------------------------------------------------------ driving overlay

function useOverlay() {
  const [state, setState] = useState<OverlayState>({ visible: false, employee: '', activity: '', tint: palette.ice })
  useEffect(() => syph.on('overlay', (s: OverlayState) => setState(s)), [])
  return state
}

/** Click-through edge glow in the driving employee's colour. */
export function Glow() {
  const o = useOverlay()
  return (
    <div style={{ position: 'fixed', inset: 0, pointerEvents: 'none', opacity: o.visible ? 1 : 0, transition: 'opacity .45s' }}>
      <style>{`@keyframes glow-spin{to{--a:360deg}}@property --a{syntax:'<angle>';inherits:false;initial-value:0deg}
        .glow-ring{position:absolute;inset:2px;border-radius:14px;padding:3px;background:conic-gradient(from var(--a),${o.tint},${palette.mint},${palette.violet},${o.tint});
        -webkit-mask:linear-gradient(#000 0 0) content-box,linear-gradient(#000 0 0);-webkit-mask-composite:xor;mask-composite:exclude;animation:glow-spin 9s linear infinite}`}</style>
      <div className="glow-ring" style={{ filter: 'blur(10px)', opacity: 0.9 }} />
      <div className="glow-ring" style={{ padding: 1.5, opacity: 0.85 }} />
    </div>
  )
}

/** Who is driving, what they're doing, and a Stop button. */
export function Pill() {
  const o = useOverlay()
  return (
    <div style={{ height: '100%', display: 'grid', placeItems: 'center' }}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 12, height: 48, width: 516, padding: '0 12px 0 10px', borderRadius: 999, ...glass,
        boxShadow: `inset 0 0 0 0.8px ${o.tint.replace(')', ' / 0.5)')}, 0 4px 18px ${o.tint.replace(')', ' / 0.35)')}`,
        transform: o.visible ? 'none' : 'scale(0.9)', opacity: o.visible ? 1 : 0, transition: 'all .45s var(--snappy)',
      }}>
        <AgentOrb mood="working" tint={o.tint} size={30} />
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 12.5, fontWeight: 600 }}>{o.employee} is using your PC</div>
          <div className="t-caption c2 ellipsis">{o.activity}</div>
        </div>
        <button className="btn-ghost sm" style={{ color: palette.coral }} title="Stop and switch computer control off" onClick={() => void syph.overlayStop()}>
          <Square size={10} fill={palette.coral} />Stop
        </button>
      </div>
    </div>
  )
}
