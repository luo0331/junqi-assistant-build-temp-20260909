import Foundation
import CoreGraphics

enum BoardLayout {
    static let rows = 6
    static let columns = 5
    static let campKeys: Set<String> = [
        "1-1",
        "1-3",
        "2-2",
        "3-1",
        "3-3"
    ]
    static let imageGridRect = CGRect(
        x: 0.069,
        y: 0.016,
        width: 0.876,
        height: 0.950
    )

    static func key(row: Int, col: Int) -> String {
        "\(row)-\(col)"
    }

    static func isCamp(row: Int, col: Int) -> Bool {
        campKeys.contains(key(row: row, col: col))
    }

    static func isCampKey(_ key: String) -> Bool {
        campKeys.contains(key)
    }
}

struct BoardRecordValidation {
    var isValid: Bool
    var occupiedCount: Int
    var issues: [String]

    var statusText: String {
        if isValid {
            return "25/25 合法"
        }
        if issues.isEmpty {
            return "\(occupiedCount)/25"
        }
        return "\(occupiedCount)/25 · " + issues.prefix(2).joined(separator: "、")
    }
}

extension ImportedBoardRecord {
    var validation: BoardRecordValidation {
        let occupiedCount = cells.count
        var issues: [String] = []

        if occupiedCount < 25 {
            issues.append("缺少\(25 - occupiedCount)枚")
        } else if occupiedCount > 25 {
            issues.append("多出\(occupiedCount - 25)枚")
        }

        for kind in PieceKind.allCases {
            let actual = cells.values.filter { $0 == kind }.count
            let expected = kind.totalCount
            if actual != expected {
                issues.append("\(kind.name)\(actual)/\(expected)")
            }
        }

        let occupiedCampCount = cells.keys.filter(BoardLayout.isCampKey).count
        if occupiedCampCount > 0 {
            issues.append("行营内有\(occupiedCampCount)枚棋子")
        }

        return BoardRecordValidation(
            isValid: issues.isEmpty,
            occupiedCount: occupiedCount,
            issues: issues
        )
    }
}
