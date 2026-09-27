import SwiftUI
import AppKit

/// Splits an assistant message into prose and the structured cards the
/// backend embeds (`[[file]]`, `[[mail]]`, `[[crm]]`), and drops model
/// think/reasoning tags — the same contract as web and iPhone.
enum MessageParser {
    struct FileCard: Hashable, Identifiable {
        var id: String { title + files.map(\.href).joined() }
        var title: String
        var meta: String
        var files: [FileLink]
    }

    struct FileLink: Hashable {
        var name: String
        var kind: String
        var href: String
    }

    struct MailCard: Hashable {
        var to: String
        var subject: String
        var body: String
        var status: String
    }

    struct Parsed {
        var prose: String
        var files: [FileCard] = []
        var mail: MailCard?
        var crmTitle: String?
    }

    static func parse(_ raw: String) -> Parsed {
        var text = raw
        for pattern in [#"<think>[\s\S]*?</think>"#, #"<reasoning>[\s\S]*?</reasoning>"#, #"<think\b[^>]*>[\s\S]*$"#] {
            text = text.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        var parsed = Parsed(prose: "")
        for json in blocks("file", in: &text) {
            guard let object = json else { continue }
            let files = (object["files"] as? [[String: Any]] ?? []).map {
                FileLink(name: ($0["name"] as? String) ?? ($0["kind"] as? String ?? "file"),
                         kind: ($0["kind"] as? String) ?? "", href: ($0["href"] as? String) ?? "")
            }
            parsed.files.append(FileCard(title: object["title"] as? String ?? "File",
                                         meta: object["meta"] as? String ?? "", files: files))
        }
        for json in blocks("mail", in: &text) {
            guard let object = json else { continue }
            let name = object["to_name"] as? String ?? object["toName"] as? String ?? ""
            let email = object["to_email"] as? String ?? object["toEmail"] as? String ?? ""
            parsed.mail = MailCard(
                to: [name, email.isEmpty ? "" : "<\(email)>"].filter { !$0.isEmpty }.joined(separator: " "),
                subject: object["subject"] as? String ?? "",
                body: object["body"] as? String ?? "",
                status: object["status"] as? String ?? "draft")
        }
        for json in blocks("crm", in: &text) {
            parsed.crmTitle = (json?["title"] as? String) ?? "CRM update"
        }
        parsed.prose = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return parsed
    }

    private static func blocks(_ tag: String, in text: inout String) -> [[String: Any]?] {
        guard let regex = try? NSRegularExpression(pattern: "\\[\\[\(tag)\\]\\]([\\s\\S]*?)\\[\\[/\(tag)\\]\\]") else { return [] }
        let ns = text as NSString
        var found: [[String: Any]?] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let inner = ns.substring(with: match.range(at: 1))
            let object = (try? JSONSerialization.jsonObject(with: Data(inner.utf8))) as? [String: Any]
            found.append(object)
        }
        text = regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        return found
    }
}

/// Lightweight Markdown: headings, lists, quotes, code fences, rules, and
/// inline emphasis/links via AttributedString.
struct MarkdownText: View {
    let source: String

    private enum Block: Hashable {
        case heading(Int, String)
        case paragraph(String)
        case bullet(String, Int)
        case numbered(String, String)
        case quote(String)
        case code(String)
        case rule
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.blocks(source).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(.system(size: level == 1 ? 18 : (level == 2 ? 15.5 : 14), weight: .semibold))
                .foregroundStyle(Palette.text)
                .padding(.top, 4)
        case .paragraph(let text):
            Text(inline(text)).font(Typo.body).foregroundStyle(Palette.text.opacity(0.92)).lineSpacing(3.5)
        case .bullet(let text, let depth):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(Palette.ice.opacity(0.8)).frame(width: 4, height: 4).offset(y: -2)
                Text(inline(text)).font(Typo.body).foregroundStyle(Palette.text.opacity(0.92)).lineSpacing(3)
            }
            .padding(.leading, CGFloat(depth) * 14)
        case .numbered(let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(number).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Palette.ice)
                Text(inline(text)).font(Typo.body).foregroundStyle(Palette.text.opacity(0.92)).lineSpacing(3)
            }
        case .quote(let text):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 1).fill(Palette.ice.opacity(0.6)).frame(width: 2)
                Text(inline(text)).font(Typo.body).italic().foregroundStyle(Palette.textSecondary)
            }
        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code).font(Typo.mono).foregroundStyle(Palette.text.opacity(0.88)).padding(12)
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.inset))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.hairline, lineWidth: 0.75))
        case .rule:
            Rectangle().fill(Palette.hairline).frame(height: 0.5).padding(.vertical, 4)
        }
    }

    private func inline(_ text: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        var value = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        for run in value.runs where run.link != nil {
            let tint: Color = Palette.ice
            value[run.range].foregroundColor = tint
            value[run.range].underlineStyle = Text.LineStyle.single
        }
        return value
    }

    private static func blocks(_ source: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var code: [String]?
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
        }
        for rawLine in source.components(separatedBy: "\n") {
            if rawLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if let lines = code { blocks.append(.code(lines.joined(separator: "\n"))); code = nil }
                else { flush(); code = [] }
                continue
            }
            if code != nil { code?.append(rawLine); continue }
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let indent = rawLine.prefix(while: { $0 == " " }).count / 2
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("#") {
                flush()
                let level = line.prefix(while: { $0 == "#" }).count
                blocks.append(.heading(min(level, 3), String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)))
            } else if line == "---" || line == "***" {
                flush(); blocks.append(.rule)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                flush(); blocks.append(.bullet(String(line.dropFirst(2)), indent))
            } else if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty,
                      line[line.index(after: dot)...].hasPrefix(" ") {
                flush(); blocks.append(.numbered(String(line[...dot]), String(line[line.index(dot, offsetBy: 2)...])))
            } else if line.hasPrefix(">") {
                flush(); blocks.append(.quote(String(line.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else {
                paragraph.append(line)
            }
        }
        if let lines = code { blocks.append(.code(lines.joined(separator: "\n"))) }
        flush()
        return blocks
    }
}

struct FileCardView: View {
    let card: MessageParser.FileCard
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Palette.ice.opacity(0.12))
                Image(systemName: "doc.richtext").foregroundStyle(Palette.ice)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title).font(Typo.headline).foregroundStyle(Palette.text)
                if !card.meta.isEmpty { Text(card.meta).font(Typo.caption).foregroundStyle(Palette.textTertiary) }
            }
            Spacer()
            ForEach(card.files, id: \.href) { file in
                Button(file.kind.isEmpty ? "Open" : file.kind.uppercased()) {
                    if let url = app.api.resolve(file.href) { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(GhostButtonStyle(compact: true))
            }
        }
        .card(radius: 12, padding: 12)
    }
}

struct MailCardView: View {
    let mail: MessageParser.MailCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Email", systemImage: "envelope").font(Typo.caption).foregroundStyle(Palette.textTertiary)
                Spacer()
                Chip(text: mail.status.capitalized, color: Palette.status(mail.status))
            }
            if !mail.to.isEmpty { Text("To \(mail.to)").font(Typo.callout).foregroundStyle(Palette.textSecondary) }
            if !mail.subject.isEmpty { Text(mail.subject).font(Typo.headline).foregroundStyle(Palette.text) }
            if !mail.body.isEmpty {
                Text(mail.body).font(Typo.callout).foregroundStyle(Palette.text.opacity(0.85)).lineLimit(8)
            }
        }
        .card(radius: 12, padding: 14)
    }
}
