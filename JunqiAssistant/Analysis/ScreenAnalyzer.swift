import Foundation
import Vision
import CoreVideo

final class ScreenAnalyzer {
    private let queue = DispatchQueue(label: "com.junqi.assistant.vision", qos: .userInitiated)

    func analyze(pixelBuffer: CVPixelBuffer) async -> ScreenSnapshot {
        await withCheckedContinuation { continuation in
            queue.async {
                let snapshot = self.recognize(pixelBuffer: pixelBuffer)
                continuation.resume(returning: snapshot)
            }
        }
    }

    private func recognize(pixelBuffer: CVPixelBuffer) -> ScreenSnapshot {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.008

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ScreenSnapshot(
                step: nil,
                rawText: "OCR失败：\(error.localizedDescription)",
                pieces: [],
                capturedAt: Date()
            )
        }

        let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
        var lines: [String] = []
        var pieces: [DetectedPiece] = []

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
            lines.append(text)

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

        let rawText = lines.joined(separator: "\n")
        return ScreenSnapshot(
            step: parseStep(from: rawText),
            rawText: rawText,
            pieces: pieces,
            capturedAt: Date()
        )
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

