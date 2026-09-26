import { useEffect, useRef, useState } from 'react'
import {
  Archive, ArrowUp, Brain, Calendar, CircleDashed, Clock, Copy, FileText, Globe, Mail, MessageSquare, Monitor, Pause,
  PanelRight, Play, Plus, ShoppingBag, SquarePen, Sun, Table2, UserPlus, Users, ChevronDown,
} from 'lucide-react'
import type { Approval, ChatMessage, Employee, WorkingRun, WorkingStep } from '../../shared/types'
import { AgentOrb, moodFor } from '../components/Orb'
import { CrmChip, FileCardView, Markdown, MailCardView, parseMessage } from '../components/Message'
import { Card, Chip, EmptyState, IconButton, Monogram, StatusDot } from '../components/ui'
import { hueFor, palette, statusColor } from '../lib/theme'
import { clock, relative } from '../lib/time'
import {
  isPaused, isUser, newThread, pause, resume, sel, selectEmployee, selectThread, send, stop, useStore, wake,
} from '../lib/store'
import { ApprovalCard } from './Approvals'

export function ChatScreen() {
  const employee = useStore((s) => sel.selectedEmployee(s))
  const [showThreads, setShowThreads] = useState(true)
  if (!employee) {
    return (
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 18 }}>
        <EmptyState icon={UserPlus} title="Hire your first employee" style={{ height: 'auto' }}
          detail="Give them a mission, the tools they need and the limits you want. They start working right away." />
        <button className="btn-signal" onClick={() => useStore.setState({ showHire: true })}>Hire an employee</button>
      </div>
    )
  }
  return (
    <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>
      <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column' }}>
        <ChatHeader employee={employee} showThreads={showThreads} toggle={() => setShowThreads(!showThreads)} />
        <MessageStream employee={employee} />
        <Composer employee={employee} />
      </div>
      {showThreads && (<><div className="divider-v" /><ThreadInspector employee={employee} /></>)}
    </div>
  )
}

function ChatHeader({ employee, showThreads, toggle }: { employee: Employee; showThreads: boolean; toggle: () => void }) {
  const s = useStore()
  const run = s.working[employee.id]
  const waiting = sel.waiting(s).some((a) => a.employeeId === employee.id)
  const [menu, setMenu] = useState(false)
  const text = isPaused(employee) ? 'Paused' : run?.active ? cap(run.phase || 'Working') : 'Ready'
  const color = isPaused(employee) ? palette.text3 : waiting ? palette.amber : run?.active ? palette.ice : palette.mint
  const status = [text, color]
  return (
    <div className="hairline-b" style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '30px 22px 14px' }}>
      <AgentOrb mood={moodFor(employee, run, waiting)} tint={hueFor(employee.id)} size={42} />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <span style={{ fontSize: 17, fontWeight: 600 }}>{employee.name}</span>
          <Chip text={status[0]} color={status[1]} />
        </div>
        <div className="t-callout c2 ellipsis">{employee.missionTitle || employee.role}</div>
      </div>
      <div style={{ position: 'relative' }}>
        <button className="icon-btn" style={{ width: 40, height: 28, gap: 2, display: 'inline-flex' }} title="Switch employee" onClick={() => setMenu(!menu)}>
          <Users size={14} /><ChevronDown size={10} />
        </button>
        {menu && (
          <div className="pop-in" onMouseLeave={() => setMenu(false)} style={{
            position: 'absolute', right: 0, top: 32, zIndex: 20, minWidth: 180, padding: 6, borderRadius: 10,
            background: 'rgba(20,23,32,0.98)', boxShadow: 'inset 0 0 0 0.75px var(--hairline-strong), 0 12px 30px rgba(0,0,0,0.5)',
          }}>
            {s.employees.map((e) => (
              <button key={e.id} className="menu-item" onClick={() => { selectEmployee(e); setMenu(false) }}
                style={{ width: '100%', display: 'flex', alignItems: 'center', gap: 8, padding: '6px 8px', borderRadius: 6 }}>
                <Monogram employee={e} size={20} /><span className="t-callout">{e.name}</span>
              </button>
            ))}
            <div style={{ height: 0.5, background: 'var(--hairline)', margin: '4px 0' }} />
            <button className="menu-item t-callout" onClick={() => { useStore.setState({ showHire: true }); setMenu(false) }}
              style={{ width: '100%', textAlign: 'left', padding: '6px 8px', borderRadius: 6 }}>Hire…</button>
            <style>{'.menu-item:hover{background:rgba(255,255,255,0.07)}'}</style>
          </div>
        )}
      </div>
      <IconButton icon={Sun} label="Wake up now" onClick={() => void wake(employee.id)} />
      <IconButton icon={isPaused(employee) ? Play : Pause} label={isPaused(employee) ? 'Resume' : 'Pause'}
        onClick={() => void (isPaused(employee) ? resume(employee.id) : pause(employee.id))} />
      <IconButton icon={SquarePen} label="New conversation" onClick={() => void newThread(employee.id)} />
      <IconButton icon={PanelRight} label="Threads & activity" active={showThreads} onClick={toggle} />
    </div>
  )
}

