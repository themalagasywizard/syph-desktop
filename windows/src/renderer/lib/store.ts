import { create } from 'zustand'
import { useShallow } from 'zustand/react/shallow'
import type {
  Activity, Approval, BridgeState, ChatMessage, ConnectedTool, Conversation, DocumentListing, Employee, LibraryDocument,
  LlmProvider, LlmSettings, SyphUser, WakeJob, WorkingRun, WorkspacePayload,
} from '../../shared/types'
import { syph } from './bridge'
import { demoWorking, fixture } from './fixture'

export type Phase = 'restoring' | 'signedOut' | 'loading' | 'ready'
export type Section = 'chat' | 'team' | 'approvals' | 'work' | 'library' | 'computer' | 'settings'
export const SECTIONS: Section[] = ['chat', 'team', 'approvals', 'work', 'library', 'computer', 'settings']

export interface HireInput {
  name: string; role: string; mission: string; success: string; personality: string
  toolIds: string[]; autonomy: string; wakeCadence: string
}

interface State {
  phase: Phase
  demo: boolean
  section: Section
  showHire: boolean
  user: SyphUser | null
  employees: Employee[]
  approvals: Approval[]
  activity: Activity[]
  jobs: WakeJob[]
  conversations: Conversation[]
  messages: ChatMessage[]
  accountTools: ConnectedTool[]
  employeeTools: ConnectedTool[]
  working: Record<string, WorkingRun>
  selectedEmployeeId: string | null
  selectedThreadIds: Record<string, string>
  drafts: Record<string, string>
  isSending: boolean
  isSigningIn: boolean
  error: string | null
  toast: string | null
  llmProviders: LlmProvider[]
  llmSettings: LlmSettings | null
  bridge: BridgeState | null
}

const polls = new Map<string, number>()
let refreshTimer: number | null = null
let seenApprovals: Set<string> | null = null

export const useStore = create<State>(() => ({
  phase: 'restoring', demo: false, section: 'chat', showHire: false,
  user: null, employees: [], approvals: [], activity: [], jobs: [], conversations: [], messages: [],
  accountTools: [], employeeTools: [], working: {}, selectedEmployeeId: null, selectedThreadIds: {}, drafts: {},
  isSending: false, isSigningIn: false, error: null, toast: null, llmProviders: [], llmSettings: null, bridge: null,
}))

/** Select several fields at once without re-render loops. */
export const useStoreShallow = <T,>(fn: (s: State) => T): T => useStore(useShallow(fn))

const set = useStore.setState
const get = useStore.getState

async function call<T>(method: string, path: string, body?: unknown, opts?: { idempotent?: boolean; timeout?: number }): Promise<T> {
  const res = await syph.api<T>(method, path, body, opts)
  if (!res.ok) throw Object.assign(new Error(res.error ?? 'Request failed'), { status: res.status })
  return res.data as T
}

// ------------------------------------------------------------------ derived

export const sel = {
  selectedEmployee: (s: State) => s.employees.find((e) => e.id === s.selectedEmployeeId) ?? s.employees[0] ?? null,
  waiting: (s: State) => s.approvals.filter((a) => a.status === 'waiting'),
  employee: (s: State, id?: string | null) => s.employees.find((e) => e.id === id) ?? null,
  threads: (s: State, employeeId: string) => s.conversations.filter((c) => c.employeeId === employeeId)
    .sort((a, b) => (b.lastMessageAt ?? b.createdAt).localeCompare(a.lastMessageAt ?? a.createdAt)),
  thread: (s: State, employeeId: string) => {
    const id = s.selectedThreadIds[employeeId]
    return s.conversations.find((c) => c.id === id) ?? s.conversations.find((c) => c.employeeId === employeeId && c.status === 'active') ?? null
  },
  messages: (s: State, employeeId: string) => {
    const thread = sel.thread(s, employeeId)
    const rows = thread ? s.messages.filter((m) => m.conversationId === thread.id) : s.messages.filter((m) => m.employeeId === employeeId && !m.conversationId)
    return [...rows].sort((a, b) => a.at.localeCompare(b.at))
  },
  tools: (s: State, employeeId: string) => s.employeeTools.filter((t) => t.employeeId === employeeId),
  activeCount: (s: State) => Object.values(s.working).filter((w) => w.active).length,
}

