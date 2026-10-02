import { useEffect, useState, type ReactNode } from 'react'
import { CircleAlert, CheckCircle2, Cpu, Keyboard, KeyRound, UserCircle, Waypoints, type LucideIcon } from 'lucide-react'
import { Card, KeyCap, ScreenHeader, Spinner, StatusDot, TextField } from '../components/ui'
import { syph } from '../lib/bridge'
import { palette } from '../lib/theme'
import { connectUrl, go, loadModelSettings, saveModel, signOut, testModel, useStore } from '../lib/store'

const CONSOLE = 'https://jarvis-client-console.netlify.app/settings'

function Group({ title, icon: Icon, children }: { title: string; icon: LucideIcon; children: ReactNode }) {
  return (
    <Card radius={16} pad={18} style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      <div className="t-headline" style={{ display: 'flex', alignItems: 'center', gap: 8 }}><Icon size={16} />{title}</div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>{children}</div>
    </Card>
  )
}

export function SettingsScreen() {
  return (
    <div className="scroll" style={{ flex: 1 }}>
      <div style={{ maxWidth: 820, padding: '0 28px 28px', display: 'flex', flexDirection: 'column', gap: 22 }}>
        <div style={{ margin: '0 -24px' }}><ScreenHeader eyebrow="Settings" title="Workspace" /></div>
        <Account />
        <Model />
        <Integrations />
        <Shortcuts />
      </div>
    </div>
  )
}

function Account() {
  const user = useStore((s) => s.user)
  const deviceId = useStore((s) => s.bridge?.deviceId ?? '')
  const [server, setServer] = useState('')
  useEffect(() => { void syph.getServer().then(setServer) }, [])
  const row = (k: string, v: string) => (
    <div style={{ display: 'flex', gap: 12 }}>
      <span className="t-callout c3" style={{ width: 110, flex: 'none' }}>{k}</span>
      <span className="t-callout ellipsis selectable">{v}</span>
    </div>
  )
  return (
    <Group title="Account" icon={UserCircle}>
      {user && row('Signed in as', `${user.name} · ${user.email}`)}
      {user && row('Role', user.role)}
      {row('Server', server)}
      {row('This PC', deviceId)}
      <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
        <button className="btn-ghost sm" style={{ color: palette.coral }} onClick={() => void signOut()}>Sign out</button>
      </div>
    </Group>
  )
}

function Model() {
  const providers = useStore((s) => s.llmProviders)
  const settings = useStore((s) => s.llmSettings)
  const [provider, setProvider] = useState('')
  const [model, setModel] = useState('')
  const [key, setKey] = useState('')
  const [status, setStatus] = useState<{ ok: boolean; text: string } | null>(null)
  const [busy, setBusy] = useState(false)
  useEffect(() => { void loadModelSettings() }, [])
  useEffect(() => {
    if (settings) { setProvider(settings.provider); setModel(settings.model) } else if (providers[0]) setProvider(providers[0].id)
  }, [settings, providers])
  const current = providers.find((p) => p.id === provider)
  const run = async (work: () => Promise<void>) => {
    setBusy(true); setStatus(null)
    try { await work() } catch (e) { setStatus({ ok: false, text: (e as Error).message }) } finally { setBusy(false) }
  }
  const select = (label: string, value: string, options: { id: string; name: string }[], onChange: (v: string) => void) => (
    <label style={{ flex: 1, display: 'flex', alignItems: 'center', gap: 8 }}>
      <span className="t-callout c2">{label}</span>
      <select value={value} onChange={(e) => onChange(e.target.value)} style={{
        flex: 1, padding: '7px 10px', borderRadius: 8, border: 0, outline: 0, background: 'rgba(255,255,255,0.07)', boxShadow: 'inset 0 0 0 0.75px var(--hairline)',
      }}>
        {options.map((o) => <option key={o.id} value={o.id} style={{ background: '#141720' }}>{o.name}</option>)}
        {!options.some((o) => o.id === value) && value && <option value={value} style={{ background: '#141720' }}>{value}</option>}
      </select>
    </label>
  )
  const testButton = <button className="btn-ghost sm" onClick={() => void run(async () => { const r = await testModel(); setStatus({ ok: r.ok, text: r.message }) })}>Test</button>
  const statusLine = status && (
    <span className="t-caption" style={{ color: status.ok ? palette.mint : palette.coral, display: 'flex', gap: 5, alignItems: 'center' }}>
      {status.ok ? <CheckCircle2 size={12} /> : <CircleAlert size={12} />}{status.text}
    </span>
  )
  if (settings?.managed) {
    const modelName = providers.find((p) => p.id === settings.provider)?.models.find((m) => m.id === settings.model)?.name ?? settings.model
    return (
      <Group title="AI model" icon={Cpu}>
        <div className="t-callout c2">AI model managed by Syph</div>
        <div className="t-callout">{modelName}</div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          {statusLine}
          <span style={{ flex: 1 }} />
          {busy && <Spinner />}
          {testButton}
        </div>
      </Group>
    )
  }
  return (
    <Group title="AI model" icon={Cpu}>
      <div style={{ display: 'flex', gap: 12 }}>
        {select('Provider', provider, providers, (v) => { setProvider(v); const first = providers.find((p) => p.id === v)?.models[0]; if (first) setModel(first.id) })}
        {select('Model', model, current?.models ?? [], setModel)}
      </div>
      <TextField value={key} onChange={setKey} secure icon={KeyRound}
        placeholder={settings?.keyConfigured ? `Key saved (${settings.keyHint}) — paste to replace` : current?.keyLabel ?? 'API key'} />
      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        {statusLine}
        <span style={{ flex: 1 }} />
        {busy && <Spinner />}
        {testButton}
        <button className="btn-signal sm" disabled={!provider || !model} onClick={() => void run(async () => { await saveModel(provider, model, key); setKey(''); setStatus({ ok: true, text: 'Saved.' }) })}>Save</button>
      </div>
    </Group>
  )
}

