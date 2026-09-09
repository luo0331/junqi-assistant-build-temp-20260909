import UIKit

enum OverlayRenderer {
    static func render(
        _ state: OverlayState,
        size: CGSize = CGSize(width: 640, height: 360)
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let bounds = CGRect(origin: .zero, size: size)
            UIColor(red: 0.97, green: 0.98, blue: 1.0, alpha: 1).setFill()
            context.fill(bounds)

            let headerColor = UIColor(red: 0.08, green: 0.20, blue: 0.36, alpha: 1)
            let accent = UIColor(red: 0.95, green: 0.62, blue: 0.12, alpha: 1)
            headerColor.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: 72))
            accent.setFill()
            context.fill(CGRect(x: 0, y: 68, width: size.width, height: 4))

            drawText(
                "四国军棋实时情报",
                in: CGRect(x: 24, y: 12, width: 360, height: 42),
                font: .systemFont(ofSize: 31, weight: .bold),
                color: .white
            )

            let stepText = state.step.map { "第\($0)步" } ?? "步数识别中"
            drawText(
                stepText,
                in: CGRect(x: size.width - 180, y: 14, width: 150, height: 36),
                font: .monospacedDigitSystemFont(ofSize: 27, weight: .bold),
                color: accent,
                alignment: .right
            )

            drawText(
                state.statusText,
                in: CGRect(x: 24, y: 43, width: size.width - 220, height: 24),
                font: .systemFont(ofSize: 16, weight: .medium),
                color: UIColor.white.withAlphaComponent(0.82)
            )

            let panelTop: CGFloat = 82
            let panelHeight: CGFloat = 108
            let panelWidth = (size.width - 72) / 2
            drawPanel(
                title: "左敌剩余",
                body: state.leftSummary,
                rect: CGRect(x: 24, y: panelTop, width: panelWidth, height: panelHeight),
                accent: UIColor(red: 0.94, green: 0.30, blue: 0.24, alpha: 1)
            )
            drawPanel(
                title: "右敌剩余",
                body: state.rightSummary,
                rect: CGRect(x: 48 + panelWidth, y: panelTop, width: panelWidth, height: panelHeight),
                accent: UIColor(red: 0.95, green: 0.52, blue: 0.12, alpha: 1)
            )

            drawText(
                "推演事件",
                in: CGRect(x: 24, y: 198, width: 150, height: 28),
                font: .systemFont(ofSize: 22, weight: .bold),
                color: accent
            )
            drawText(
                state.eventText,
                in: CGRect(x: 24, y: 226, width: size.width - 48, height: 46),
                font: .systemFont(ofSize: 27, weight: .bold),
                color: headerColor
            )

            drawText(
                "候选",
                in: CGRect(x: 24, y: 280, width: 100, height: 26),
                font: .systemFont(ofSize: 21, weight: .bold),
                color: accent
            )
            let candidateText = state.candidates.isEmpty
                ? "暂无候选情报"
                : state.candidates.prefix(3).joined(separator: "  ")
            drawText(
                candidateText,
                in: CGRect(x: 24, y: 306, width: size.width - 48, height: 42),
                font: .monospacedDigitSystemFont(ofSize: 20, weight: .semibold),
                color: UIColor(red: 0.12, green: 0.17, blue: 0.24, alpha: 1)
            )
        }
    }

    private static func drawPanel(
        title: String,
        body: String,
        rect: CGRect,
        accent: UIColor
    ) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 11)
        UIColor(white: 1, alpha: 0.95).setFill()
        path.fill()

        accent.setFill()
        UIBezierPath(
            roundedRect: CGRect(x: rect.minX, y: rect.minY, width: 6, height: rect.height),
            cornerRadius: 3
        ).fill()

        drawText(
            title,
            in: CGRect(x: rect.minX + 16, y: rect.minY + 7, width: rect.width - 26, height: 24),
            font: .systemFont(ofSize: 18, weight: .bold),
            color: accent
        )
        drawText(
            body.isEmpty ? "暂无数据" : body,
            in: CGRect(x: rect.minX + 16, y: rect.minY + 31, width: rect.width - 26, height: 70),
            font: .monospacedDigitSystemFont(ofSize: 18, weight: .bold),
            color: UIColor(red: 0.10, green: 0.14, blue: 0.20, alpha: 1)
        )
    }

    private static func drawText(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping

        (text as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ],
            context: nil
        )
    }
}
