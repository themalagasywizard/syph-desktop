import { useEffect, useState } from 'react'
import { ArrowRightCircle, BadgeCheck, Check, Lightbulb, ShieldAlert, Sparkles } from 'lucide-react'
import type { Approval } from '../../shared/types'
import { AgentOrb } from '../components/Orb'
import { Card, Chip, EmptyState, Eyebrow, KeyCap, Monogram, ScreenHeader, Spinner } from '../components/ui'
import { palette, statusColor } from '../lib/theme'
import { resolve, sel, useStore } from '../lib/store'

export function ApprovalsScreen() {
  const s = useStore()
  const waiting = sel.waiting(s)
  const decided = s.approvals.filter((a) => a.status !== 'waiting').slice(0, 30)
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [showDecided, setShowDecided] = useState(false)
  const current = waiting.find((a) => a.id === selectedId) ?? waiting[0]
  return (
    <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>
      <div style={{ width: 380, flex: 'none', display: 'flex', flexDirection: 'column' }}>
        <ScreenHeader eyebrow="Needs you" title={waiting.length ? `${waiting.length} decision${waiting.length === 1 ? '' : 's'} waiting` : 'All clear'}
          detail="Anything that sends, spends, deletes or acts on your PC waits here until you say so." />
        <div className="scroll" style={{ flex: 1, padding: '0 20px 20px', display: 'flex', flexDirection: 'column', gap: 8 }}>
          {waiting.map((a) => <ListRow key={a.id} approval={a} selected={current?.id === a.id} onClick={() => setSelectedId(a.id)} />)}
          {!waiting.length && <EmptyState icon={BadgeCheck} title="Nothing needs you" detail="Your team is working within the limits you set." style={{ height: 260 }} />}
          <button className="eyebrow" style={{ textAlign: 'left', marginTop: 18 }} onClick={() => setShowDecided(!showDecided)}>
            {showDecided ? '▾' : '▸'} Recently decided
          </button>
          {showDecided && decided.map((a) => <div key={a.id} style={{ opacity: 0.7 }}><ListRow approval={a} selected={false} /></div>)}
        </div>
      </div>
      <div className="divider-v" />
      <div className="scroll" style={{ flex: 1 }}>
        {current ? (
          <div key={current.id} className="fade-in" style={{ maxWidth: 720, margin: '0 auto', padding: 32 }}>
            <ApprovalCard approval={current} compact={false} />
          </div>
        ) : (
          <EmptyState icon={Sparkles} title="Inbox zero" detail="New requests appear here and as notifications." />
        )}
      </div>
    </div>
  )
}

function ListRow({ approval, selected, onClick }: { approval: Approval; selected: boolean; onClick?: () => void }) {
  const employee = useStore((s) => sel.employee(s, approval.employeeId))
  return (
    <button onClick={onClick} style={{
      textAlign: 'left', display: 'flex', gap: 12, padding: 12, borderRadius: 12,
      background: selected ? 'rgba(255,255,255,0.07)' : 'rgba(255,255,255,0.02)',
      boxShadow: `inset 0 0 0 0.75px ${selected ? 'rgba(227,165,95,0.5)' : 'var(--hairline)'}`,
    }}>
      {employee && <Monogram employee={employee} size={30} />}
      <div style={{ minWidth: 0, display: 'flex', flexDirection: 'column', gap: 3 }}>
        <div className="t-headline clamp2">{approval.title}</div>
        <div className="t-caption c2 clamp2">{approval.situation}</div>
        <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
          <span className="t-caption c3">{employee?.name}</span>
          {approval.status !== 'waiting' && <Chip text={approval.status[0].toUpperCase() + approval.status.slice(1)} color={statusColor(approval.status)} />}
        </div>
      </div>
    </button>
  )
}

/** A decision, with the context needed to make it and nothing else. */
export function ApprovalCard({ approval, compact }: { approval: Approval; compact: boolean }) {
  const employee = useStore((s) => sel.employee(s, approval.employeeId))
  const [busy, setBusy] = useState(false)
  const decide = async (ok: boolean) => { setBusy(true); await resolve(approval, ok); setBusy(false) }
  useEffect(() => {
    if (compact) return
    const onKey = (e: KeyboardEvent) => {
      if (!e.ctrlKey) return
      if (e.key === 'Enter') { e.preventDefault(); void decide(true) }
      if (e.key === 'Backspace' || e.key === 'Delete') { e.preventDefault(); void decide(false) }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  })
  const block = (title: string, text: string, Icon: typeof Lightbulb) => (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 5 }}>
      <span className="t-caption c3" style={{ display: 'flex', alignItems: 'center', gap: 6 }}><Icon size={12} />{title}</span>
      <span className="t-body selectable" style={{ color: 'rgba(244,245,247,0.9)' }}>{text}</span>
    </div>
  )
  return (
    <Card hl radius={16} pad={compact ? 14 : 22} className="fade-in"
      style={{ display: 'flex', flexDirection: 'column', gap: compact ? 12 : 20, boxShadow: 'inset 0 0 0 0.75px rgba(227,165,95,0.3)', opacity: busy ? 0.7 : 1 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        <AgentOrb mood="attention" tint={palette.amber} size={compact ? 28 : 40} />
        <div>
          <Eyebrow color={palette.amber}>{employee?.name ?? 'Employee'} needs your decision</Eyebrow>
          <div className={compact ? 't-headline' : 't-display'} style={{ fontSize: compact ? 14 : 22, marginTop: 2 }}>{approval.title}</div>
        </div>
      </div>
      {approval.situation && block('What happens', approval.situation, ArrowRightCircle)}
      {!compact && approval.recommendation && approval.recommendation !== approval.reason && block('Recommendation', approval.recommendation, Lightbulb)}
      {!compact && approval.risk && block('Risk', approval.risk, ShieldAlert)}
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <button className="btn-ghost" style={{ color: palette.coral }} disabled={busy} onClick={() => void decide(false)}>Decline</button>
        <span style={{ flex: 1 }} />
        {busy && <Spinner />}
        <button className="btn-signal" disabled={busy} onClick={() => void decide(true)}>
          <Check size={14} strokeWidth={2.6} />{approval.primaryAction || 'Approve'}
        </button>
      </div>
      {!compact && (
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <KeyCap k="Ctrl ↵" /><span className="t-caption c3">approve</span>
          <span style={{ width: 8 }} /><KeyCap k="Ctrl ⌫" /><span className="t-caption c3">decline</span>
        </div>
      )}
    </Card>
  )
}