function Integrations() {
  const tools = useStore((s) => s.accountTools)
  const google: Record<string, string> = { gmail: 'gmail', calendar: 'calendar', drive: 'drive', docs: 'docs', sheet: 'sheet' }
  return (
    <Group title="Connected tools" icon={Waypoints}>
      {tools.map((t) => (
        <div key={t.id} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '2px 0' }}>
          <StatusDot color={t.connected ? palette.mint : palette.faint} size={6} />
          <div style={{ flex: 1, minWidth: 0 }}>
            <div className="t-callout">{t.name}</div>
            <div className="t-caption c3 ellipsis">{t.description}</div>
          </div>
          <span className="t-caption" style={{ color: t.connected ? palette.mint : palette.text3 }}>{t.connected ? 'Connected' : 'Not connected'}</span>
          {google[t.id] && !t.connected && (
            <button className="btn-ghost sm" onClick={() => void connectUrl(`/api/v1/settings/gmail/connect?service=${google[t.id]}`).then(syph.openExternal).catch((e) => useStore.setState({ error: e.message }))}>Connect</button>
          )}
          {t.id === 'computer' && <button className="btn-ghost sm" onClick={() => go('computer')}>Open</button>}
        </div>
      ))}
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginTop: 6 }}>
        <span className="t-caption c3" style={{ flex: 1 }}>OAuth apps, WhatsApp, Telegram, Odoo and Etsy keys are managed in the web console.</span>
        <button className="btn-ghost sm" onClick={() => void syph.openExternal(CONSOLE)}>Open web console</button>
      </div>
    </Group>
  )
}

function Shortcuts() {
  const rows: [string[], string][] = [
    [['Alt', 'Space'], 'Command bar, from anywhere'],
    [['Ctrl', 'Alt', '.'], 'Stop computer control, from anywhere'],
    [['Ctrl', 'K'], 'Command bar'],
    [['Ctrl', '1…7'], 'Switch sections'],
    [['Ctrl', 'N'], 'Hire an employee'],
    [['Ctrl', 'Enter'], 'Approve the open decision'],
  ]
  return (
    <Group title="Keyboard" icon={Keyboard}>
      {rows.map(([keys, label]) => (
        <div key={label} style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
          {keys.map((k) => <KeyCap key={k} k={k} />)}
          <span className="t-callout c2" style={{ marginLeft: 8 }}>{label}</span>
        </div>
      ))}
    </Group>
  )
}
