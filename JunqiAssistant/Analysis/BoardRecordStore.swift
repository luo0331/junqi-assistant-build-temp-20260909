import Foundation
import UIKit
import Vision

enum BoardOwner: String, CaseIterable, Codable, Identifiable {
    case ours
    case teammate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ours: return "我方棋谱"
        case .teammate: return "队友棋谱"
        }
    }
}

struct ImportedBoardRecord: Codable {
    var owner: BoardOwner
    var cells: [String: PieceKind]
    var updatedAt: Date

    static func empty(owner: BoardOwner) -> ImportedBoardRecord {
        ImportedBoardRecord(owner: owner, cells: [:], updatedAt: Date())
    }

    var occupiedCount: Int {
        cells.count
    }

    func globalPoint(for key: String) -> BoardPoint? {
        let parts = key.split(separator: "-")
        guard parts.count == 2,
              let localRow = Int(parts[0]),
              let localCol = Int(parts[1]) else {
            return nil
        }

        switch owner {
        case .ours:
            return BoardPoint(row: 11 + localRow, col: 6 + localCol)
        case .teammate:
            return BoardPoint(row: 5 - localRow, col: 10 - localCol)
        }
    }
}

enum BoardRecordPersistence {
    private static let oursKey = "junqi.board.record.ours"
    private static let teammateKey = "junqi.board.record.teammate"

    static func load(owner: BoardOwner) -> ImportedBoardRecord {
        let key = owner == .ours ? oursKey : teammateKey
        guard let data = UserDefaults.standard.data(forKey: key),
              var record = try? JSONDecoder().decode(ImportedBoardRecord.self, from: data) else {
            return .empty(owner: owner)
        }
        record.cells = record.cells.filter { !BoardLayout.isCampKey($0.key) }
        return record
    }

    static func save(_ record: ImportedBoardRecord) {
        let key = record.owner == .ours ? oursKey : teammateKey
        guard let data = try? JSONEncoder().encode(record) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

enum BoardImagePersistence {
    private static var directoryURL: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("BoardRecords", isDirectory: true)
    }

    static func load(owner: BoardOwner) -> UIImage? {
        let url = fileURL(owner: owner)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func save(_ image: UIImage, owner: BoardOwner) {
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            guard let data = image.pngData() else { return }
            try data.write(to: fileURL(owner: owner), options: .atomic)
        } catch {
        }
    }

    static func delete(owner: BoardOwner) {
        try? FileManager.default.removeItem(at: fileURL(owner: owner))
    }

    private static func fileURL(owner: BoardOwner) -> URL {
        directoryURL.appendingPathComponent("\(owner.rawValue).png")
    }
}

enum BoardImageImporter {
    static func recognize(
        image: UIImage,
        owner: BoardOwner
    ) async throws -> ImportedBoardRecord {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let record = try recognizeSync(image: image, owner: owner)
                    continuation.resume(returning: record)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func recognizeSync(
        image: UIImage,
        owner: BoardOwner
    ) throws -> ImportedBoardRecord {
        guard let cgImage = image.normalizedForOCR().cgImage else {
            throw BoardImportError.invalidImage
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.008
        request.customWords = PieceKind.allCases.flatMap { [$0.name] + $0.aliases }

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        try handler.perform([request])

        var cells: [String: PieceKind] = [:]
        let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
        for observation in observations {
            guard let kind = recognizedKind(in: observation) else { continue }
            let box = observation.boundingBox
            let col = min(4, max(0, Int(box.midX * 5)))
            let row = min(5, max(0, Int((1 - box.midY) * 6)))
            cells["\(row)-\(col)"] = kind
        }

        // 对 25 个可落子棋位逐个裁切放大识别，弥补整图 OCR 对小棋子的漏识别。
        for row in 0..<BoardLayout.rows {
            for col in 0..<BoardLayout.columns where !BoardLayout.isCamp(row: row, col: col) {
                let key = BoardLayout.key(row: row, col: col)
                if let kind = recognizeCell(
                    cgImage: cgImage,
                    row: row,
                    col: col
                ) {
                    cells[key] = kind
                }
            }
        }

        return ImportedBoardRecord(
            owner: owner,
            cells: cells,
            updatedAt: Date()
        )
    }

    private static func recognizedKind(
        in observation: VNRecognizedTextObservation
    ) -> PieceKind? {
        for candidate in observation.topCandidates(3) {
            let compact = candidate.string
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "\n", with: "")
            for kind in PieceKind.allCases {
                if kind.aliases.contains(where: { compact.contains($0) }) {
                    return kind
                }
            }
        }
        return nil
    }

    private static func recognizeCell(
        cgImage: CGImage,
        row: Int,
        col: Int
    ) -> PieceKind? {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let centerX = (CGFloat(col) + 0.5) / CGFloat(BoardLayout.columns) * width
        let centerY = (CGFloat(row) + 0.5) / CGFloat(BoardLayout.rows) * height
        let cropWidth = width * 0.19
        let cropHeight = height * 0.16
        let cropRect = CGRect(
            x: centerX - cropWidth / 2,
            y: centerY - cropHeight / 2,
            width: cropWidth,
            height: cropHeight
        )
        .integral
        .intersection(CGRect(x: 0, y: 0, width: width, height: height))

        guard !cropRect.isEmpty,
              let cropped = cgImage.cropping(to: cropRect),
              let enlarged = enlarge(cropped, scale: 4) else {
            return nil
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.02
        request.customWords = PieceKind.allCases.flatMap { [$0.name] + $0.aliases }

        let handler = VNImageRequestHandler(cgImage: enlarged, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil else { return nil }

        let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
        return observations.compactMap { recognizedKind(in: $0) }.first
    }

    private static func enlarge(_ image: CGImage, scale: Int) -> CGImage? {
        let width = image.width * scale
        let height = image.height * scale
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

enum BoardImportError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "无法读取棋谱图片"
        }
    }
}

extension UIImage {
    func normalizedForOCR() -> UIImage {
        guard imageOrientation != .up else { return self }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
