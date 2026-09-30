import { app } from 'electron'
import type { DeviceCommand } from '../shared/types'

export interface Risk { level: 'ask' | 'block'; reason: string }

/** What a click or keystroke is aimed at, as far as the PC can tell. */
export interface Target { name?: string; role?: string; password?: boolean; secret?: boolean }

export interface GuardLookups {
  element(id: number): Promise<Target | null>
  at(x: number, y: number, space: string): Promise<Target | null>
  focused(): Promise<Target | null>
  browserRef(ref: number): Promise<Target | null>
}

/**
 * Buttons and links whose press commits something the owner can't take back.
 * "Sign in", "Accept cookies" and similar everyday clicks are deliberately not here.
 */
const COMMITTING = new RegExp(
  '\\b(pay( now)?|purchase|buy( now)?|place (your )?order|check ?out|confirm (and pay|payment|order|purchase|transfer)|' +
  'submit (payment|order)|complete (purchase|order|payment)|transfer|send( money| payment| now)?|wire|donate|subscribe|' +
  'delete|remove|uninstall|erase|format|factory reset|reset (pc|this pc|password)|sign(?! (in|up|out|on))|publish|post|tweet|' +
  'share|approve|accept (offer|quote|terms)|book( now)?|reserve|unsubscribe|cancel (subscription|order|account|membership)|close account)\\b',
  'i',
)

/** PowerShell that changes the system, destroys data, or reaches beyond the owner's files. */
const DESTRUCTIVE: Array<[RegExp, string]> = [
  [/\b(Remove-Item|rm|del|erase|rd|rmdir)\b[^|;]*-(Recurse|r\b|Force)|\b(rd|rmdir)\s+\/s|\bdel\s+\/[sq]/i, 'delete files recursively'],
  [/\b(Format-Volume|Clear-Disk|Initialize-Disk|diskpart|format\s+[a-z]:)/i, 'format or wipe a disk'],
  [/\b(Stop-Computer|Restart-Computer|shutdown(\.exe)?\s)/i, 'shut down or restart the PC'],
  [/\b(Set-ExecutionPolicy|bcdedit|reg(\.exe)?\s+(delete|add)|Remove-ItemProperty|Set-ItemProperty\s+[^|;]*HKLM)/i, 'change system settings'],
  [/\b(net\s+user|New-LocalUser|Add-LocalGroupMember|Set-LocalUser|Disable-LocalUser)\b/i, 'change user accounts'],
  [/\b(New-Service|sc(\.exe)?\s+(create|config|delete)|schtasks(\.exe)?\s+\/create|Register-ScheduledTask)\b/i, 'install a service or scheduled task'],
  [/\b(Invoke-WebRequest|iwr|Invoke-RestMethod|irm|curl|wget|Start-BitsTransfer)\b[^\n]*\|\s*(iex|Invoke-Expression)|\b(iex|Invoke-Expression)\b/i, 'download and run code'],
  [/\b(winget|choco|Install-Package|Install-Module|msiexec)\b/i, 'install or remove software'],
  [/\b(vssadmin|wbadmin|cipher\s+\/w|Set-MpPreference|Add-MpPreference|netsh\s+(advfirewall|firewall))\b/i, 'change backups, Defender or the firewall'],
  [/\b(Send-MailMessage)\b/i, 'send email'],
]

export class Guard {
  constructor(private lookups: GuardLookups) {}

  /** Nothing an employee runs may touch Syph itself: its settings, session, helper or process. */
  private touchesSyph(text: string): boolean {
    const t = text.toLowerCase()
    const own = app.getPath('userData').toLowerCase()
    return t.includes(own) || t.includes(own.replace(/\\/g, '/'))
      || /computer\.(bin|json)|session\.bin|device-id/.test(t)
      || /\b(stop-process|kill|taskkill)\b[^|;\n]*\bsyph/i.test(text)
      || /\\appdata\\roaming\\syph\b|\$env:appdata[\\/]+syph\b/i.test(text)
  }

  private commits(label: string | undefined): string | null {
    const text = (label ?? '').trim()
    if (!text) return null
    const m = text.match(COMMITTING)
    return m ? `press ‘${text.slice(0, 60)}’` : null
  }

  private async clickRisk(a: Record<string, unknown>): Promise<Risk | null> {
    let target: Target | null = null
    if (a.element !== undefined && a.element !== null && a.element !== '') target = await this.lookups.element(Number(a.element))
    else if (a.x !== undefined && a.y !== undefined) target = await this.lookups.at(Number(a.x), Number(a.y), String(a.space ?? 'screen'))
    const label = this.commits(target?.name) ?? this.commits(a.text as string) ?? this.commits(a.title as string)
    return label ? { level: 'ask', reason: label } : null
  }

  private async typingRisk(a: Record<string, unknown>): Promise<Risk | null> {
    const target = a.element !== undefined && a.element !== null && a.element !== ''
      ? await this.lookups.element(Number(a.element))
      : await this.lookups.focused()
    if (target?.password || target?.secret) {
      return { level: 'block', reason: 'Syph never types into password or payment fields. Sign in or pay yourself, then let the employee continue.' }
    }
    return null
  }

  /** The strictest risk across a command (and every step of an act batch). */
  async assess(command: DeviceCommand): Promise<Risk | null> {
    const a = command.arguments
    try {
      switch (command.operation) {
        case 'run_shell': {
          const line = String(a.command ?? '')
          if (this.touchesSyph(line)) return { level: 'block', reason: 'Commands may not touch Syph’s own settings, session or process.' }
          const hit = DESTRUCTIVE.find(([re]) => re.test(line))
          return hit ? { level: 'ask', reason: hit[1] } : null
        }
        case 'write_file': case 'read_file':
          if (this.touchesSyph(String(a.path ?? ''))) return { level: 'block', reason: 'Syph’s own files are off-limits.' }
          return null
        case 'click': case 'press': case 'click_text':
          return await this.clickRisk(a)
        case 'type_text': case 'set_value':
          return await this.typingRisk(a)
        case 'browser_click': {
          const t = a.ref !== undefined ? await this.lookups.browserRef(Number(a.ref)) : null
          const label = this.commits(t?.name) ?? this.commits(a.text as string)
          return label ? { level: 'ask', reason: label } : null
        }
        case 'browser_type': {
          const t = a.ref !== undefined ? await this.lookups.browserRef(Number(a.ref)) : null
          if (t?.secret) return { level: 'block', reason: 'Syph never types into password, card or one-time-code fields. Fill those in yourself.' }
          return null
        }
        case 'quit_app':
          return a.force === true ? { level: 'ask', reason: `force-quit ${a.app} (unsaved work is lost)` } : null
        case 'act': {
          let worst: Risk | null = null
          for (const step of Array.isArray(a.actions) ? (a.actions as Record<string, unknown>[]) : []) {
            const kind = String(step.do ?? step.action ?? '').toLowerCase()
            const scoped = { space: a.space ?? 'image', ...step }
            const risk = ['click', 'double_click', 'right_click', 'press', 'invoke'].includes(kind) ? await this.clickRisk(scoped)
              : ['type', 'type_text', 'set_value'].includes(kind) ? await this.typingRisk(scoped) : null
            if (risk?.level === 'block') return risk
            worst = worst ?? risk
          }
          return worst
        }
        default:
          return null
      }
    } catch {
      // The target couldn't be identified (window closed, element gone): the scope's own
      // Off / Ask / Allow still applies, and the action itself will fail on a missing target.
      return null
    }
  }
}
