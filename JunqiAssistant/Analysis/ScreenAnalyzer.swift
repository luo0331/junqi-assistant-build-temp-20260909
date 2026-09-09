import Foundation
import Vision
import CoreVideo

final class ScreenAnalyzer {
    private let queue = DispatchQueue(label: "com.junqi.assistant.vision", qos: .userInitiated)
    private let boardTracker = BoardTracker()
    private var lastStep: Int?
    private var lastOCRTime = Date.distantPast
    private var lastBoardDetectionTime = Date.distantPast
    private var cachedBoardDetection: BoardDetection?
    private var cachedStep: Int?
    private var cachedPieces: [DetectedPiece] = []
    private var cachedRecognizedPieces: [RecognizedBoardPiece] = []
    private var cachedRawText = ""
    private var lastOCRErrorText: String?

    func reset() {
        queue.async {
            self.boardTracker.reset()
            self.lastStep = nil
            self.lastOCRTime = .distantPast
            self.lastBoardDetectionTime = .distantPast
            self.cachedBoardDetection = nil
            self.cachedStep = nil
            self.cachedPieces.removeAll()
            self.cachedRecognizedPieces.removeAll()
            self.cachedRawText = ""
            self.lastOCRErrorText = nil
        }
    }

    func analyze(pixelBuffer: CVPixelBuffer) async -> ScreenSnapshot {
        await withCheckedContinuation { continuation in
            queue.async {
                let snapshot = self.recognize(pixelBuffer: pixelBuffer)
                continuation.resume(returning: snapshot)
            }
        }
    }

    private func recognize(pixelBuffer: CVPixelBuffer) -> ScreenSnapshot {
        let now = Date()
        let detection: BoardDetection
        if let cachedBoardDetection,
           now.timeIntervalSince(lastBoardDetectionTime) < 1.0 {
            detection = cachedBoardDetection
        } else {
            detection = BoardDetector.detect(in: pixelBuffer)
            cachedBoardDetection = detection
            lastBoardDetectionTime = now
        }
        let shouldRunOCR = now.timeIntervalSince(lastOCRTime) >= 1.0
            || cachedRawText.isEmpty

        if shouldRunOCR {
            lastOCRTime = now
            runOCR(pixelBuffer: pixelBuffer, boardRect: detection.rect)
        }

        if let step = cachedStep {
            if step <= 1, lastStep != step {
                boardTracker.reset()
            }
            lastStep = step
        }

        let rawText = lastOCRErrorText ?? cachedRawText
        let board = analyzeBoard(
            pixelBuffer: pixelBuffer,
            detection: detection,
            recognized: cachedRecognizedPieces
        )
        return ScreenSnapshot(
            step: cachedStep,
            rawText: rawText,
            pieces: cachedPieces,
            board: board,
            capturedAt: Date()
        )
    }

    private func runOCR(
        pixelBuffer: CVPixelBuffer,
        boardRect: CGRect
    ) {
        // 全屏 OCR 只用于读取步数，不把微信界面或画中画文字混入棋子结果。
        let stepRequest = VNRecognizeTextRequest()
        stepRequest.recognitionLevel = .fast
        stepRequest.recognitionLanguages = ["zh-Hans", "en-US"]
        stepRequest.usesLanguageCorrection = false
        stepRequest.minimumTextHeight = 0.012

        // 棋子 OCR 只扫描棋盘区域，减少系统文字和画中画造成的自我识别。
        let boardRequest = VNRecognizeTextRequest()
        boardRequest.recognitionLevel = .accurate
        boardRequest.recognitionLanguages = ["zh-Hans", "en-US"]
        boardRequest.usesLanguageCorrection = false
        boardRequest.minimumTextHeight = 0.005
        boardRequest.regionOfInterest = visionRegion(
            for: boardRect,
            pixelBuffer: pixelBuffer
        )

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([stepRequest, boardRequest])
        } catch {
            lastOCRErrorText = "OCR失败：\(error.localizedDescription)"
            return
        }

        let stepObservations = (stepRequest.results as? [VNRecognizedTextObservation]) ?? []
        let boardObservations = (boardRequest.results as? [VNRecognizedTextObservation]) ?? []
        let stepText = stepObservations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
        let step = parseStep(from: stepText)

        var pieces: [DetectedPiece] = []
        for observation in boardObservations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
            let tokens = text
                .split(whereSeparator: { $0.isWhitespace })
                .map(String.init)
            let matchTexts = tokens.isEmpty ? [text] : tokens

            for matchText in matchTexts {
                for kind in PieceKind.match(matchText) {
                    pieces.append(
                        DetectedPiece(
                            kind: kind,
                            text: matchText,
                            normalizedRect: observation.boundingBox
                        )
                    )
                }
            }
        }

        cachedStep = step
        cachedPieces = pieces
        cachedRawText = makeDisplayText(step: step, pieces: pieces)
        cachedRecognizedPieces = pieces.compactMap { piece -> RecognizedBoardPiece? in
            guard let point = BoardTracker.boardPoint(
                forRelativeX: piece.normalizedRect.midX,
                y: piece.normalizedRect.midY
            ) else {
                return nil
            }
            return RecognizedBoardPiece(kind: piece.kind, point: point)
        }
        lastOCRErrorText = nil
    }

    private func analyzeBoard(
        pixelBuffer: CVPixelBuffer,
        detection: BoardDetection,
        recognized: [RecognizedBoardPiece]
    ) -> BoardSnapshot? {
        // 步数只用于显示和重置，不能阻塞棋盘跟踪。
        // 实战中步数文字经常被动画或画中画遮挡，棋盘变化仍然必须继续分析。
        return boardTracker.process(
            pixelBuffer: pixelBuffer,
            boardRect: detection.rect,
            usedFallbackRect: detection.usedFallback,
            recognized: recognized
        )
    }

    private func visionRegion(
        for rect: CGRect,
        pixelBuffer: CVPixelBuffer
    ) -> CGRect {
        let width = max(1, CGFloat(CVPixelBufferGetWidth(pixelBuffer)))
        let height = max(1, CGFloat(CVPixelBufferGetHeight(pixelBuffer)))
        let region = CGRect(
            x: rect.minX / width,
            y: 1 - rect.maxY / height,
            width: rect.width / width,
            height: rect.height / height
        )
        return region
            .insetBy(dx: -0.01, dy: -0.01)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private func makeDisplayText(step: Int?, pieces: [DetectedPiece]) -> String {
        var lines: [String] = []
        if let step {
            lines.append("第\(step)步")
        }

        let uniqueNames = Array(Set(pieces.map(\.kind.name))).sorted()
        if !uniqueNames.isEmpty {
            lines.append("棋盘识别：" + uniqueNames.joined(separator: "、"))
        } else {
            lines.append("棋盘内暂未识别到棋子文字")
        }
        return lines.joined(separator: "\n")
    }

    private func parseStep(from text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: "第\\s*(\\d+)\\s*步") else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else {
            return nil
        }
        guard let stepRange = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[stepRange])
    }
}