export const isUser = (m: ChatMessage) => ['user', 'principal', 'owner'].includes(m.role)
export const isPaused = (e: Employee) => e.status === 'paused'

// ------------------------------------------------------------------ session

export async function launch() {
  const opts = await syph.launch()
  if (opts.demo) { loadDemo(opts.section as Section | undefined); return }
  await restore()
}

function loadDemo(section?: Section) {
  const p = fixture
  set({
    demo: true, phase: 'ready', user: p.user, employees: p.employees, approvals: p.approvals, activity: p.activity, jobs: p.jobs,
    conversations: p.conversations, messages: p.messages, accountTools: p.accountTools, employeeTools: p.employeeTools,
    selectedEmployeeId: p.employees[0]?.id ?? null, working: { e1: demoWorking },
    section: section && SECTIONS.includes(section) ? section : 'chat',
    llmProviders: [{ id: 'openai', name: 'OpenAI', keyLabel: 'OpenAI API key', keyHint: '', allowCustomModel: true, models: [{ id: 'gpt-5.6-sol', name: 'GPT-5.6 Sol' }] }],
    llmSettings: { provider: 'openai', model: 'gpt-5.6-sol', baseUrl: '', keyConfigured: false, keyHint: '', fallbackModels: [] },
  })
}

export async function restore() {
  set({ phase: 'restoring' })
  try {
    await call('GET', '/api/v1/auth/me')
    set({ phase: 'loading' })
    await loadWorkspace()
    set({ phase: 'ready' })
    afterSignIn()
  } catch (e) {
    const status = (e as { status?: number }).status
    set({ phase: 'signedOut', error: status === 401 ? null : (e as Error).message })
  }
}

export async function signIn(email: string, password: string) {
  set({ isSigningIn: true, error: null })
  try {
    await call('POST', '/api/v1/auth/login', { email, password })
    set({ phase: 'loading' })
    await loadWorkspace()
    set({ phase: 'ready' })
    afterSignIn()
  } catch (e) {
    set({ phase: 'signedOut', error: (e as Error).message })
  } finally {
    set({ isSigningIn: false })
  }
}

function afterSignIn() {
  void syph.signedIn()
  if (refreshTimer) window.clearInterval(refreshTimer)
  refreshTimer = window.setInterval(() => { if (get().phase === 'ready') void refresh() }, 12_000)
}

export async function signOut() {
  if (refreshTimer) window.clearInterval(refreshTimer)
  polls.forEach((id) => window.clearTimeout(id)); polls.clear()
  await syph.api('POST', '/api/v1/auth/logout')
  await syph.signedOut()
  set({ user: null, employees: [], approvals: [], activity: [], jobs: [], conversations: [], messages: [], working: {}, phase: 'signedOut' })
}

// ------------------------------------------------------------------ loading

export async function loadWorkspace() {
  const p = await call<WorkspacePayload>('GET', '/api/v1/workspace')
  const s = get()
  const incoming = new Set((p.conversations ?? []).map((c) => c.id))
  const msgIds = new Set((p.messages ?? []).map((m) => m.id))
  const employees = p.employees ?? []
  set({
    user: p.user, employees, approvals: p.approvals ?? [], activity: p.activity ?? [], jobs: p.jobs ?? [],
    conversations: [...(p.conversations ?? []), ...s.conversations.filter((c) => !incoming.has(c.id))],
    messages: [...(p.messages ?? []), ...s.messages.filter((m) => !msgIds.has(m.id))],
    accountTools: p.accountTools ?? [], employeeTools: p.employeeTools ?? [],
    selectedEmployeeId: s.selectedEmployeeId && employees.some((e) => e.id === s.selectedEmployeeId) ? s.selectedEmployeeId : employees[0]?.id ?? null,
  })
  notifyApprovals()
  const id = sel.selectedEmployee(get())?.id
  if (id) { await refreshWorking(id); await loadThread(id) }
}

