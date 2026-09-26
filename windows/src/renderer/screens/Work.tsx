import { useEffect, useState } from 'react'
import { Activity as ActivityIcon, BookOpen, FileSearch, FileText, Filter, Folder, Presentation, Search, Table2, Trash2 } from 'lucide-react'
import type { Activity, DocumentListing, LibraryDocument } from '../../shared/types'
import { Markdown } from '../components/Message'
import { Card, EmptyState, Eyebrow, IconButton, ScreenHeader, Switch, TextField } from '../components/ui'
import { syph } from '../lib/bridge'
import { hueFor, palette, statusColor } from '../lib/theme'
import { clock, isPast, relative } from '../lib/time'
import { deleteJob, getDocument, documents, sel, setJob, useStore } from '../lib/store'

export function WorkScreen() {
  const s = useStore()
  const [filter, setFilter] = useState<string | null>(null)
  const [menu, setMenu] = useState(false)
  const items = s.activity.filter((a) => !filter || a.employeeId === filter)
  return (
    <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>
      <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column' }}>
        <ScreenHeader eyebrow="Work" title="Every step, on the record" detail="What your team did, newest first."
          trailing={
            <div style={{ position: 'relative' }}>
              <button className="btn-ghost sm" onClick={() => setMenu(!menu)}><Filter size={12} />{sel.employee(s, filter)?.name ?? 'Everyone'}</button>
              {menu && (
                <div className="pop-in" onMouseLeave={() => setMenu(false)} style={{ position: 'absolute', right: 0, top: 34, zIndex: 20, minWidth: 160, padding: 6, borderRadius: 10, background: 'rgba(20,23,32,0.98)', boxShadow: 'inset 0 0 0 0.75px var(--hairline-strong), 0 12px 30px rgba(0,0,0,0.5)' }}>
                  {[{ id: null as string | null, name: 'Everyone' }, ...s.employees].map((e) => (
                    <button key={e.id ?? 'all'} className="menu-item t-callout" onClick={() => { setFilter(e.id); setMenu(false) }} style={{ width: '100%', textAlign: 'left', padding: '6px 8px', borderRadius: 6 }}>{e.name}</button>
                  ))}
                  <style>{'.menu-item:hover{background:rgba(255,255,255,0.07)}'}</style>
                </div>
              )}
            </div>
          } />
        <div className="scroll" style={{ flex: 1, padding: '0 24px 24px' }}>
          {items.map((item, i) => <TimelineRow key={item.id} item={item} last={i === items.length - 1} />)}
          {!items.length && <EmptyState icon={ActivityIcon} title="Quiet so far" detail="Activity appears as your employees work." style={{ height: 280 }} />}
        </div>
      </div>
      <div className="divider-v" />
      <SchedulePanel />
    </div>
  )
}

function TimelineRow({ item, last }: { item: Activity; last: boolean }) {
  const employee = useStore((s) => sel.employee(s, item.employeeId))
  const color = statusColor(item.kind)
  return (
    <div style={{ display: 'flex', gap: 14 }}>
      <div className="t-mono c3" style={{ width: 92, textAlign: 'right', paddingTop: 1, flex: 'none' }}>{clock(item.at)}</div>
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', flex: 'none' }}>
        <span style={{ width: 7, height: 7, borderRadius: '50%', background: color, boxShadow: `0 0 3px ${color}`, marginTop: 6 }} />
        {!last && <span style={{ width: 0.75, flex: 1, background: 'var(--hairline)' }} />}
      </div>
      <div style={{ paddingBottom: 18, minWidth: 0 }}>
        <div style={{ display: 'flex', gap: 6, alignItems: 'baseline', flexWrap: 'wrap' }}>
          {employee && <span style={{ fontSize: 11.5, fontWeight: 600, color: hueFor(employee.id) }}>{employee.name}</span>}
          <span className="t-callout">{item.title}</span>
        </div>
        {item.summary && <div className="t-caption c2 clamp3" style={{ marginTop: 3 }}>{item.summary}</div>}
      </div>
    </div>
  )
}

function SchedulePanel() {
  const s = useStore()
  return (
    <div className="scroll" style={{ width: 340, flex: 'none', padding: '44px 18px 20px', display: 'flex', flexDirection: 'column', gap: 10, background: 'rgba(5,5,7,0.3)' }}>
      <Eyebrow>Recurring work</Eyebrow>
      {!s.jobs.length && <div className="t-caption c3">No schedules yet. Ask an employee to do something “every Monday at 9” and it appears here.</div>}
      {s.jobs.map((job) => (
        <Card key={job.id} radius={12} pad={12} style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
          <div style={{ display: 'flex', alignItems: 'flex-start', gap: 8 }}>
            <div className="t-headline clamp2" style={{ flex: 1, color: job.enabled ? palette.text : palette.text3 }}>{job.title}</div>
            <Switch on={job.enabled} onChange={(v) => void setJob(job, v)} label="Enabled" />
          </div>
          <div className="t-caption" style={{ color: palette.ice }}>{job.cadenceLabel || job.cadence || 'Schedule unset'}</div>
          {job.instruction && <div className="t-caption c2 clamp3">{job.instruction}</div>}
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <span className="t-caption c3" style={{ flex: 1 }}>{sel.employee(s, job.employeeId)?.name}</span>
            {job.enabled && job.nextRunAt && <span className="t-caption c3">{isPast(job.nextRunAt) ? 'due now' : `next ${relative(job.nextRunAt)}`}</span>}
            <IconButton icon={Trash2} label="Delete schedule" size={20} onClick={() => void deleteJob(job)} />
          </div>
        </Card>
      ))}
    </div>
  )
}

