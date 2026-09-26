import Foundation
import SwiftUI

/// `-SyphDemo YES` fills the workspace from a fixture instead of the network,
/// for screenshots and design review. `-SyphSection <name>` opens a section;
/// `-SyphDemoConsent YES` shows the consent panel and the driving overlay.
enum DemoMode {
    static var isOn: Bool { UserDefaults.standard.bool(forKey: "SyphDemo") }
    static var section: AppSection? { UserDefaults.standard.string(forKey: "SyphSection").flatMap(AppSection.init(rawValue:)) }
    static var showConsent: Bool { UserDefaults.standard.bool(forKey: "SyphDemoConsent") }

    static func payload() -> WorkspacePayload? {
        try? JSONDecoder().decode(WorkspacePayload.self, from: Data(fixture.utf8))
    }

    static let working = WorkingRun(
        active: true, runId: "run-1", status: "working",
        goal: "Pull this week’s Etsy orders into the shipping sheet", phase: "acting",
        steps: [
            WorkingStep(tool: "etsy", operation: "orders", label: "Read open Etsy orders", status: "verified", summary: "7 orders awaiting shipment."),
            WorkingStep(tool: "computer", operation: "open_app", label: "Open Numbers on your Mac", status: "verified", summary: "Opened Numbers."),
            WorkingStep(tool: "computer", operation: "read_screen", label: "Read the shipping sheet", status: "running", summary: ""),
        ])

    static let commandJSON = """
    {"id":"cmd-demo","deviceId":null,"employeeId":"e1","employeeName":"Atlas","runId":"run-1","operation":"run_shell",
     "arguments":{"command":"mkdir -p ~/Documents/Syph/Invoices && mv ~/Downloads/*invoice*.pdf ~/Documents/Syph/Invoices/"},
     "status":"delivered","summary":"","createdAt":"2026-09-26T09:40:00Z","completedAt":null}
    """