function MessageStream({ employee }: { employee: Employee }) {
  const s = useStore()
  const messages = sel.messages(s, employee.id)
  const approvals = sel.waiting(s).filter((a) => a.employeeId === employee.id)
  const run = s.working[employee.id]
  const bottom = useRef<HTMLDivElement>(null)
  useEffect(() => { bottom.current?.scrollIntoView({ behavior: 'smooth', block: 'end' }) }, [messages.length, run?.steps.length, employee.id])
  return (
    <div className="scroll" style={{ flex: 1 }}>
      <div style={{ maxWidth: 860, margin: '0 auto', padding: '22px 28px', display: 'flex', flexDirection: 'column', gap: 18 }}>
        {messages.length === 0 && <Greeting employee={employee} />}
        {messages.map((m) => <MessageRow key={m.id} message={m} employee={employee} />)}
        {run?.active && <WorkingCard run={run} employee={employee} />}
        {approvals.map((a: Approval) => <ApprovalCard key={a.id} approval={a} compact />)}
        <div ref={bottom} style={{ height: 8 }} />
      </div>
    </div>
  )
}

function Greeting({ employee }: { employee: Employee }) {
  const suggestions = ['Brief me on today', 'What needs my decision?',
    employee.toolIds?.includes('computer') ? 'Look at my screen and tidy my Desktop' : 'Research our top 3 competitors']
  return (
    <div className="fade-in" style={{ paddingTop: 60, display: 'flex', flexDirection: 'column', gap: 16 }}>
      <div className="t-display" style={{ fontSize: 26 }}>What should {employee.name} do next?</div>
      <div className="t-body c2 clamp3">{employee.mission}</div>
      <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
        {suggestions.map((t) => (
          <button key={t} className="btn-ghost sm" onClick={() => useStore.setState((st) => ({ drafts: { ...st.drafts, [employee.id]: t } }))}>{t}</button>
        ))}
      </div>
    </div>
  )
}

