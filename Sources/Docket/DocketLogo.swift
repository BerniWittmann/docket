import SwiftUI

/// The Docket mark: a vertical connector with three dots and three decreasing pills, on a 32×32 grid.
struct DocketLogo: View {
    var dots: Color
    var pills: Color
    var line: Color

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 32
            context.scaleBy(x: scale, y: scale)
            var connector = Path()
            connector.move(to: CGPoint(x: 7, y: 8))
            connector.addLine(to: CGPoint(x: 7, y: 24))
            context.stroke(connector, with: .color(line), lineWidth: 2)
            for (y, width) in [(5.0, 17.0), (13, 13), (21, 9)] {
                context.fill(Path(roundedRect: CGRect(x: 12, y: y, width: width, height: 6), cornerRadius: 3), with: .color(pills))
                context.fill(Path(ellipseIn: CGRect(x: 4, y: y, width: 6, height: 6)), with: .color(dots))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Docket")
    }
}

extension DocketLogo {
    init(theme: Theme) {
        self.init(dots: theme.logo.dots, pills: theme.logo.pills, line: theme.logo.line)
    }

    /// The app icon: the logo in n8n colours on a rounded n8n background.
    @MainActor
    static func renderIcon(to path: String) throws {
        let icon = ZStack {
            RoundedRectangle(cornerRadius: 224, style: .continuous).fill(Theme.n8n.backgroundPrimary)
            DocketLogo(theme: .n8n).padding(160)
        }
        .frame(width: 1024, height: 1024)
        let renderer = ImageRenderer(content: icon)
        renderer.scale = 1
        guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        let rep = NSBitmapImageRep(cgImage: image)
        try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