function notifyApprovals() {
  const waiting = sel.waiting(get())
  void syph.setBadge(waiting.length)
  const ids = new Set(waiting.map((a) => a.id))
  if (seenApprovals && !document.hasFocus()) {
    for (const a of waiting.filter((w) => !seenApprovals!.has(w.id))) {
      void syph.notify(`${sel.employee(get(), a.employeeId)?.name ?? 'An employee'} needs you`, a.title)
    }
  }
  seenApprovals = ids
}

export async function refresh() {
  if (get().demo) return
  try { await loadWorkspace(); if (get().error) set({ error: null }) } catch (e) {
    if ((e as { status?: number }).status === 401) set({ phase: 'signedOut' }); else set({ error: (e as Error).message })
  }
}

export function selectEmployee(e: Employee) {
  if (e.id === get().selectedEmployeeId) return
  set({ selectedEmployeeId: e.id })
  if (!get().demo) { void refreshWorking(e.id); void loadThread(e.id) }
}

export async function loadThread(employeeId: string) {
  const thread = sel.thread(get(), employeeId)
  if (!thread || get().demo) return
  try {
    const d = await call<{ conversation: Conversation; messages: ChatMessage[] }>('GET', `/api/v1/conversations/${thread.id}`)
    set((s) => ({
      messages: [...s.messages.filter((m) => m.conversationId !== thread.id), ...d.messages],
      conversations: s.conversations.map((c) => (c.id === thread.id ? d.conversation : c)),
    }))
  } catch { /* keep what the payload carried */ }
}

export async function selectThread(c: Conversation) {
  set((s) => ({ selectedThreadIds: { ...s.selectedThreadIds, [c.employeeId]: c.id } }))
  await loadThread(c.employeeId)
}

export async function newThread(employeeId: string) {
  if (get().demo) return
  try {
    const t = await call<Conversation>('POST', `/api/v1/employees/${employeeId}/conversations`, {})
    set((s) => ({ conversations: [t, ...s.conversations], selectedThreadIds: { ...s.selectedThreadIds, [employeeId]: t.id } }))
  } catch (e) { set({ error: (e as Error).message }) }
}

// ------------------------------------------------------------------ working

export async function refreshWorking(employeeId: string) {
  try {
    const run = await call<WorkingRun>('GET', `/api/v1/employees/${employeeId}/working`)
    set((s) => ({ working: { ...s.working, [employeeId]: run } }))
    if (run.active) beginPolling(employeeId)
  } catch { /* transient */ }
}

function beginPolling(employeeId: string) {
  if (polls.has(employeeId)) return
  const tick = async () => {
    try {
      const run = await call<WorkingRun>('GET', `/api/v1/employees/${employeeId}/working`)
      set((s) => ({ working: { ...s.working, [employeeId]: run } }))
      if (!run.active) { polls.delete(employeeId); await loadThread(employeeId); await refresh(); return }
    } catch { polls.delete(employeeId); return }
    polls.set(employeeId, window.setTimeout(tick, 1500))
  }
  polls.set(employeeId, window.setTimeout(tick, 1500))
}

// ------------------------------------------------------------------ commands

