import { type ReactNode } from 'react'
import { FileText, Mail, Users } from 'lucide-react'
import { syph } from '../lib/bridge'
import { palette, statusColor } from '../lib/theme'
import { Card, Chip } from './ui'

interface FileCard { title: string; meta: string; files: { name: string; kind: string; href: string }[] }
interface MailCard { to: string; subject: string; body: string; status: string }
export interface Parsed { prose: string; files: FileCard[]; mail?: MailCard; crm?: string }

/** Same contract as web and iPhone: strip think tags, lift [[file]]/[[mail]]/[[crm]] into cards. */
export function parseMessage(raw: string): Parsed {
  let text = raw
    .replace(/<think>[\s\S]*?<\/think>/gi, '')
    .replace(/<reasoning>[\s\S]*?<\/reasoning>/gi, '')
    .replace(/<think\b[^>]*>[\s\S]*$/i, '')
  const parsed: Parsed = { prose: '', files: [] }
  const blocks = (tag: string) => {
    const found: Record<string, any>[] = []
    text = text.replace(new RegExp(`\\[\\[${tag}\\]\\]([\\s\\S]*?)\\[\\[/${tag}\\]\\]`, 'g'), (_m, inner: string) => {
      try { found.push(JSON.parse(inner)) } catch { /* malformed */ }
      return ''
    })
    return found
  }
  for (const o of blocks('file')) {
    parsed.files.push({
      title: o.title ?? 'File', meta: o.meta ?? '',
      files: (o.files ?? []).map((f: any) => ({ name: f.name ?? f.kind ?? 'file', kind: f.kind ?? '', href: f.href ?? '' })),
    })
  }
  for (const o of blocks('mail')) {
    const name = o.to_name ?? o.toName ?? '', email = o.to_email ?? o.toEmail ?? ''
    parsed.mail = { to: [name, email ? `<${email}>` : ''].filter(Boolean).join(' '), subject: o.subject ?? '', body: o.body ?? '', status: o.status ?? 'draft' }
  }
  for (const o of blocks('crm')) parsed.crm = o.title ?? 'CRM update'
  parsed.prose = text.trim()
  return parsed
}

type Block =
  | { k: 'h'; level: number; text: string } | { k: 'p'; text: string } | { k: 'li'; text: string; depth: number }
  | { k: 'ol'; n: string; text: string } | { k: 'quote'; text: string } | { k: 'code'; text: string } | { k: 'hr' }