    static let fixture = """
    {
      "user": {"id": "u1", "name": "Ryan Trumble", "email": "ryan@syph.ai", "role": "Owner"},
      "employees": [
        {"id": "e1", "name": "Atlas", "role": "Market & Sales", "missionTitle": "Keep the pipeline honest",
         "mission": "Find qualified buyers, keep the pipeline honest, follow up, and surface only the decisions that need me.",
         "success": "Three qualified meetings a week.", "personality": "Direct, brief, numbers first.", "status": "active",
         "autonomyLevel": "balanced", "wakeCadence": "12h", "timezone": "Europe/Berlin", "toolIds": ["records","web","gmail","odoo","computer"]},
        {"id": "e2", "name": "Vale", "role": "Marketing", "missionTitle": "Campaigns and briefs",
         "mission": "Research the market, draft campaigns, and keep a brief ready before anyone asks.",
         "status": "active", "autonomyLevel": "autonomous", "toolIds": ["web","documents","presenton"]},
        {"id": "e3", "name": "Ines", "role": "Executive assistant", "missionTitle": "Inbox and calendar",
         "mission": "Keep the inbox, calendar and follow-ups from eating the week.", "status": "active",
         "autonomyLevel": "conservative", "toolIds": ["gmail","calendar","computer"]},
        {"id": "e4", "name": "Soren", "role": "Operations", "missionTitle": "Shop operations", "mission": "Run the Etsy shop back office.",
         "status": "paused", "autonomyLevel": "balanced", "toolIds": ["etsy","sheet"]}
      ],
      "approvals": [
        {"id": "a1", "employeeId": "e1", "title": "Send Tomasz the Q4 proposal",
         "situation": "Email proposal.pdf from your Gmail to Tomasz Nowak at ABC Stone.",
         "recommendation": "Send today. €94k is above your €90k floor.", "reason": "communication.send requires approval",
         "risk": "Outbound communication. Nothing is sent until you approve.", "primaryAction": "Approve send", "status": "waiting"},
        {"id": "a2", "employeeId": "e3", "title": "Run a command on your Mac",
         "situation": "mv ~/Downloads/*invoice*.pdf ~/Documents/Syph/Invoices/",
         "recommendation": "File this month’s invoices before the accountant’s export.", "reason": "computer.update requires approval",
         "risk": "Runs on the linked Mac with the scopes you allowed there.", "primaryAction": "Approve on Mac", "status": "waiting"}
      ],
      "activity": [
        {"id": "ac1", "employeeId": "e1", "at": "2026-09-26T09:42:00Z", "title": "Drafted the Q4 proposal for ABC Stone", "summary": "€94k, 12-month term. Waiting on your approval to send.", "kind": "waiting"},
        {"id": "ac2", "employeeId": "e3", "at": "2026-09-26T09:31:00Z", "title": "Read your screen in Mail", "summary": "Found 4 invoices in Downloads.", "kind": "done"},
        {"id": "ac3", "employeeId": "e2", "at": "2026-09-26T08:05:00Z", "title": "Morning market brief", "summary": "Three competitor launches, one pricing change worth answering.", "kind": "done"},
        {"id": "ac4", "employeeId": "e1", "at": "2026-09-26T08:00:00Z", "title": "Updated 6 opportunities in Odoo", "summary": "Moved Kraków Tiles to Proposal.", "kind": "done"},
        {"id": "ac5", "employeeId": "e4", "at": "2026-09-25T17:10:00Z", "title": "Paused by you", "summary": "", "kind": "paused"}
      ],
      "jobs": [
        {"id": "j1", "employeeId": "e2", "title": "Morning market brief", "instruction": "Scan competitors and send me a one-page brief.", "cadence": "daily_morning", "cadenceLabel": "Every morning", "timezone": "Europe/Berlin", "nextRunAt": "2026-09-27T06:00:00Z", "enabled": true},
        {"id": "j2", "employeeId": "e1", "title": "Pipeline review", "instruction": "Review stale deals and propose follow-ups.", "cadence": "12h", "cadenceLabel": "Twice a day", "timezone": "Europe/Berlin", "nextRunAt": "2026-09-26T18:00:00Z", "enabled": true},
        {"id": "j3", "employeeId": "e3", "title": "File invoices", "instruction": "Move invoices from Downloads into the Invoices folder.", "cadence": "weekly", "cadenceLabel": "Fridays at 16:00", "timezone": "Europe/Berlin", "nextRunAt": null, "enabled": false}
      ],
      "conversations": [
        {"id": "c1", "employeeId": "e1", "title": "ABC Stone proposal", "status": "active", "messageCount": 4, "lastMessageAt": "2026-09-26T09:42:00Z", "createdAt": "2026-09-26T09:30:00Z"},
        {"id": "c2", "employeeId": "e1", "title": "Weekly pipeline", "status": "archived", "messageCount": 12, "lastMessageAt": "2026-09-22T10:00:00Z", "createdAt": "2026-09-22T09:00:00Z"}
      ],
      "messages": [
        {"id": "m1", "employeeId": "e1", "conversationId": "c1", "role": "user", "body": "Where are we with ABC Stone?", "at": "2026-09-26T09:30:00Z"},
        {"id": "m2", "employeeId": "e1", "conversationId": "c1", "role": "assistant", "body": "Proposal’s drafted at **€94k** — above your €90k floor.\\n\\n- Tomasz asked for a 12-month term\\n- Delivery from November\\n- Their CFO signs above €80k\\n\\nIt’s in *Needs you* whenever you’re ready.\\n\\n[[file]]{\\"title\\": \\"ABC Stone — Q4 proposal\\", \\"meta\\": \\"Proposals · PDF\\", \\"files\\": [{\\"kind\\": \\"pdf\\", \\"name\\": \\"proposal.pdf\\", \\"href\\": \\"/api/v1/documents/d1/download/pdf\\"}]}[[/file]]", "at": "2026-09-26T09:31:00Z"},
        {"id": "m3", "employeeId": "e1", "conversationId": "c1", "role": "user", "body": "Good. Also put this week’s Etsy orders into the shipping sheet on my Mac.", "at": "2026-09-26T09:40:00Z"}
      ],
      "accountTools": [
        {"id": "gmail", "name": "Gmail", "description": "Full Gmail mailbox.", "connected": true, "read": "autonomous", "write": "autonomous", "send": "approval"},
        {"id": "calendar", "name": "Google Calendar", "description": "The live agenda.", "connected": true, "read": "autonomous", "write": "autonomous", "send": "denied"},
        {"id": "web", "name": "Web", "description": "Search and read the web.", "connected": true, "read": "autonomous", "write": "denied", "send": "denied"},
        {"id": "odoo", "name": "Odoo CRM", "description": "Contacts, leads and opportunities.", "connected": true, "read": "autonomous", "write": "autonomous", "send": "denied"},
        {"id": "etsy", "name": "Etsy", "description": "Listings and open orders.", "connected": true, "read": "autonomous", "write": "denied", "send": "denied"},
        {"id": "computer", "name": "Mac (computer control)", "description": "Use the owner’s Mac through the Syph desktop app.", "connected": true, "read": "autonomous", "write": "autonomous", "send": "denied", "delete": "approval"},
        {"id": "documents", "name": "Documents", "description": "The document library.", "connected": true, "read": "autonomous", "write": "autonomous", "send": "denied"}
      ],
      "employeeTools": [
        {"id": "gmail", "name": "Gmail", "description": "", "connected": true, "read": "autonomous", "write": "autonomous", "send": "approval", "employeeId": "e1"},
        {"id": "odoo", "name": "Odoo CRM", "description": "", "connected": true, "read": "autonomous", "write": "autonomous", "send": "denied", "employeeId": "e1"},
        {"id": "computer", "name": "Mac", "description": "", "connected": true, "read": "autonomous", "write": "autonomous", "send": "denied", "employeeId": "e1"},
        {"id": "web", "name": "Web", "description": "", "connected": true, "read": "autonomous", "write": "denied", "send": "denied", "employeeId": "e1"}
      ]
    }
    """
}

extension WorkspaceStore {
    func loadDemo() {
        guard let payload = DemoMode.payload() else {
            errorMessage = "Demo fixture failed to decode."
            phase = .signedOut
            return
        }
        user = payload.user
        employees = payload.employees
        approvals = payload.approvals
        activity = payload.activity
        jobs = payload.jobs
        conversations = payload.conversations
        messages = payload.messages
        accountTools = payload.accountTools
        employeeTools = payload.employeeTools
        selectedEmployeeID = payload.employees.first?.id
        working = ["e1": DemoMode.working]
        phase = .ready
    }
}

extension AppModel {
    func launchDemo() {
        store.loadDemo()
        if let section = DemoMode.section { self.section = section }
        policy.onChange = nil  // no network in demo mode
        policy.controlEnabled = true
        bridge.link = .online
        if DemoMode.showConsent,
           let command = try? JSONDecoder().decode(DeviceCommand.self, from: Data(DemoMode.commandJSON.utf8)) {
            bridge.overlay.show(employee: "Atlas", activity: "Reading the shipping sheet in Numbers", tint: Palette.hue(for: "e1"))
            Task { _ = await bridge.consent.ask(employee: "Ines", scope: .shell, command: command) }
        }
    }
}
