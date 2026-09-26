import { useState } from 'react'
import {
  ShoppingBag as Bag, Calendar, CheckCircle2, Circle, FileText, Folder, Globe, HardDrive, Mail, MessageSquare, Monitor, Pause, Play,
  Plus, Presentation, Sun, Table2, SquareUser as UserSquare, Users, Wrench, type LucideIcon,
} from 'lucide-react'
import type { Employee } from '../../shared/types'
import { AgentOrb, moodFor } from '../components/Orb'
import { Card, Chip, Eyebrow, ScreenHeader, Segmented, StatusDot, Switch, TextField } from '../components/ui'
import { alpha, hueFor, palette } from '../lib/theme'
import { relative } from '../lib/time'
import { go, hire, isPaused, patch, pause, pauseAll, resume, sel, selectEmployee, setTool, useStore, wake, type HireInput } from '../lib/store'

export const TOOL_ICONS: Record<string, LucideIcon> = {
  gmail: Mail, whatsapp: MessageSquare, telegram: MessageSquare, drive: HardDrive, docs: FileText, calendar: Calendar,
  web: Globe, sheet: Table2, records: UserSquare, odoo: Users, etsy: Bag, computer: Monitor, documents: Folder, presenton: Presentation,
}

export function TeamScreen() {
  const s = useStore()
  const [focusedId, setFocusedId] = useState<string | null>(null)
  const focused = s.employees.find((e) => e.id === focusedId) ?? s.employees[0]
  return (
    <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>
      <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column' }}>
        <ScreenHeader eyebrow="Team" title={`${s.employees.length} AI employee${s.employees.length === 1 ? '' : 's'}`}
          detail="Each one has a mission, a schedule, tools and limits. They share the company Brain."
          trailing={
            <div style={{ display: 'flex', gap: 8 }}>
              <button className="btn-ghost sm" onClick={() => void pauseAll()}><Pause size={13} />Pause all</button>
              <button className="btn-signal sm" onClick={() => useStore.setState({ showHire: true })}><Plus size={13} strokeWidth={2.6} />Hire</button>
            </div>
          } />
        <div className="scroll" style={{ flex: 1, padding: '0 24px 24px' }}>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(250px, 1fr))', gap: 14 }}>
            {s.employees.map((e) => <EmployeeTile key={e.id} employee={e} selected={focused?.id === e.id} onClick={() => setFocusedId(e.id)} />)}
          </div>
        </div>
      </div>
      {focused && (<><div className="divider-v" /><EmployeeDetail key={focused.id} employee={focused} /></>)}
    </div>
  )
}

function EmployeeTile({ employee, selected, onClick }: { employee: Employee; selected: boolean; onClick: () => void }) {
  const s = useStore()
  const waiting = sel.waiting(s).some((a) => a.employeeId === employee.id)
  const run = s.working[employee.id]
  const tint = hueFor(employee.id)
  const [hover, setHover] = useState(false)
  const status = waiting ? 'Needs you' : run?.active ? run.goal || 'Working' : isPaused(employee) ? 'Paused' : 'Ready'
  const dot = waiting ? palette.amber : run?.active ? palette.ice : isPaused(employee) ? palette.text3 : palette.mint
  return (
    <Card hl={selected || hover} radius={18} pad={18} onClick={onClick} onHover={setHover}
      style={{ display: 'flex', flexDirection: 'column', gap: 14, transform: hover ? 'scale(1.01)' : undefined, transition: 'transform .2s var(--snappy), background .2s',
        boxShadow: selected ? `inset 0 0 0 1px ${alpha(tint, 0.5)}` : undefined }}>
      <div style={{ display: 'flex', alignItems: 'flex-start' }}>
        <AgentOrb mood={moodFor(employee, run, waiting)} tint={tint} size={54} />
        <span style={{ flex: 1 }} />
        <Chip text={cap(employee.autonomyLevel ?? 'balanced')} />
      </div>
      <div>
        <div style={{ fontSize: 16, fontWeight: 600 }}>{employee.name}</div>
        <div className="t-caption" style={{ color: tint }}>{employee.role}</div>
      </div>
      <div className="t-callout c2 clamp2" style={{ minHeight: 36 }}>{employee.missionTitle || employee.mission}</div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        <StatusDot color={dot} pulsing={!!run?.active} size={5} />
        <span className="t-caption c3 ellipsis" style={{ flex: 1 }}>{status}</span>
        <span className="t-caption cf">{employee.toolIds?.length ?? 0} tools</span>
      </div>
    </Card>
  )
}