export function LibraryScreen() {
  const [query, setQuery] = useState('')
  const [folder, setFolder] = useState('')
  const [listing, setListing] = useState<DocumentListing | null>(null)
  const [selected, setSelected] = useState<LibraryDocument | null>(null)
  const [menu, setMenu] = useState(false)
  const load = async () => {
    try { setListing(await documents(query, folder)) } catch (e) { useStore.setState({ error: (e as Error).message }) }
  }
  useEffect(() => { void load() }, [folder]) // eslint-disable-line react-hooks/exhaustive-deps
  const open = async (d: LibraryDocument) => { setSelected(d); try { setSelected(await getDocument(d.id)) } catch { /* keep excerpt */ } }
  const icon = (f: string) => (f === 'pptx' || f === 'deck' ? Presentation : f === 'csv' || f === 'xlsx' ? Table2 : FileText)
  return (
    <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>
      <div style={{ width: 400, flex: 'none', display: 'flex', flexDirection: 'column' }}>
        <ScreenHeader eyebrow="Library" title="Documents" detail="Everything your employees wrote, researched and built." />
        <div style={{ display: 'flex', gap: 8, padding: '0 20px 12px' }}>
          <div style={{ flex: 1 }}><TextField value={query} onChange={setQuery} placeholder="Search documents" icon={Search} onSubmit={() => void load()} /></div>
          <div style={{ position: 'relative' }}>
            <button className="btn-ghost sm" style={{ height: '100%' }} onClick={() => setMenu(!menu)}><Folder size={12} />{folder || 'All'}</button>
            {menu && (
              <div className="pop-in" onMouseLeave={() => setMenu(false)} style={{ position: 'absolute', right: 0, top: 42, zIndex: 20, minWidth: 180, padding: 6, borderRadius: 10, background: 'rgba(20,23,32,0.98)', boxShadow: 'inset 0 0 0 0.75px var(--hairline-strong), 0 12px 30px rgba(0,0,0,0.5)' }}>
                {['', ...(listing?.folders ?? [])].map((f) => (
                  <button key={f || 'all'} className="menu-item t-callout" onClick={() => { setFolder(f); setMenu(false) }} style={{ width: '100%', textAlign: 'left', padding: '6px 8px', borderRadius: 6 }}>{f || 'All folders'}</button>
                ))}
                <style>{'.menu-item:hover{background:rgba(255,255,255,0.07)}'}</style>
              </div>
            )}
          </div>
        </div>
        <div className="scroll" style={{ flex: 1, padding: '0 12px' }}>
          {listing?.documents.map((d) => {
            const Icon = icon(d.format)
            return (
              <button key={d.id} onClick={() => void open(d)} className="side-row" style={{ width: '100%', display: 'flex', gap: 12, padding: 10, borderRadius: 10, textAlign: 'left', background: selected?.id === d.id ? 'rgba(255,255,255,0.07)' : undefined }}>
                <Icon size={16} color={palette.ice} style={{ flex: 'none', marginTop: 2 }} />
                <div style={{ minWidth: 0 }}>
                  <div className="t-callout ellipsis">{d.title}</div>
                  <div className="t-caption c3">{d.folder} · {relative(d.updated_at)}</div>
                </div>
              </button>
            )
          })}
          {listing && !listing.documents.length && <EmptyState icon={BookOpen} title="No documents" detail="Reports, decks and notes appear here." style={{ height: 240 }} />}
        </div>
      </div>
      <div className="divider-v" />
      <div className="scroll" style={{ flex: 1 }}>
        {selected ? (
          <div key={selected.id} className="fade-in" style={{ maxWidth: 780, padding: 36, display: 'flex', flexDirection: 'column', gap: 14 }}>
            <Eyebrow color={palette.ice}>{selected.folder}</Eyebrow>
            <div className="t-display" style={{ fontSize: 26 }}>{selected.title}</div>
            <div style={{ display: 'flex', gap: 8 }}>
              {(selected.downloads ?? []).map((dl) => (
                <button key={dl.format} className="btn-ghost sm" onClick={() => void syph.resolveUrl(dl.url).then(syph.openExternal)}>{dl.format.toUpperCase()}</button>
              ))}
            </div>
            <div style={{ height: 0.5, background: 'var(--hairline)' }} />
            <Markdown source={selected.content ?? selected.excerpt ?? ''} />
          </div>
        ) : (
          <EmptyState icon={FileSearch} title="Pick a document" detail="Preview it here, or download it in the format you need." />
        )}
      </div>
    </div>
  )
}
