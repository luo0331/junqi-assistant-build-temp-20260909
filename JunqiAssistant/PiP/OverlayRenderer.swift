import UIKit

enum OverlayRenderer {
    static func render(_ state: OverlayState, size: CGSize = CGSize(width: 640, height: 360)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let bounds = CGRect(origin: .zero, size: size)
            UIColor(red: 0.06, green: 0.09, blue: 0.14, alpha: 1).setFill()
            context.fill(bounds)

            let accent = UIColor(red: 0.94, green: 0.70, blue: 0.22, alpha: 1)
            accent.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: 8))

            drawText(
                "军棋实时情报",
                in: CGRect(x: 28, y: 22, width: 300, height: 42),
                font: .systemFont(ofSize: 30, weight: .bold),
                color: .white
            )

            let stepText = state.step.map { "第\($0)步" } ?? "步数识别中"
            drawText(
                stepText,
                in: CGRect(x: size.width - 190, y: 28, width: 160, height: 32),
                font: .monospacedDigitSystemFont(ofSize: 24, weight: .semibold),
                color: accent,
                alignment: .right
            )

            drawText(
                state.statusText,
                in: CGRect(x: 28, y: 74, width: size.width - 56, height: 30),
                font: .systemFont(ofSize: 20, weight: .medium),
                color: UIColor(white: 0.85, alpha: 1)
            )

            let panelTop: CGFloat = 116
            let panelHeight: CGFloat = 94
            let panelWidth = (size.width - 84) / 2
            drawPanel(
                title: "左侧敌方",
                body: state.leftSummary,
                rect: CGRect(x: 28, y: panelTop, width: panelWidth, height: panelHeight),
                accent: UIColor(red: 0.33, green: 0.73, blue: 0.94, alpha: 1)
            )
            drawPanel(
                title: "右侧敌方",
                body: state.rightSummary,
                rect: CGRect(x: 56 + panelWidth, y: panelTop, width: panelWidth, height: panelHeight),
                accent: UIColor(red: 0.94, green: 0.42, blue: 0.36, alpha: 1)
            )

            drawText(
                "候选推断",
                in: CGRect(x: 28, y: 228, width: 180, height: 28),
                font: .systemFont(ofSize: 20, weight: .bold),
                color: accent
            )

            let candidateText = state.candidates.isEmpty
                ? "暂无足够情报"
                : state.candidates.prefix(3).joined(separator: "   ")
            drawText(
                candidateText,
                in: CGRect(x: 28, y: 262, width: size.width - 56, height: 70),
                font: .systemFont(ofSize: 21, weight: .medium),
                color: .white
            )
        }
    }

    private static func drawPanel(title: String, body: String, rect: CGRect, accent: UIColor) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 12)
        UIColor(white: 1, alpha: 0.08).setFill()
        path.fill()

        accent.setFill()
        UIBezierPath(roundedRect: CGRect(x: rect.minX, y: rect.minY, width: 6, height: rect.height), cornerRadius: 3).fill()

        drawText(
            title,
            in: CGRect(x: rect.minX + 18, y: rect.minY + 12, width: rect.width - 30, height: 26),
            font: .systemFont(ofSize: 18, weight: .semibold),
            color: accent
        )
        drawText(
            body,
            in: CGRect(x: rect.minX + 18, y: rect.minY + 42, width: rect.width - 30, height: 44),
            font: .systemFont(ofSize: 17, weight: .regular),
            color: UIColor(white: 0.92, alpha: 1)
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
