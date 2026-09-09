import SwiftUI

struct FourPlayerBoardView: View {
    @EnvironmentObject private var model: AssistantViewModel

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    board
                    legend
                }
                .padding(16)
            }
            .background(Color(red: 0.95, green: 0.96, blue: 0.98))
            .navigationTitle("四方棋盘")
        }
        .navigationViewStyle(.stack)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("全盘状态")
                    .font(.headline)
                Spacer()
                Text(readinessText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(readinessColor)
            }

            Text(model.liveStateText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                statusBadge(
                    title: "我方",
                    count: model.oursBoardRecord.occupiedCount,
                    color: Color(red: 0.12, green: 0.38, blue: 0.72)
                )
                statusBadge(
                    title: "队友",
                    count: model.teammateBoardRecord.occupiedCount,
                    color: Color(red: 0.10, green: 0.54, blue: 0.34)
                )
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var board: some View {
        Canvas { context, size in
            drawBoard(context: context, size: size)
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(6)
        .background(Color(red: 0.08, green: 0.12, blue: 0.18))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("队友在上 · 我方在下 · 左敌和右敌在左右")
                .font(.caption.weight(.semibold))
            Text("只显示导入棋谱和已经确认的棋子；中央区域不绘制随机点。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var readinessText: String {
        let oursReady = model.oursBoardRecord.validation.isValid
        let teammateReady = model.teammateBoardRecord.validation.isValid
        return oursReady && teammateReady ? "导入完成" : "等待完善"
    }

    private var readinessColor: Color {
        let oursReady = model.oursBoardRecord.validation.isValid
        let teammateReady = model.teammateBoardRecord.validation.isValid
        return oursReady && teammateReady ? .green : .secondary
    }

    private func statusBadge(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: count == 25 ? "checkmark.circle.fill" : "circle")
            Text("\(title) \(count)/25")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(count > 0 ? color : .secondary)
    }

    private func drawBoard(context: GraphicsContext, size: CGSize) {
        let gridSize = BoardTracker.gridSize
        let side = min(size.width, size.height)
        let cell = side / CGFloat(gridSize)
        let origin = CGPoint(
            x: (size.width - side) / 2,
            y: (size.height - side) / 2
        )

        context.fill(
            Path(CGRect(x: origin.x, y: origin.y, width: side, height: side)),
            with: .color(Color(red: 0.10, green: 0.15, blue: 0.22))
        )

        for index in 0...gridSize {
            let position = CGFloat(index) * cell

            var vertical = Path()
            vertical.move(to: CGPoint(x: origin.x + position, y: origin.y))
            vertical.addLine(to: CGPoint(x: origin.x + position, y: origin.y + side))
            context.stroke(
                vertical,
                with: .color(.white.opacity(0.24)),
                lineWidth: 0.7
            )

            var horizontal = Path()
            horizontal.move(to: CGPoint(x: origin.x, y: origin.y + position))
            horizontal.addLine(to: CGPoint(x: origin.x + side, y: origin.y + position))
            context.stroke(
                horizontal,
                with: .color(.white.opacity(0.24)),
                lineWidth: 0.7
            )
        }

        let borderRect = CGRect(
            x: origin.x,
            y: origin.y,
            width: side,
            height: side
        )
        context.stroke(
            Path(borderRect),
            with: .color(Color(red: 0.95, green: 0.72, blue: 0.24)),
            lineWidth: 2.5
        )

        drawZoneOutline(
            context: context,
            origin: origin,
            cell: cell,
            rowRange: 0...5,
            colRange: 6...10,
            color: Color(red: 0.10, green: 0.54, blue: 0.34)
        )
        drawZoneOutline(
            context: context,
            origin: origin,
            cell: cell,
            rowRange: 11...16,
            colRange: 6...10,
            color: Color(red: 0.12, green: 0.38, blue: 0.72)
        )
        drawZoneOutline(
            context: context,
            origin: origin,
            cell: cell,
            rowRange: 6...10,
            colRange: 0...5,
            color: Color(red: 0.86, green: 0.24, blue: 0.20)
        )
        drawZoneOutline(
            context: context,
            origin: origin,
            cell: cell,
            rowRange: 6...10,
            colRange: 11...16,
            color: Color(red: 0.95, green: 0.48, blue: 0.12)
        )

        drawCamps(context: context, origin: origin, cell: cell)
        drawEnemyPlaceholders(context: context, origin: origin, cell: cell)
        drawEnemyBacks(context: context, origin: origin, cell: cell)
        drawConfirmedPieces(context: context, origin: origin, cell: cell)
    }

    private func drawZoneOutline(
        context: GraphicsContext,
        origin: CGPoint,
        cell: CGFloat,
        rowRange: ClosedRange<Int>,
        colRange: ClosedRange<Int>,
        color: Color
    ) {
        let rect = CGRect(
            x: origin.x + CGFloat(colRange.lowerBound) * cell,
            y: origin.y + CGFloat(rowRange.lowerBound) * cell,
            width: CGFloat(colRange.count) * cell,
            height: CGFloat(rowRange.count) * cell
        )
        context.stroke(
            Path(rect),
            with: .color(color.opacity(0.75)),
            lineWidth: 1.5
        )
    }

    private func drawEnemyPlaceholders(
        context: GraphicsContext,
        origin: CGPoint,
        cell: CGFloat
    ) {
        guard model.enemyBacks.isEmpty else { return }

        for side in [BoardSide.leftEnemy, .rightEnemy] {
            for row in 0..<BoardLayout.rows {
                for col in 0..<BoardLayout.columns where !BoardLayout.isCamp(row: row, col: col) {
                    guard let point = globalPoint(
                        for: BoardLayout.key(row: row, col: col),
                        side: side
                    ) else {
                        continue
                    }
                    let inset = max(1, cell * 0.13)
                    let rect = CGRect(
                        x: origin.x + CGFloat(point.col) * cell + inset,
                        y: origin.y + CGFloat(point.row) * cell + inset,
                        width: cell - inset * 2,
                        height: cell - inset * 2
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: cell * 0.18),
                        with: .color(Color(red: 0.22, green: 0.25, blue: 0.31).opacity(0.52))
                    )
                }
            }
        }
    }

    private func drawEnemyBacks(
        context: GraphicsContext,
        origin: CGPoint,
        cell: CGFloat
    ) {
        for point in model.enemyBacks {
            let inset = max(1, cell * 0.10)
            let rect = CGRect(
                x: origin.x + CGFloat(point.col) * cell + inset,
                y: origin.y + CGFloat(point.row) * cell + inset,
                width: cell - inset * 2,
                height: cell - inset * 2
            )
            context.fill(
                Path(roundedRect: rect, cornerRadius: cell * 0.20),
                with: .color(Color(red: 0.24, green: 0.28, blue: 0.34))
            )
            context.stroke(
                Path(roundedRect: rect, cornerRadius: cell * 0.20),
                with: .color(.white.opacity(0.32)),
                lineWidth: 0.7
            )
        }
    }

    private func drawCamps(
        context: GraphicsContext,
        origin: CGPoint,
        cell: CGFloat
    ) {
        for point in allCampPoints {
            let center = self.center(for: point, origin: origin, cell: cell)
            let radius = max(1.5, cell * 0.18)
            let rect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(
                Path(ellipseIn: rect),
                with: .color(.white.opacity(0.42))
            )
        }
    }

    private func drawConfirmedPieces(
        context: GraphicsContext,
        origin: CGPoint,
        cell: CGFloat
    ) {
        for (point, kind) in confirmedPieces {
            let inset = max(1, cell * 0.10)
            let rect = CGRect(
                x: origin.x + CGFloat(point.col) * cell + inset,
                y: origin.y + CGFloat(point.row) * cell + inset,
                width: cell - inset * 2,
                height: cell - inset * 2
            )
            let side = BoardTracker.side(for: point)
            context.fill(
                Path(roundedRect: rect, cornerRadius: cell * 0.20),
                with: .color(color(for: side))
            )

            let text = Text(kind.shortName)
                .font(.system(size: max(6, cell * 0.48), weight: .bold))
                .foregroundColor(.white)
            context.draw(
                text,
                at: CGPoint(x: rect.midX, y: rect.midY),
                anchor: .center
            )
        }
    }

    private var confirmedPieces: [BoardPoint: PieceKind] {
        model.confirmedPieces
    }

    private var allCampPoints: Set<BoardPoint> {
        var result = Set<BoardPoint>()
        for side in [BoardSide.ours, .teammate, .leftEnemy, .rightEnemy] {
            for key in BoardLayout.campKeys {
                if let point = globalPoint(for: key, side: side) {
                    result.insert(point)
                }
            }
        }
        return result
    }

    private func globalPoint(
        for localKey: String,
        side: BoardSide
    ) -> BoardPoint? {
        let parts = localKey.split(separator: "-")
        guard parts.count == 2,
              let row = Int(parts[0]),
              let col = Int(parts[1]) else {
            return nil
        }

        switch side {
        case .ours:
            return BoardPoint(row: 11 + row, col: 6 + col)
        case .teammate:
            return BoardPoint(row: 5 - row, col: 10 - col)
        case .leftEnemy:
            return BoardPoint(row: 6 + col, col: row)
        case .rightEnemy:
            return BoardPoint(row: 6 + col, col: 11 + row)
        case .center:
            return nil
        }
    }

    private func center(
        for point: BoardPoint,
        origin: CGPoint,
        cell: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: origin.x + (CGFloat(point.col) + 0.5) * cell,
            y: origin.y + (CGFloat(point.row) + 0.5) * cell
        )
    }

    private func color(for side: BoardSide) -> Color {
        switch side {
        case .ours:
            return Color(red: 0.12, green: 0.38, blue: 0.72)
        case .teammate:
            return Color(red: 0.10, green: 0.54, blue: 0.34)
        case .leftEnemy:
            return Color(red: 0.86, green: 0.24, blue: 0.20)
        case .rightEnemy:
            return Color(red: 0.95, green: 0.48, blue: 0.12)
        case .center:
            return .gray
        }
    }
}
