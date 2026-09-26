import { type CSSProperties, type ReactNode, useState } from 'react'
import type { LucideIcon } from 'lucide-react'
import type { Employee } from '../../shared/types'
import { alpha, hueFor, palette } from '../lib/theme'

export function Card({ children, className = '', style, hl, radius = 14, pad = 16, onClick, onHover }: {
  children: ReactNode; className?: string; style?: CSSProperties; hl?: boolean; radius?: number; pad?: number
  onClick?: () => void; onHover?: (hovering: boolean) => void
}) {
  return (
    <div className={`card ${hl ? 'hl' : ''} ${className}`} style={{ borderRadius: radius, padding: pad, ...style }} onClick={onClick}
      onMouseEnter={onHover && (() => onHover(true))} onMouseLeave={onHover && (() => onHover(false))}>
      {children}
    </div>
  )
}

export function Eyebrow({ children, color, style }: { children: ReactNode; color?: string; style?: CSSProperties }) {
  return <div className="eyebrow" style={{ color, ...style }}>{children}</div>
}

export function StatusDot({ color, pulsing, size = 7 }: { color: string; pulsing?: boolean; size?: number }) {
  const box = size * 2.6
  return (
    <span style={{ position: 'relative', width: box, height: box, display: 'inline-grid', placeItems: 'center', flex: 'none' }}>
      {pulsing && (
        <span style={{ position: 'absolute', width: box, height: box, borderRadius: '50%', background: alpha(color, 0.35), animation: 'pulse-ring 1.4s ease-out infinite' }} />
      )}
      <span style={{ width: size, height: size, borderRadius: '50%', background: color, boxShadow: pulsing ? `0 0 5px ${color}` : undefined }} />
    </span>
  )
}

export function Chip({ text, color = palette.text2, icon: Icon }: { text: string; color?: string; icon?: LucideIcon }) {
  return (
    <span className="chip" style={{ color, background: alpha(color, 0.12), boxShadow: `inset 0 0 0 0.5px ${alpha(color, 0.22)}` }}>
      {Icon && <Icon size={9} strokeWidth={3} />}
      {text}
    </span>
  )
}

export function KeyCap({ k }: { k: string }) {
  return <span className="keycap">{k}</span>
}

export function Monogram({ employee, size = 28 }: { employee: Employee; size?: number }) {
  const tint = hueFor(employee.id)
  return (
    <span style={{
      width: size, height: size, borderRadius: '50%', display: 'inline-grid', placeItems: 'center', flex: 'none',
      fontSize: size * 0.42, fontWeight: 600, color: tint, background: alpha(tint, 0.13), boxShadow: `inset 0 0 0 0.75px ${alpha(tint, 0.35)}`,
    }}>
      {(employee.name || '?').slice(0, 1).toUpperCase()}
    </span>
  )
}

export function IconButton({ icon: Icon, label, onClick, size = 28, tint, active }: {
  icon: LucideIcon; label: string; onClick?: () => void; size?: number; tint?: string; active?: boolean
}) {
  return (
    <button className="icon-btn no-drag" title={label} aria-label={label} onClick={onClick}
      style={{ width: size, height: size, color: active ? palette.ice : tint }}>
      <Icon size={size * 0.5} strokeWidth={1.75} />
    </button>
  )
}

export function TextField({ value, onChange, placeholder, secure, icon: Icon, onSubmit, autoFocus }: {
  value: string; onChange: (v: string) => void; placeholder: string; secure?: boolean; icon?: LucideIcon; onSubmit?: () => void; autoFocus?: boolean
}) {
  return (
    <label className="field">
      {Icon && <Icon size={14} />}
      <input type={secure ? 'password' : 'text'} value={value} placeholder={placeholder} autoFocus={autoFocus}
        onChange={(e) => onChange(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') onSubmit?.() }} spellCheck={false} />
    </label>
  )
}

export function Segmented<T extends string>({ value, options, onChange }: { value: T; options: { value: T; label: string }[]; onChange: (v: T) => void }) {
  return (
    <div className="segmented">
      {options.map((o) => (
        <button key={o.value} className={o.value === value ? 'on' : ''} onClick={() => onChange(o.value)}>{o.label}</button>
      ))}
    </div>
  )
}

export function Switch({ on, onChange, label }: { on: boolean; onChange: (v: boolean) => void; label?: string }) {
  return <button role="switch" aria-checked={on} aria-label={label} className={`switch ${on ? 'on' : ''}`} onClick={() => onChange(!on)} />
}

export function EmptyState({ icon: Icon, title, detail, style }: { icon: LucideIcon; title: string; detail: string; style?: CSSProperties }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 12, height: '100%', ...style }}>
      <div style={{ width: 64, height: 64, borderRadius: '50%', boxShadow: 'inset 0 0 0 0.75px var(--hairline-strong)', display: 'grid', placeItems: 'center' }}>
        <Icon size={24} strokeWidth={1.2} color={palette.ice} />
      </div>
      <div className="t-headline">{title}</div>
      <div className="t-callout c2" style={{ maxWidth: 320, textAlign: 'center' }}>{detail}</div>
    </div>
  )
}

export function ScreenHeader({ eyebrow, title, detail, trailing }: { eyebrow: string; title: string; detail?: string; trailing?: ReactNode }) {
  return (
    <div style={{ display: 'flex', alignItems: 'flex-end', gap: 16, padding: '40px 24px 20px' }}>
      <div style={{ flex: 1, minWidth: 0 }}>
        <Eyebrow color={palette.ice}>{eyebrow}</Eyebrow>
        <div className="t-display" style={{ fontSize: 26, marginTop: 6 }}>{title}</div>
        {detail && <div className="t-callout c2" style={{ marginTop: 6 }}>{detail}</div>}
      </div>
      {trailing}
    </div>
  )
}

export function Hover({ children, render }: { children?: ReactNode; render: (hovering: boolean) => ReactNode }) {
  const [hovering, setHovering] = useState(false)
  return <div onMouseEnter={() => setHovering(true)} onMouseLeave={() => setHovering(false)}>{render(hovering)}{children}</div>
}

export function Spinner({ size = 14, color = palette.text }: { size?: number; color?: string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" style={{ animation: 'spin 0.9s linear infinite' }}>
      <style>{'@keyframes spin{to{transform:rotate(360deg)}}'}</style>
      <circle cx="12" cy="12" r="9" fill="none" stroke={alpha(color, 0.25)} strokeWidth="3" />
      <path d="M21 12a9 9 0 0 0-9-9" fill="none" stroke={color} strokeWidth="3" strokeLinecap="round" />
    </svg>
  )
}