export async function send(text: string, employeeId: string): Promise<boolean> {
  const body = text.trim()
  const s = get()
  if (!body || s.isSending) return false
  if (s.demo) { set({ toast: 'Demo mode — nothing was sent.' }); return false }
  if (s.working[employeeId]?.active) { set({ toast: 'Still working — wait for the current task or stop it.' }); return false }
  set({ isSending: true, error: null })
  const echoId = `local-${Date.now()}`
  try {
    let thread = sel.thread(get(), employeeId)
    if (!thread || thread.status === 'archived') {
      thread = await call<Conversation>('POST', `/api/v1/employees/${employeeId}/conversations`, {})
      const t = thread
      set((st) => ({ conversations: [t, ...st.conversations], selectedThreadIds: { ...st.selectedThreadIds, [employeeId]: t.id } }))
    }
    set((st) => ({ messages: [...st.messages, { id: echoId, employeeId, conversationId: thread!.id, role: 'user', body, at: new Date().toISOString() }] }))
    const res = await call<{ ok: boolean; runId?: string }>('POST', `/api/v1/employees/${employeeId}/instructions`,
      { body, conversationId: thread.id }, { idempotent: true, timeout: 180 })
    set((st) => ({ working: { ...st.working, [employeeId]: { active: true, runId: res.runId ?? null, status: 'working', goal: body, phase: 'starting', steps: [] } } }))
    beginPolling(employeeId)
    await loadThread(employeeId)
    set((st) => ({ messages: st.messages.filter((m) => m.id !== echoId) }))
    return true
  } catch (e) {
    set((st) => ({ messages: st.messages.filter((m) => m.id !== echoId), error: (e as Error).message, drafts: { ...st.drafts, [employeeId]: body } }))
    return false
  } finally {
    set({ isSending: false })
  }
}

export async function stop(employeeId: string) {
  if (get().demo) return
  const runId = get().working[employeeId]?.runId
  await syph.api('POST', `/api/v1/employees/${employeeId}/working/cancel${runId ? `?run_id=${runId}` : ''}`, undefined, { idempotent: true })
  await refreshWorking(employeeId)
}

export async function resolve(a: Approval, approve: boolean): Promise<boolean> {
  if (get().demo) {
    set((s) => ({ approvals: s.approvals.map((x) => (x.id === a.id ? { ...x, status: approve ? 'approved' : 'rejected' } : x)), toast: approve ? 'Approved.' : 'Declined.' }))
    return true
  }
  try {
    await call('POST', `/api/v1/approvals/${a.id}/${approve ? 'approve' : 'reject'}`, undefined, { idempotent: true })
    set((s) => ({
      approvals: s.approvals.map((x) => (x.id === a.id ? { ...x, status: approve ? 'approved' : 'rejected' } : x)),
      toast: approve ? `Approved — ${sel.employee(get(), a.employeeId)?.name ?? 'they'} will carry on.` : 'Declined.',
    }))
    if (approve) await refreshWorking(a.employeeId)
    await refresh()
    return true
  } catch (e) { set({ error: (e as Error).message }); return false }
}

export async function hire(input: HireInput): Promise<Employee> {
  const body: Record<string, unknown> = {
    mission: input.mission, success: input.success, toolIds: input.toolIds, toolAccess: {}, autonomy: input.autonomy,
    role: input.role, personality: input.personality, userContext: '', wakeCadence: input.wakeCadence,
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
  }
  if (input.name.trim()) body.name = input.name.trim()
  const employee = await call<Employee>('POST', '/api/v1/employees', body, { idempotent: true })
  await loadWorkspace()
  set({ selectedEmployeeId: employee.id })
  return employee
}

export async function patch(employeeId: string, fields: Record<string, unknown>) {
  if (get().demo) {
    set((s) => ({ employees: s.employees.map((e) => (e.id === employeeId ? { ...e, ...(fields.toolIds ? { toolIds: fields.toolIds as string[] } : {}), ...(fields.autonomy ? { autonomyLevel: String(fields.autonomy) } : {}) } : e)) }))
    return
  }
  try { await call('PATCH', `/api/v1/employees/${employeeId}`, fields); await refresh() } catch (e) { set({ error: (e as Error).message }) }
}

export async function setTool(toolId: string, enabled: boolean, e: Employee) {
  let ids = [...(e.toolIds ?? [])]
  ids = enabled ? (ids.includes(toolId) ? ids : [...ids, toolId]) : ids.filter((x) => x !== toolId)
  if (!ids.length) { set({ error: 'Each employee needs at least one tool.' }); return }
  await patch(e.id, { toolIds: ids })
}

async function command(path: string) {
  if (get().demo) return
  try { await call('POST', path, undefined, { idempotent: true }); await refresh() } catch (e) { set({ error: (e as Error).message }) }
}
export const pause = (id: string) => command(`/api/v1/employees/${id}/pause`)
export const resume = (id: string) => command(`/api/v1/employees/${id}/resume`)
export const wake = async (id: string) => { await command(`/api/v1/employees/${id}/wakeup`); await refreshWorking(id) }
export const pauseAll = () => command('/api/v1/workspace/pause-all')

