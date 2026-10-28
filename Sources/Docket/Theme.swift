import AppKit
import DocketCore
import SwiftUI

/// Semantic design tokens. Views read colours, radii and fonts only from here.
struct Theme {
    var colorScheme: ColorScheme
    var backgroundPrimary: Color
    var backgroundSecondary: Color
    var backgroundTertiary: Color
    var textPrimary: Color
    var textSecondary: Color
    var accent: Color
    var needForeground: Color
    var needBackground: Color
    var chipStroke: Color
    /// Agent state chips: a working agent and a finished one.
    var workingForeground: Color
    var workingBackground: Color
    var doneForeground: Color
    var doneBackground: Color
    /// Text on accent-filled controls.
    var onAccent: Color
    /// Logo dots, pills and connector line.
    var logo: (dots: Color, pills: Color, line: Color)
    var radiusSmall: CGFloat = 8
    var radiusMedium: CGFloat = 12
    var textFamily: String?
    var monoFamily: String?
    /// Capsule labels in ALL CAPS.
    var uppercaseCapsules: Bool

    static let nord = Theme(
        colorScheme: .dark,
        backgroundPrimary: Color(hex: 0x2E3440),
        backgroundSecondary: Color(hex: 0x3B4252),
        backgroundTertiary: Color(hex: 0x434C5E),
        textPrimary: Color(hex: 0xECEFF4),
        textSecondary: Color(hex: 0xD8DEE9).opacity(0.7),
        accent: Color(hex: 0x88C0D0),
        needForeground: Color(hex: 0xBF616A),
        needBackground: Color(hex: 0xBF616A).opacity(0.18),
        chipStroke: Color(hex: 0x4C566A),
        workingForeground: Color(hex: 0x88C0D0),
        workingBackground: Color(hex: 0x88C0D0).opacity(0.18),
        doneForeground: Color(hex: 0xA3BE8C),
        doneBackground: Color(hex: 0xA3BE8C).opacity(0.18),
        onAccent: Color(hex: 0x2E3440),
        logo: (Color(hex: 0x88C0D0), Color(hex: 0xD8DEE9), Color(hex: 0x4C566A)),
        uppercaseCapsules: false
    )

    /// n8n brand Light mode, from n8ndesign.md tokens only.
    static let n8n = Theme(
        colorScheme: .light,
        backgroundPrimary: Color(hex: 0xFAFAFA),
        backgroundSecondary: Color(hex: 0xF1F1F1),
        backgroundTertiary: Color(hex: 0xEAEAEA),
        textPrimary: Color(hex: 0x191919),
        textSecondary: Color.black.opacity(0.5),
        accent: Color(hex: 0xFF91AC),
        needForeground: Color(hex: 0x87003C),
        needBackground: Color(hex: 0xFFE8EC),
        chipStroke: Color(hex: 0xBFBFBF),
        workingForeground: Color(hex: 0x191919),
        workingBackground: Color(hex: 0xFF91AC),
        doneForeground: Color(hex: 0xFAFAFA),
        doneBackground: Color(hex: 0x191919),
        onAccent: Color(hex: 0x191919),
        logo: (Color(hex: 0xFF91AC), Color(hex: 0x191919), Color(hex: 0xBFBFBF)),
        textFamily: Theme.installed("n8n Baumer Uniwidth"),
        monoFamily: Theme.installed("n8n Baumer Mono"),
        uppercaseCapsules: true
    )

    static func named(_ name: ThemeName) -> Theme { name == .n8n ? .n8n : .nord }

    /// The family name when the font is installed, so the theme falls back to the system font otherwise.
    static func installed(_ family: String) -> String? {
        NSFontManager.shared.availableFontFamilies.contains(family) ? family : nil
    }

    func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        textFamily.map { Font.custom($0, size: size).weight(weight) } ?? .system(size: size, weight: weight)
    }

    func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        monoFamily.map { Font.custom($0, size: size).weight(weight) } ?? .system(size: size, weight: weight, design: .monospaced)
    }

    func capsule(_ text: String) -> String { uppercaseCapsules ? text.uppercased() : text }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension EnvironmentValues {
    @Entry var theme: Theme = .nord
}

/// Capsule buttons in theme colours. Prominent ones use the accent.
struct ThemedButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .lineLimit(1)
            .fixedSize()
            .font(theme.font(13, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(prominent ? theme.accent : theme.backgroundTertiary, in: .capsule)
            .foregroundStyle(prominent ? theme.onAccent : theme.textPrimary)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(.capsule)
    }
}

/// Lays views out in rows, wrapping to the next row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map { $0.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0 }.reduce(0) { $0 + $1 + spacing } - spacing
        let width = rows.map { row in row.map { $0.sizeThatFits(.unspecified).width }.reduce(0) { $0 + $1 + spacing } - spacing }.max() ?? 0
        return CGSize(width: width, height: max(height, 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            let height = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for view in row {
                let size = view.sizeThatFits(.unspecified)
                view.place(at: CGPoint(x: x, y: y + (height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += height + spacing
        }
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [[LayoutSubview]] {
        var rows: [[LayoutSubview]] = [[]]
        var x: CGFloat = 0
        for view in subviews {
            let w = view.sizeThatFits(.unspecified).width
            if x + w > width, !rows[rows.count - 1].isEmpty {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(view)
            x += w + spacing
        }
        return rows
    }
}
