import CoreGraphics
import Foundation

enum PieceKind: String, CaseIterable, Codable, Identifiable, Hashable {
    case flag
    case commander
    case armyCommander
    case divisionCommander
    case brigadeCommander
    case regimentCommander
    case battalionCommander
    case companyCommander
    case platoonCommander
    case engineer
    case mine
    case bomb

    var id: String { rawValue }

    var name: String {
        switch self {
        case .flag: return "军旗"
        case .commander: return "司令"
        case .armyCommander: return "军长"
        case .divisionCommander: return "师长"
        case .brigadeCommander: return "旅长"
        case .regimentCommander: return "团长"
        case .battalionCommander: return "营长"
        case .companyCommander: return "连长"
        case .platoonCommander: return "排长"
        case .engineer: return "工兵"
        case .mine: return "地雷"
        case .bomb: return "炸弹"
        }
    }

    var shortName: String {
        switch self {
        case .flag: return "旗"
        case .commander: return "司"
        case .armyCommander: return "军"
        case .divisionCommander: return "师"
        case .brigadeCommander: return "旅"
        case .regimentCommander: return "团"
        case .battalionCommander: return "营"
        case .companyCommander: return "连"
        case .platoonCommander: return "排"
        case .engineer: return "兵"
        case .mine: return "雷"
        case .bomb: return "炸"
        }
    }

    var totalCount: Int {
        switch self {
        case .commander, .armyCommander, .flag: return 1
        case .divisionCommander, .brigadeCommander, .regimentCommander, .battalionCommander, .bomb: return 2
        case .companyCommander, .platoonCommander, .engineer, .mine: return 3
        }
    }

    var rank: Int {
        switch self {
        case .commander: return 13
        case .armyCommander: return 12
        case .divisionCommander: return 11
        case .brigadeCommander: return 10
        case .regimentCommander: return 9
        case .battalionCommander: return 8
        case .companyCommander: return 7
        case .platoonCommander: return 6
        case .engineer: return 5
        case .mine: return 1
        case .flag: return 0
        case .bomb: return 0
        }
    }

    var movable: Bool {
        switch self {
        case .flag, .mine: return false
        default: return true
        }
    }

    var aliases: [String] {
        switch self {
        case .flag: return ["军旗", "旗"]
        case .commander: return ["司令", "司"]
        case .armyCommander: return ["军长", "军"]
        case .divisionCommander: return ["师长", "师"]
        case .brigadeCommander: return ["旅长", "旅"]
        case .regimentCommander: return ["团长", "团"]
        case .battalionCommander: return ["营长", "营"]
        case .companyCommander: return ["连长", "连"]
        case .platoonCommander: return ["排长", "排"]
        case .engineer: return ["工兵", "兵"]
        case .mine: return ["地雷", "雷"]
        case .bomb: return ["炸弹", "炸", "弹"]
        }
    }

    static func match(_ text: String) -> [PieceKind] {
        let normalized = text.replacingOccurrences(of: " ", with: "")
        guard !normalized.isEmpty else { return [] }

        var result = Set<PieceKind>()
        for kind in PieceKind.allCases {
            for alias in kind.aliases {
                if normalized == alias {
                    result.insert(kind)
                    break
                }

                if alias.count >= 2, normalized.hasPrefix(alias) {
                    let suffix = normalized.dropFirst(alias.count)
                    if !suffix.isEmpty, suffix.allSatisfy({ $0.isNumber }) {
                        result.insert(kind)
                        break
                    }
                }
            }
        }
        return Array(result)
    }
}

enum EnemySide: String, CaseIterable, Codable, Identifiable {
    case left
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: return "左侧敌方"
        case .right: return "右侧敌方"
        }
    }
}

struct OpponentState: Codable {
    var dead: [PieceKind: Int] = [:]
    var revealed: [PieceKind: Int] = [:]

    func count(_ kind: PieceKind, in dictionary: [PieceKind: Int]) -> Int {
        dictionary[kind, default: 0]
    }

    func deadCount(_ kind: PieceKind) -> Int {
        count(kind, in: dead)
    }

    func revealedCount(_ kind: PieceKind) -> Int {
        count(kind, in: revealed)
    }

    func unknownCount(_ kind: PieceKind) -> Int {
        max(0, kind.totalCount - deadCount(kind) - revealedCount(kind))
    }

    mutating func setDead(_ kind: PieceKind, count: Int) {
        dead[kind] = min(max(0, count), kind.totalCount)
    }

    mutating func setRevealed(_ kind: PieceKind, count: Int) {
        revealed[kind] = min(max(0, count), kind.totalCount)
    }

    mutating func reset() {
        dead.removeAll()
        revealed.removeAll()
    }
}

struct GameEvent: Identifiable, Codable, Hashable {
    enum Source: String, Codable, CaseIterable {
        case enemyMoved
        case enemyStationary
        case unknown

        var title: String {
            switch self {
            case .enemyMoved: return "敌方主动吃我方"
            case .enemyStationary: return "我方主动碰敌方"
            case .unknown: return "不确定"
            }
        }
    }

    enum Result: String, Codable, CaseIterable {
        case enemySurvived
        case bothDead
        case enemyDeadOursSurvived
        case enemyDeadUnknown

        var title: String {
            switch self {
            case .enemySurvived: return "敌方存活，我方被吃"
            case .bothDead: return "双方同归于尽"
            case .enemyDeadOursSurvived: return "敌方被吃，我方存活"
            case .enemyDeadUnknown: return "敌方被吃，我方结果不确定"
            }
        }
    }

    var id: UUID = UUID()
    var side: EnemySide
    var contactID: String
    var ourPiece: PieceKind
    var source: Source
    var result: Result
    var createdAt: Date = Date()
}

struct DetectedPiece: Identifiable {
    var id: UUID = UUID()
    var kind: PieceKind
    var text: String
    var normalizedRect: CGRect
}

struct ScreenSnapshot {
    var step: Int?
    var rawText: String
    var pieces: [DetectedPiece]
    var capturedAt: Date
}

struct OverlayState {
    var statusText: String
    var step: Int?
    var leftSummary: String
    var rightSummary: String
    var candidates: [String]

    static let idle = OverlayState(
        statusText: "等待录屏画面",
        step: nil,
        leftSummary: "左侧：未识别",
        rightSummary: "右侧：未识别",
        candidates: ["启动录屏后自动分析"]
    )
}




