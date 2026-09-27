import SwiftUI

/// Brand mark for Settings integration rows — mirrors web IntegrationMark.
struct IntegrationMark: View {
    let id: String
    var size: CGFloat = 28

    private var radius: CGFloat { size * 0.3 }
    private var glyph: CGFloat { size * 0.5 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(background)
            Image(systemName: symbol)
                .font(.system(size: glyph, weight: .semibold))
                .foregroundStyle(foreground)
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(needsHairline ? Color.white.opacity(0.08) : .clear, lineWidth: 0.5)
        )
        .accessibilityHidden(true)
    }

    private var symbol: String {
        switch id {
        case "gmail": return "envelope.fill"
        case "whatsapp": return "phone.fill"
        case "telegram": return "paperplane.fill"
        case "odoo": return "circle"
        case "etsy": return "storefront.fill"
        case "presenton": return "rectangle.on.rectangle.angled"
        case "drive": return "triangle.fill"
        case "docs": return "doc.text.fill"
        case "calendar": return "calendar"
        case "sheet", "sheets": return "tablecells.fill"
        case "model": return "sparkle"
        case "computer": return "desktopcomputer"
        case "web": return "globe"
        case "records": return "person.crop.rectangle.stack"
        case "documents": return "doc.on.doc.fill"
        default: return "app.fill"
        }
    }

    private var background: Color {
        switch id {
        case "model": return Color(hex: 0x1f1d1a)
        case "gmail": return .white
        case "whatsapp": return Color(hex: 0x25D366)
        case "telegram": return Color(hex: 0x229ED9)
        case "odoo": return Color(hex: 0x714B67)
        case "etsy": return Color(hex: 0xF1641E)
        case "presenton": return Color(hex: 0x2f3a4f)
        case "drive": return Color(hex: 0xfef3d6)
        case "docs": return Color(hex: 0xe8f0fe)
        case "calendar": return Color(hex: 0xe3edfd)
        case "sheet", "sheets": return Color(hex: 0xe1f2e6)
        case "computer": return Color(hex: 0x0f172a)
        default: return Palette.panel
        }
    }

    private var foreground: Color {
        switch id {
        case "gmail": return Color(hex: 0xEA4335)
        case "whatsapp", "telegram", "odoo", "etsy", "presenton", "model": return .white
        case "drive": return Color(hex: 0xe8930c)
        case "docs", "calendar": return Color(hex: 0x1a73e8)
        case "sheet", "sheets": return Color(hex: 0x188038)
        case "computer": return Color(hex: 0xbfe3ff)
        default: return Palette.text
        }
    }

    private var needsHairline: Bool {
        ["gmail", "drive", "docs", "calendar", "sheet", "sheets", "web", "records", "documents"].contains(id)
    }
}
