import Foundation

struct CandidateProbability: Identifiable {
    var kind: PieceKind
    var probability: Double

    var id: PieceKind { kind }
}

struct ContactInference: Identifiable {
    var contactID: String
    var side: EnemySide
    var candidates: [CandidateProbability]
    var explanation: String

    var id: String { "\(side.rawValue)-\(contactID)" }
}

final class InferenceEngine {
    func infer(
        opponent: OpponentState,
        side: EnemySide,
        events: [GameEvent]
    ) -> [ContactInference] {
        let grouped = Dictionary(grouping: events.filter { $0.side == side }, by: \.contactID)

        return grouped.map { contactID, contactEvents in
            let candidates = PieceKind.allCases.compactMap { kind -> CandidateProbability? in
                let weight = opponent.effectiveUnknownCount(kind)
                guard weight > 0 else { return nil }
                guard contactEvents.allSatisfy({ isPossible(kind, event: $0) }) else { return nil }
                return CandidateProbability(
                    kind: kind,
                    probability: weight
                )
            }

            let total = candidates.reduce(0) { $0 + $1.probability }
            let normalized = candidates
                .map {
                    CandidateProbability(
                        kind: $0.kind,
                        probability: total > 0 ? $0.probability / total : 0
                    )
                }
                .sorted { $0.probability > $1.probability }

            return ContactInference(
                contactID: contactID,
                side: side,
                candidates: normalized,
                explanation: explanation(for: normalized)
            )
        }
        .sorted { $0.contactID < $1.contactID }
    }

    private func explanation(for candidates: [CandidateProbability]) -> String {
        guard let first = candidates.first else {
            return "当前记牌信息与该棋子事件冲突，请检查阵亡或明牌数量。"
        }

        if candidates.count == 1 {
            return "只剩唯一候选：\(first.kind.name)。"
        }

        let names = candidates.prefix(3).map {
            "\($0.kind.name)\(Int(($0.probability * 100).rounded()))%"
        }
        return "候选：" + names.joined(separator: "、")
    }

    private func isPossible(_ piece: PieceKind, event: GameEvent) -> Bool {
        switch event.source {
        case .enemyMoved:
            return isPossible(piece, ourPiece: event.ourPiece, result: event.result, enemyMoved: true)
        case .enemyStationary:
            return isPossible(piece, ourPiece: event.ourPiece, result: event.result, enemyMoved: false)
        case .unknown:
            return isPossible(piece, ourPiece: event.ourPiece, result: event.result, enemyMoved: true)
                || isPossible(piece, ourPiece: event.ourPiece, result: event.result, enemyMoved: false)
        }
    }

    private func isPossible(
        _ enemy: PieceKind,
        ourPiece: PieceKind,
        result: GameEvent.Result,
        enemyMoved: Bool
    ) -> Bool {
        if enemyMoved && !enemy.movable { return false }

        switch result {
        case .enemySurvived:
            if enemy == .bomb || enemy == .flag { return false }
            if ourPiece == .bomb { return false }

            if enemyMoved {
                if ourPiece == .mine {
                    return enemy == .engineer
                }
                if ourPiece == .flag {
                    return true
                }
                return enemy.rank > ourPiece.rank
            } else {
                if enemy == .mine {
                    return ourPiece != .engineer && ourPiece != .bomb
                }
                if ourPiece == .flag {
                    return false
                }
                return enemy.rank > ourPiece.rank
            }

        case .bothDead:
            if enemy == .bomb || ourPiece == .bomb { return true }
            if !enemyMoved && enemy == .mine { return false }
            return enemy.rank == ourPiece.rank

        case .enemyDeadOursSurvived:
            if enemy == .bomb || ourPiece == .bomb { return false }
            if enemy == .mine {
                return ourPiece == .engineer
            }
            if enemy == .flag { return true }
            return enemy.rank < ourPiece.rank

        case .enemyDeadUnknown:
            if enemy == .bomb || ourPiece == .bomb { return true }
            if enemy == .mine {
                return ourPiece == .engineer || ourPiece == .bomb
            }
            if enemy == .flag { return true }
            return enemy.rank <= ourPiece.rank
        }
    }
}