function EmployeeDetail({ employee }: { employee: Employee }) {
  const s = useStore()
  const tools = sel.tools(s, employee.id)
  const jobs = s.jobs.filter((j) => j.employeeId === employee.id)
  const field = (title: string, text?: string) => text ? (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
      <Eyebrow>{title}</Eyebrow>
      <div className="t-body selectable" style={{ color: 'rgba(244,245,247,0.88)' }}>{text}</div>
    </div>
  ) : null
  return (
    <div className="scroll fade-in" style={{ width: 380, flex: 'none', padding: '36px 22px 24px', display: 'flex', flexDirection: 'column', gap: 20, background: 'rgba(5,5,7,0.35)' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
        <AgentOrb mood={moodFor(employee, s.working[employee.id], false)} tint={hueFor(employee.id)} size={60} />
        <div>
          <div className="t-title">{employee.name}</div>
          <div className="t-callout c2">{employee.role}</div>
        </div>
      </div>
      <div style={{ display: 'flex', gap: 8 }}>
        <button className="btn-signal sm" onClick={() => { selectEmployee(employee); go('chat') }}><MessageSquare size={13} />Message</button>
        <button className="btn-ghost sm" onClick={() => void wake(employee.id)}><Sun size={13} />Wake</button>
        <button className="btn-ghost sm" onClick={() => void (isPaused(employee) ? resume(employee.id) : pause(employee.id))}>
          {isPaused(employee) ? <Play size={13} /> : <Pause size={13} />}{isPaused(employee) ? 'Resume' : 'Pause'}
        </button>
      </div>
      {field('Mission', employee.mission)}
      {field('What success looks like', employee.success)}
      {field('How they work', employee.personality)}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        <Eyebrow>Autonomy</Eyebrow>
        <Segmented value={employee.autonomyLevel ?? 'balanced'} onChange={(v) => void patch(employee.id, { autonomy: v })}
          options={[{ value: 'conservative', label: 'Careful' }, { value: 'balanced', label: 'Balanced' }, { value: 'autonomous', label: 'Bold' }]} />
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
        <Eyebrow>Tools</Eyebrow>
        {s.accountTools.map((tool) => {
          const on = !!employee.toolIds?.includes(tool.id)
          const detail = tools.find((t) => t.id === tool.id)
          const Icon = TOOL_ICONS[tool.id] ?? Wrench
          return (
            <div key={tool.id} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '3px 0' }}>
              <Icon size={15} color={on ? palette.ice : palette.text3} style={{ width: 18, flex: 'none' }} />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div className="t-callout">{tool.name}</div>
                {detail ? <div style={{ fontSize: 10.5, color: palette.text3 }}>read {detail.read} · write {detail.write}</div>
                  : !tool.connected ? <div style={{ fontSize: 10.5, color: palette.faint }}>Not connected</div> : null}
              </div>
              <Switch on={on} onChange={(v) => void setTool(tool.id, v, employee)} label={tool.name} />
            </div>
          )
        })}
      </div>
      {jobs.length > 0 && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          <Eyebrow>Schedule</Eyebrow>
          {jobs.map((j) => (
            <div key={j.id} style={{ display: 'flex', alignItems: 'center' }}>
              <div style={{ flex: 1 }}>
                <div className="t-callout">{j.title}</div>
                <div className="t-caption c3">{j.cadenceLabel || j.cadence}</div>
              </div>
              <span className="t-caption c3">{relative(j.nextRunAt)}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

const ROLES: [string, string, string][] = [
  ['Sales', 'Market & Sales', 'Find qualified buyers, keep the pipeline honest, follow up, and surface only the decisions that need me.'],
  ['Marketing', 'Marketing', 'Research the market, draft campaigns, and keep a brief ready before anyone asks.'],
  ['Assistant', 'Executive assistant', 'Keep the inbox, calendar and follow-ups from eating the week. Interrupt only when time or money is at stake.'],
  ['Operator', 'Operations', 'Work on my PC: keep files organised, prepare documents and run the routine desktop chores I hand over.'],
]

export function HireSheet() {
  const s = useStore()
  const [step, setStep] = useState(0)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [input, setInput] = useState<HireInput>({
    name: '', role: '', mission: '', success: '', personality: '', toolIds: ['records', 'web', 'documents'], autonomy: 'balanced', wakeCadence: 'off',
  })
  const up = (p: Partial<HireInput>) => setInput((i) => ({ ...i, ...p }))
  const close = () => useStore.setState({ showHire: false })
  const submit = async () => {
    setBusy(true); setError(null)
    try {
      const e = await hire(input)
      useStore.setState({ toast: `${e.name} joined your team.`, showHire: false, section: 'chat' })
    } catch (e) { setError((e as Error).message) } finally { setBusy(false) }
  }
  const ok = input.mission.trim().length >= 8 && !busy
  return (
    <div onClick={close} style={{ position: 'absolute', inset: 0, zIndex: 40, background: 'rgba(0,0,0,0.55)', display: 'grid', placeItems: 'center', backdropFilter: 'blur(6px)' }}>
      <div className="pop-in" onClick={(e) => e.stopPropagation()} style={{
        width: 620, borderRadius: 18, background: 'var(--panel)', boxShadow: 'inset 0 0 0 0.75px var(--hairline-strong), 0 30px 60px rgba(0,0,0,0.6)', overflow: 'hidden',
      }}>
        <div className="hairline-b" style={{ display: 'flex', alignItems: 'center', padding: 24 }}>
          <div style={{ flex: 1 }}>
            <Eyebrow color={palette.ice}>Hire · step {step + 1} of 2</Eyebrow>
            <div className="t-display" style={{ fontSize: 22, marginTop: 4 }}>{step === 0 ? 'What will they own?' : 'How should they work?'}</div>
          </div>
          <AgentOrb mood={busy ? 'working' : 'idle'} size={44} />
        </div>
        <div className="scroll" style={{ height: 400, padding: 24, display: 'flex', flexDirection: 'column', gap: 16 }}>
          {step === 0 ? (
            <>
              <Eyebrow>Start from a role</Eyebrow>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
                {ROLES.map(([title, role, mission]) => (
                  <Card key={title} radius={12} pad={12} hl={input.role === role}
                    onClick={() => up({ role, mission, toolIds: title === 'Operator' && !input.toolIds.includes('computer') ? [...input.toolIds, 'computer'] : input.toolIds })}>
                    <div className="t-headline">{title}</div>
                    <div className="t-caption c2 clamp2" style={{ marginTop: 4 }}>{mission}</div>
                  </Card>
                ))}
              </div>
              <Eyebrow>Name (optional)</Eyebrow>
              <TextField value={input.name} onChange={(v) => up({ name: v })} placeholder="We’ll pick one if you leave this empty" />
              <Eyebrow>Mission</Eyebrow>
              <label className="field" style={{ alignItems: 'flex-start' }}>
                <textarea rows={3} value={input.mission} onChange={(e) => up({ mission: e.target.value })} style={{ resize: 'none', lineHeight: 1.5 }} />
              </label>
              <Eyebrow>What success looks like</Eyebrow>
              <TextField value={input.success} onChange={(v) => up({ success: v })} placeholder="e.g. Three qualified meetings a week" />
            </>
          ) : (
            <>
              <Eyebrow>Autonomy</Eyebrow>
              <Segmented value={input.autonomy} onChange={(v) => up({ autonomy: v })}
                options={[{ value: 'conservative', label: 'Careful — ask first' }, { value: 'balanced', label: 'Balanced' }, { value: 'autonomous', label: 'Bold' }]} />
              <Eyebrow>Wakes up</Eyebrow>
              <Segmented value={input.wakeCadence} onChange={(v) => up({ wakeCadence: v })}
                options={[{ value: 'off', label: 'Only when asked' }, { value: 'daily_morning', label: 'Every morning' }, { value: '12h', label: 'Twice a day' }, { value: '1h', label: 'Every hour' }]} />
              <Eyebrow>Tools</Eyebrow>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(150px, 1fr))', gap: 8 }}>
                {s.accountTools.map((t) => {
                  const on = input.toolIds.includes(t.id)
                  return (
                    <button key={t.id} onClick={() => up({ toolIds: on ? input.toolIds.filter((x) => x !== t.id) : [...input.toolIds, t.id] })}
                      style={{ display: 'flex', alignItems: 'center', gap: 6, padding: 8, borderRadius: 8, background: on ? alpha(palette.ice, 0.08) : 'var(--field)' }}>
                      {on ? <CheckCircle2 size={14} color={palette.ice} /> : <Circle size={14} color={palette.text3} />}
                      <span className="t-callout ellipsis">{t.name}</span>
                    </button>
                  )
                })}
              </div>
              {input.toolIds.includes('computer') && (
                <div className="t-caption" style={{ color: palette.mint, display: 'flex', gap: 6 }}>
                  <Monitor size={13} />They can use this PC within the scopes you set in This PC. Every action shows on screen.
                </div>
              )}
              <Eyebrow>Personality (optional)</Eyebrow>
              <TextField value={input.personality} onChange={(v) => up({ personality: v })} placeholder="Direct, warm, brief" />
            </>
          )}
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: 20, boxShadow: 'inset 0 0.5px 0 var(--hairline)' }}>
          {error && <span className="t-caption" style={{ color: palette.coral }}>{error}</span>}
          <span style={{ flex: 1 }} />
          <button className="btn-ghost" onClick={() => (step === 0 ? close() : setStep(0))}>{step === 0 ? 'Cancel' : 'Back'}</button>
          <button className="btn-signal" disabled={!ok} onClick={() => (step === 0 ? setStep(1) : void submit())}>
            {step === 0 ? 'Continue' : busy ? 'Hiring…' : `Hire ${input.name || 'employee'}`}
          </button>
        </div>
      </div>
    </div>
  )
}

const cap = (x: string) => x[0].toUpperCase() + x.slice(1)