function blocksOf(source: string): Block[] {
  const out: Block[] = []
  let para: string[] = []
  let code: string[] | null = null
  const flush = () => { if (para.length) { out.push({ k: 'p', text: para.join('\n') }); para = [] } }
  for (const raw of source.split('\n')) {
    if (raw.trim().startsWith('```')) {
      if (code) { out.push({ k: 'code', text: code.join('\n') }); code = null } else { flush(); code = [] }
      continue
    }
    if (code) { code.push(raw); continue }
    const line = raw.trim()
    const depth = Math.floor((raw.length - raw.trimStart().length) / 2)
    if (!line) { flush(); continue }
    let m: RegExpMatchArray | null
    if ((m = line.match(/^(#{1,6})\s*(.*)$/))) { flush(); out.push({ k: 'h', level: Math.min(m[1].length, 3), text: m[2] }) }
    else if (line === '---' || line === '***') { flush(); out.push({ k: 'hr' }) }
    else if ((m = line.match(/^[-*•]\s+(.*)$/))) { flush(); out.push({ k: 'li', text: m[1], depth }) }
    else if ((m = line.match(/^(\d+\.)\s+(.*)$/))) { flush(); out.push({ k: 'ol', n: m[1], text: m[2] }) }
    else if (line.startsWith('>')) { flush(); out.push({ k: 'quote', text: line.slice(1).trim() }) }
    else para.push(line)
  }
  if (code) out.push({ k: 'code', text: code.join('\n') })
  flush()
  return out
}

/** Inline **bold**, *italic*, `code` and [links](url). */
function inline(text: string): ReactNode[] {
  const nodes: ReactNode[] = []
  const re = /(\*\*[^*]+\*\*|\*[^*]+\*|`[^`]+`|\[[^\]]+\]\([^)]+\))/g
  let last = 0, i = 0
  for (const m of text.matchAll(re)) {
    if (m.index! > last) nodes.push(text.slice(last, m.index))
    const t = m[0]
    if (t.startsWith('**')) nodes.push(<strong key={i++} style={{ fontWeight: 600, color: palette.text }}>{t.slice(2, -2)}</strong>)
    else if (t.startsWith('`')) nodes.push(<code key={i++} style={{ font: '12px var(--mono)', background: 'rgba(255,255,255,0.06)', padding: '1px 5px', borderRadius: 5 }}>{t.slice(1, -1)}</code>)
    else if (t.startsWith('[')) {
      const [, label, href] = t.match(/\[([^\]]+)\]\(([^)]+)\)/)!
      nodes.push(<a key={i++} href="#" onClick={(e) => { e.preventDefault(); void syph.resolveUrl(href).then(syph.openExternal) }} style={{ color: palette.ice }}>{label}</a>)
    } else nodes.push(<em key={i++}>{t.slice(1, -1)}</em>)
    last = m.index! + t.length
  }
  if (last < text.length) nodes.push(text.slice(last))
  return nodes
}

export function Markdown({ source }: { source: string }) {
  return (
    <div className="selectable" style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
      {blocksOf(source).map((b, i) => {
        switch (b.k) {
          case 'h': return <div key={i} style={{ fontSize: b.level === 1 ? 18 : b.level === 2 ? 15.5 : 14, fontWeight: 600, marginTop: 4 }}>{inline(b.text)}</div>
          case 'p': return <div key={i} className="t-body" style={{ color: 'rgba(244,245,247,0.92)', lineHeight: 1.6, whiteSpace: 'pre-wrap' }}>{inline(b.text)}</div>
          case 'li': return (
            <div key={i} style={{ display: 'flex', gap: 8, paddingLeft: b.depth * 14, lineHeight: 1.55 }}>
              <span style={{ width: 4, height: 4, borderRadius: 2, background: 'rgba(157,184,255,0.8)', marginTop: 9, flex: 'none' }} />
              <span style={{ color: 'rgba(244,245,247,0.92)' }}>{inline(b.text)}</span>
            </div>
          )
          case 'ol': return (
            <div key={i} style={{ display: 'flex', gap: 8, lineHeight: 1.55 }}>
              <span style={{ font: '600 12px var(--mono)', color: palette.ice, marginTop: 1 }}>{b.n}</span>
              <span style={{ color: 'rgba(244,245,247,0.92)' }}>{inline(b.text)}</span>
            </div>
          )
          case 'quote': return (
            <div key={i} style={{ display: 'flex', gap: 10 }}>
              <span style={{ width: 2, borderRadius: 1, background: 'rgba(157,184,255,0.6)' }} />
              <span className="c2" style={{ fontStyle: 'italic' }}>{inline(b.text)}</span>
            </div>
          )
          case 'code': return (
            <pre key={i} className="t-mono" style={{ margin: 0, padding: 12, borderRadius: 10, background: 'rgba(0,0,0,0.35)', boxShadow: 'inset 0 0 0 0.75px var(--hairline)', overflowX: 'auto', color: 'rgba(244,245,247,0.88)' }}>{b.text}</pre>
          )
          case 'hr': return <div key={i} style={{ height: 0.5, background: 'var(--hairline)', margin: '4px 0' }} />
        }
      })}
    </div>
  )
}

export function FileCardView({ card }: { card: FileCard }) {
  return (
    <Card radius={12} pad={12} style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
      <span style={{ width: 36, height: 36, borderRadius: 8, background: 'rgba(157,184,255,0.12)', display: 'grid', placeItems: 'center', flex: 'none' }}>
        <FileText size={16} color={palette.ice} />
      </span>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div className="t-headline ellipsis">{card.title}</div>
        {card.meta && <div className="t-caption c3">{card.meta}</div>}
      </div>
      {card.files.map((f) => (
        <button key={f.href} className="btn-ghost sm" onClick={() => void syph.resolveUrl(f.href).then(syph.openExternal)}>
          {f.kind ? f.kind.toUpperCase() : 'Open'}
        </button>
      ))}
    </Card>
  )
}

export function MailCardView({ mail }: { mail: MailCard }) {
  return (
    <Card radius={12} pad={14} style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <span className="t-caption c3" style={{ display: 'flex', alignItems: 'center', gap: 6 }}><Mail size={12} /> Email</span>
        <Chip text={mail.status.replace(/^\w/, (c) => c.toUpperCase())} color={statusColor(mail.status)} />
      </div>
      {mail.to && <div className="t-callout c2">To {mail.to}</div>}
      {mail.subject && <div className="t-headline">{mail.subject}</div>}
      {mail.body && <div className="t-callout clamp3" style={{ color: 'rgba(244,245,247,0.85)' }}>{mail.body}</div>}
    </Card>
  )
}

export const CrmChip = ({ title }: { title: string }) => <Chip text={title} color={palette.mint} icon={Users} />