function MessageRow({ message, employee }: { message: ChatMessage; employee: Employee }) {
  const [hover, setHover] = useState(false)
  if (isUser(message)) {
    return (
      <div style={{ display: 'flex', justifyContent: 'flex-end', paddingLeft: 120 }}>
        <div className="selectable t-body" style={{
          padding: '10px 14px', borderRadius: 16, whiteSpace: 'pre-wrap', opacity: message.id.startsWith('local-') ? 0.6 : 1,
          background: 'linear-gradient(135deg, rgba(74,99,217,0.45), rgba(74,99,217,0.25))', boxShadow: 'inset 0 0 0 0.75px rgba(157,184,255,0.25)',
        }}>{message.body}</div>
      </div>
    )
  }
  const parsed = parseMessage(message.body)
  return (
    <div style={{ display: 'flex', gap: 12 }} onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}>
      <Monogram employee={employee} size={26} />
      <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 10 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, height: 22 }}>
          <span style={{ fontSize: 12, fontWeight: 600 }}>{employee.name}</span>
          <span className="t-caption c3">{clock(message.at)}</span>
          <span style={{ flex: 1 }} />
          {hover && <IconButton icon={Copy} label="Copy" size={22} onClick={() => void navigator.clipboard.writeText(parsed.prose)} />}
        </div>
        {parsed.prose && <Markdown source={parsed.prose} />}
        {parsed.files.map((f) => <FileCardView key={f.title + f.files.map((x) => x.href).join()} card={f} />)}
        {parsed.mail && <MailCardView mail={parsed.mail} />}
        {parsed.crm && <div><CrmChip title={parsed.crm} /></div>}
      </div>
    </div>
  )
}

export function WorkingCard({ run, employee }: { run: WorkingRun; employee: Employee }) {
  return (
    <Card hl radius={14} pad={14} className="fade-in" style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <AgentOrb mood="working" tint={hueFor(employee.id)} size={26} />
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 12.5, fontWeight: 600 }}>{cap(run.phase || 'Working')}</div>
          <div className="t-caption c3 ellipsis">{run.goal}</div>
        </div>
        <button className="btn-ghost sm" style={{ color: palette.coral }} onClick={() => void stop(employee.id)}>Stop</button>
      </div>
      {run.steps.length > 0 && (
        <div>{run.steps.map((step, i) => <StepRow key={i} step={step} last={i === run.steps.length - 1} />)}</div>
      )}
    </Card>
  )
}

const STEP_ICONS: Record<string, typeof Globe> = {
  computer: Monitor, web: Globe, gmail: Mail, 'local.draft_message': Mail, calendar: Calendar, documents: FileText, docs: FileText,
  drive: FileText, 'odoo.crm': Users, memory: Brain, etsy: ShoppingBag, sheet: Table2, schedule: Clock, 'channel.message': MessageSquare,
}

function StepRow({ step, last }: { step: WorkingStep; last: boolean }) {
  const Icon = STEP_ICONS[step.tool] ?? CircleDashed
  return (
    <div style={{ display: 'flex', gap: 10 }}>
      <div style={{ width: 16, display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
        <StatusDot color={statusColor(step.status)} pulsing={step.status === 'running' || step.status === 'executing'} size={6} />
        {!last && <div style={{ width: 0.75, flex: 1, background: 'var(--hairline-strong)' }} />}
      </div>
      <div style={{ paddingBottom: 10, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <Icon size={11} color={palette.text3} />
          <span className="t-callout">{step.label || `${step.tool} · ${step.operation}`}</span>
        </div>
        {step.summary && <div className="t-caption c2 clamp3" style={{ marginTop: 2 }}>{step.summary}</div>}
      </div>
    </div>
  )
}

function Composer({ employee }: { employee: Employee }) {
  const s = useStore()
  const busy = !!s.working[employee.id]?.active
  const text = s.drafts[employee.id] ?? ''
  const [focused, setFocused] = useState(false)
  const ref = useRef<HTMLTextAreaElement>(null)
  const setText = (v: string) => useStore.setState((st) => ({ drafts: { ...st.drafts, [employee.id]: v } }))
  useEffect(() => {
    const el = ref.current
    if (!el) return
    el.style.height = 'auto'
    el.style.height = `${Math.min(el.scrollHeight, 150)}px`
  }, [text])
  useEffect(() => { ref.current?.focus() }, [employee.id])
  const submit = () => {
    if (!text.trim()) return
    setText('')
    void send(text, employee.id)
  }
  const empty = !text.trim()
  return (
    <div style={{ maxWidth: 860, width: '100%', margin: '0 auto', padding: '6px 28px 18px' }}>
      <div style={{
        display: 'flex', alignItems: 'flex-end', gap: 10, padding: 12, borderRadius: 18, background: 'rgba(14,16,21,0.9)',
        boxShadow: focused ? 'inset 0 0 0 1px rgba(157,184,255,0.45), 0 0 18px rgba(157,184,255,0.18)' : 'inset 0 0 0 0.75px var(--hairline-strong)',
        transition: 'box-shadow .2s var(--snappy)',
      }}>
        <textarea ref={ref} rows={1} value={text} onChange={(e) => setText(e.target.value)}
          onFocus={() => setFocused(true)} onBlur={() => setFocused(false)}
          onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); submit() } }}
          placeholder={busy ? `${employee.name} is working — you can queue the next thing after.` : `Instruct ${employee.name}…`}
          style={{ flex: 1, resize: 'none', border: 0, outline: 0, background: 'transparent', color: palette.text, fontSize: 13.5, lineHeight: 1.5, padding: '5px 4px', maxHeight: 150, userSelect: 'text' }} />
        <button onClick={submit} disabled={empty || s.isSending} title="Send (Enter)" style={{
          width: 30, height: 30, borderRadius: '50%', display: 'grid', placeItems: 'center', flex: 'none',
          background: empty ? palette.faint : palette.text, color: palette.void, transition: 'background .2s',
        }}>
          <ArrowUp size={15} strokeWidth={2.6} />
        </button>
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '8px 6px 0' }}>
        {sel.tools(s, employee.id).slice(0, 6).map((t) => (
          <span key={t.id} style={{ display: 'flex', alignItems: 'center', gap: 4, fontSize: 10.5, color: palette.text3 }}>
            <span style={{ width: 5, height: 5, borderRadius: '50%', background: t.connected ? palette.mint : palette.faint }} />{t.name}
          </span>
        ))}
        <span style={{ flex: 1 }} />
        <span style={{ fontSize: 10.5, color: palette.faint }}>Enter send · Shift+Enter new line</span>
      </div>
    </div>
  )
}