export async function setJob(job: WakeJob, enabled: boolean) {
  if (get().demo) { set((s) => ({ jobs: s.jobs.map((j) => (j.id === job.id ? { ...j, enabled } : j)) })); return }
  try { await call('PATCH', `/api/v1/employees/${job.employeeId}/jobs/${job.id}`, { enabled }); await refresh() } catch (e) { set({ error: (e as Error).message }) }
}

export async function deleteJob(job: WakeJob) {
  if (get().demo) { set((s) => ({ jobs: s.jobs.filter((j) => j.id !== job.id) })); return }
  try { await call('DELETE', `/api/v1/employees/${job.employeeId}/jobs/${job.id}`); set((s) => ({ jobs: s.jobs.filter((j) => j.id !== job.id) })) } catch (e) { set({ error: (e as Error).message }) }
}

// ------------------------------------------------------------------ library + settings

export async function documents(query: string, folder: string): Promise<DocumentListing> {
  if (get().demo) {
    return {
      folders: ['Proposals', 'Reports/Weekly', 'Briefs'],
      documents: [
        { id: 'd1', title: 'ABC Stone — Q4 proposal', folder: 'Proposals', format: 'pdf', updated_at: '2026-09-26T09:31:00Z', excerpt: '', downloads: [{ format: 'pdf', url: '#' }, { format: 'md', url: '#' }] },
        { id: 'd2', title: 'Morning market brief', folder: 'Briefs', format: 'markdown', updated_at: '2026-09-26T08:05:00Z', excerpt: '', downloads: [{ format: 'md', url: '#' }] },
        { id: 'd3', title: 'Weekly pipeline review', folder: 'Reports/Weekly', format: 'pptx', updated_at: '2026-09-22T10:00:00Z', excerpt: '', downloads: [{ format: 'pptx', url: '#' }] },
      ].filter((d) => (!folder || d.folder === folder) && (!query || d.title.toLowerCase().includes(query.toLowerCase()))),
    }
  }
  const q = new URLSearchParams({ offset: '0' })
  if (query) q.set('q', query)
  if (folder) q.set('folder', folder)
  return call<DocumentListing>('GET', `/api/v1/documents?${q}`)
}

export async function getDocument(id: string): Promise<LibraryDocument> {
  if (get().demo) {
    return { id, title: 'ABC Stone — Q4 proposal', folder: 'Proposals', format: 'pdf', downloads: [{ format: 'pdf', url: '#' }],
      content: '# Q4 proposal\n\nPrepared for **Tomasz Nowak**, ABC Stone.\n\n## Terms\n\n- €94,000 over 12 months\n- Delivery from November\n- Net 30 invoicing\n\n> Above the €90k floor you set.' }
  }
  return call<LibraryDocument>('GET', `/api/v1/documents/${id}`)
}

export async function loadModelSettings() {
  if (get().demo) return
  try { set({ llmProviders: await call<LlmProvider[]>('GET', '/api/v1/settings/llm/providers') }) } catch { /* keep */ }
  try { set({ llmSettings: await call<LlmSettings>('GET', '/api/v1/settings/llm') }) } catch { /* keep */ }
}

export async function saveModel(provider: string, model: string, apiKey: string) {
  const s = get().llmSettings
  const body: Record<string, unknown> = { provider, model, baseUrl: s?.baseUrl ?? '', fallbackModels: s?.fallbackModels ?? [] }
  if (apiKey.trim()) body.apiKey = apiKey.trim()
  set({ llmSettings: await call<LlmSettings>('PUT', '/api/v1/settings/llm', body) })
}

export const testModel = () => call<{ ok: boolean; message: string }>('POST', '/api/v1/settings/llm/test')

export async function connectUrl(path: string): Promise<string> {
  return (await call<{ url: string }>('POST', path, {})).url
}

export function go(section: Section) { set({ section }) }
