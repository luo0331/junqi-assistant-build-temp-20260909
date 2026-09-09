import Foundation
import Combine
import UIKit

@MainActor
final class AssistantViewModel: ObservableObject {
    @Published private(set) var statusText = "等待启动"
    @Published private(set) var ocrText = ""
    @Published private(set) var stepText = "未识别"
    @Published private(set) var knownPiecesText = "暂无"
    @Published private(set) var inferenceText = "暂无候选情报"
    @Published private(set) var isRunning = false

    @Published var leftOpponent = OpponentState()
    @Published var rightOpponent = OpponentState()
    @Published var events: [GameEvent] = []

    let pip = PiPController()

    private let server = LocalFrameServer()
    private let analyzer = ScreenAnalyzer()
    private let inferenceEngine = InferenceEngine()
    private var currentStep: Int?
    private var isAnalyzing = false

    func start() {
        guard !isRunning else { return }

        do {
            try server.start(
                onStatus: { [weak self] text in
                    self?.statusText = text
                },
                onFrame: { [weak self] data in
                    self?.handleFrame(data)
                }
            )
            isRunning = true
            statusText = "等待控制中心开始录屏"
            pip.start()
            updateOverlay()
        } catch {
            statusText = "启动失败：\(error.localizedDescription)"
        }
    }

    func stop() {
        server.stop()
        pip.stop()
        isRunning = false
        statusText = "已停止"
        updateOverlay()
    }

    func addEvent(_ event: GameEvent) {
        events.append(event)
        updateOverlay()
    }

    func clearEvents() {
        events.removeAll()
        updateOverlay()
    }

    private func handleFrame(_ data: Data) {
        guard !isAnalyzing else { return }
        guard let pixelBuffer = data.toCVPixelBuffer() else {
            statusText = "收到画面但解码失败"
            return
        }

        isAnalyzing = true
        Task {
            let snapshot = await analyzer.analyze(pixelBuffer: pixelBuffer)
            await MainActor.run {
                self.apply(snapshot)
                self.isAnalyzing = false
            }
        }
    }

    private func apply(_ snapshot: ScreenSnapshot) {
        currentStep = snapshot.step
        ocrText = snapshot.rawText
        stepText = snapshot.step.map { "第\($0)步" } ?? "未识别"
        knownPiecesText = summarize(pieces: snapshot.pieces)
        statusText = snapshot.rawText.isEmpty ? "录屏中，等待可识别文字" : "正在分析"
        updateOverlay()
    }

    private func updateOverlay() {
        let leftInferences = inferenceEngine.infer(
            opponent: leftOpponent,
            side: .left,
            events: events
        )
        let rightInferences = inferenceEngine.infer(
            opponent: rightOpponent,
            side: .right,
            events: events
        )

        let candidateLines = (leftInferences + rightInferences)
            .prefix(3)
            .flatMap { inference in
                inference.candidates.prefix(3).map {
                    "\(inference.side.title)\(inference.contactID)：\($0.kind.name)\(Int(($0.probability * 100).rounded()))%"
                }
            }

        inferenceText = candidateLines.isEmpty
            ? "暂无候选情报"
            : candidateLines.joined(separator: "\n")

        pip.update(
            state: OverlayState(
                statusText: statusText,
                step: currentStep,
                leftSummary: summary(for: leftOpponent),
                rightSummary: summary(for: rightOpponent),
                candidates: Array(candidateLines.prefix(3))
            )
        )
    }

    private func summary(for opponent: OpponentState) -> String {
        let unknownTotal = PieceKind.allCases.reduce(0) { $0 + opponent.unknownCount($1) }
        let revealedTotal = PieceKind.allCases.reduce(0) { $0 + opponent.revealedCount($1) }
        return "未知\(unknownTotal)枚  明牌\(revealedTotal)枚"
    }

    private func summarize(pieces: [DetectedPiece]) -> String {
        guard !pieces.isEmpty else { return "暂无" }
        let counts = Dictionary(grouping: pieces, by: \.kind).mapValues { $0.count }
        return PieceKind.allCases.compactMap { kind in
            guard let count = counts[kind] else { return nil }
            return "\(kind.name)\(count)"
        }
        .joined(separator: "  ")
    }
}

