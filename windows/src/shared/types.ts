// Wire models for the Syph API — the same contract as the Mac and iPhone apps.

export interface SyphUser { id: string; name: string; email: string; role: string }

export interface Employee {
  id: string; name: string; role: string; missionTitle?: string; mission?: string; success?: string
  personality?: string; status?: string; currentTaskTitle?: string; autonomyLevel?: string
  wakeCadence?: string; timezone?: string; nextWakeAt?: string | null; toolIds?: string[]
}

export interface Approval {
  id: string; employeeId: string; title: string; situation: string; recommendation: string
  reason: string; risk: string; primaryAction: string; status: string
}

export interface Activity { id: string; employeeId: string; at: string; title: string; summary: string; kind: string }

export interface Conversation {
  id: string; employeeId: string; title: string; status: string; messageCount: number
  lastMessageAt?: string | null; createdAt: string
}

export interface ChatMessage {
  id: string; employeeId: string; conversationId?: string | null; role: string; body: string; at: string
}

export interface WorkingStep { tool: string; operation: string; label: string; status: string; summary: string }
export interface WorkingRun { active: boolean; runId?: string | null; status: string; goal: string; phase: string; steps: WorkingStep[] }

export interface ConnectedTool {
  id: string; name: string; description: string; connected: boolean
  read: string; write: string; send: string; delete?: string | null; access?: string | null; employeeId?: string | null
}

export interface WakeJob {
  id: string; employeeId: string; title: string; instruction: string; cadence: string; cadenceLabel?: string
  timezone?: string; nextRunAt?: string | null; enabled: boolean
}

export interface LibraryDocument {
  id: string; title: string; folder: string; format: string; employee_id?: string | null
  created_at?: string; updated_at?: string; excerpt?: string; content?: string | null
  downloads?: { format: string; url: string }[]
}

export interface DocumentListing { documents: LibraryDocument[]; folders: string[] }

export interface LlmProvider { id: string; name: string; keyLabel: string; keyHint: string; allowCustomModel: boolean; models: { id: string; name: string }[] }
export interface LlmSettings { provider: string; model: string; baseUrl: string; keyConfigured: boolean; keyHint: string; fallbackModels: string[] }

export interface WorkspacePayload {
  user: SyphUser; employees: Employee[]; approvals: Approval[]; activity: Activity[]; jobs: WakeJob[]
  conversations: Conversation[]; messages: ChatMessage[]; accountTools: ConnectedTool[]; employeeTools: ConnectedTool[]
}

export interface DeviceRecord {
  id: string; name: string; platform: string; model: string; osVersion: string; appVersion: string
  controlEnabled: boolean; scopes: Record<string, string>; online: boolean; lastSeenAt?: string | null
}

export interface DeviceCommand {
  id: string; employeeId?: string | null; employeeName: string; runId?: string | null
  operation: string; arguments: Record<string, unknown>; status: string; summary: string; createdAt: string
}

// ---- Computer control (local) ----

export type ScopeMode = 'off' | 'ask' | 'allow'
export const SCOPES = ['observe', 'screen', 'control', 'apps', 'browser', 'office', 'clipboard', 'files_read', 'files_outside', 'files_write', 'shell'] as const
export type Scope = (typeof SCOPES)[number]

export interface PolicyState {
  controlEnabled: boolean
  modes: Record<Scope, ScopeMode>
  sharedFolders: string[]
}

export type LinkState = 'idle' | 'linking' | 'online' | 'offline'

export interface LocalAction {
  id: string; employee: string; employeeId?: string | null; operation: string; scope?: Scope | null
  status: string; summary: string; detail: string; startedAt: number; finishedAt?: number; thumbnail?: string
}

export interface BridgeState {
  deviceId: string; link: LinkState; linkError?: string
  current?: LocalAction | null; log: LocalAction[]; devices: DeviceRecord[]
  policy: PolicyState; hostName: string
}

export interface ConsentRequest {
  id: string; employee: string; scope: Scope; operation: string; headline: string; detail: string; deadline: number
}
export type ConsentDecision = 'once' | 'always' | 'deny'

export interface OverlayState { visible: boolean; employee: string; activity: string; tint: string }

export interface ApiResult<T = unknown> { ok: boolean; status: number; data?: T; error?: string }

export interface LaunchOptions { demo: boolean; section?: string; demoConsent?: boolean; surface: string }

/** Everything the renderer may ask of the main process. */
export interface SyphBridge {
  launch(): Promise<LaunchOptions>
  api<T = unknown>(method: string, path: string, body?: unknown, opts?: { idempotent?: boolean; timeout?: number }): Promise<ApiResult<T>>
  getServer(): Promise<string>
  setServer(url: string): Promise<void>
  resolveUrl(path: string): Promise<string>
  openExternal(url: string): Promise<void>
  signedIn(): Promise<void>
  signedOut(): Promise<void>

  bridgeState(): Promise<BridgeState>
  setControl(enabled: boolean): Promise<void>
  setScope(scope: Scope, mode: ScopeMode): Promise<void>
  resetScopes(): Promise<void>
  addFolder(): Promise<void>
  removeFolder(path: string): Promise<void>
  revealFolder(path: string): Promise<void>
  emergencyStop(): Promise<void>
  unlinkDevice(id: string): Promise<void>

  consentDecide(id: string, decision: ConsentDecision): Promise<void>
  overlayStop(): Promise<void>

  toggleCommandBar(): Promise<void>
  hideCommandBar(): Promise<void>
  showMain(section?: string): Promise<void>
  setBadge(count: number): Promise<void>
  notify(title: string, body: string): Promise<void>
  window(action: 'minimize' | 'maximize' | 'close'): Promise<void>

  on(channel: 'bridge' | 'consent' | 'overlay' | 'navigate' | 'commandbar-opened' | 'workspace-changed', fn: (payload: any) => void): () => void
  broadcast(channel: 'workspace-changed', payload?: unknown): void
}

declare global {
  interface Window { syph?: SyphBridge }
}