function ThreadInspector({ employee }: { employee: Employee }) {
  const s = useStore()
  const threads = sel.threads(s, employee.id)
  const current = sel.thread(s, employee.id)
  const recent = s.activity.filter((a) => a.employeeId === employee.id).slice(0, 12)
  return (
    <div className="scroll" style={{ width: 272, flex: 'none', padding: '36px 16px 20px', background: 'rgba(5,5,7,0.35)', display: 'flex', flexDirection: 'column', gap: 8 }}>
      <div style={{ display: 'flex', alignItems: 'center' }}>
        <div className="eyebrow" style={{ flex: 1 }}>Conversations</div>
        <IconButton icon={Plus} label="New conversation" size={22} onClick={() => void newThread(employee.id)} />
      </div>
      {threads.map((t) => (
        <button key={t.id} onClick={() => void selectThread(t)} className="side-row" style={{
          textAlign: 'left', padding: 10, borderRadius: 10, background: current?.id === t.id ? 'rgba(255,255,255,0.07)' : undefined,
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <span className="t-callout ellipsis" style={{ flex: 1 }}>{t.title}</span>
            {t.status === 'archived' && <Archive size={11} color={palette.text3} />}
          </div>
          <div className="t-caption c3">{t.messageCount} messages · {relative(t.lastMessageAt ?? t.createdAt)}</div>
        </button>
      ))}
      {threads.length === 0 && <div className="t-caption c3">No conversations yet.</div>}
      <div className="eyebrow" style={{ marginTop: 18 }}>Recent activity</div>
      {recent.map((a) => (
        <div key={a.id} style={{ display: 'flex', gap: 8 }}>
          <span style={{ width: 5, height: 5, borderRadius: '50%', background: statusColor(a.kind), marginTop: 7, flex: 'none' }} />
          <div>
            <div className="t-callout clamp2">{a.title}</div>
            <div className="t-caption c3">{relative(a.at)}</div>
          </div>
        </div>
      ))}
    </div>
  )
}

const cap = (s: string) => (s ? s[0].toUpperCase() + s.slice(1) : s)
