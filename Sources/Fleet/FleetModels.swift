import Foundation

// MARK: - Wire types (JSON-RPC response)

struct FleetTasksQueryResponse: Decodable {
    struct Result: Decodable {
        let content: [ContentItem]
        struct ContentItem: Decodable {
            let type: String
            let text: String?
        }
    }
    let result: Result?
}

// MARK: - Domain value types (snapshot-boundary safe)

enum FleetTaskStatus: String, Decodable {
    case todo
    case inProgress = "in_progress"
    case done
    case failedValidation = "failed_validation"
    case replanFailed = "replan_failed"
    case blocked

    var displayIcon: String {
        switch self {
        case .todo: return "⏳"
        case .inProgress: return "🔵"
        case .done: return "✅"
        case .failedValidation: return "❌"
        case .replanFailed: return "🔴"
        case .blocked: return "⚠️"
        }
    }
}

struct FleetTask: Identifiable, Equatable {
    let id: String
    let title: String
    let status: FleetTaskStatus
    let lockedBy: String?
    let startedAt: Date?
    let phase: String?

    var elapsedLabel: String? {
        guard status == .inProgress, let started = startedAt else { return nil }
        let seconds = Int(-started.timeIntervalSinceNow)
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
    }
}

struct FleetMission: Identifiable, Equatable {
    let id: String
    let name: String
    let tasks: [FleetTask]

    var doneCount: Int { tasks.filter { $0.status == .done }.count }
    var totalCount: Int { tasks.count }
}

// MARK: - Action bundle (snapshot-boundary closure bundle)

struct FleetMissionRowActions {
    let onJumpToSession: (FleetMission) -> Void
}

struct FleetTaskRowActions {
    let onJumpToSession: (FleetTask) -> Void
}

// MARK: - Wire task (from knowledge JSON)

struct FleetWireTask: Decodable {
    let id: String
    let title: String
    let status: String
    let lockedBy: String?
    let frontmatter: Frontmatter?
    struct Frontmatter: Decodable {
        let epic: String?
        let startedAt: String?
        private enum CodingKeys: String, CodingKey {
            case epic
            case startedAt = "started_at"
        }
    }
    let phase: String?
    let parentId: String?
    private enum CodingKeys: String, CodingKey {
        case id, title, status, lockedBy, frontmatter, phase
        case parentId = "parent_id"
    }
}

// MARK: - Mapping

extension FleetTask {
    static func from(_ wire: FleetWireTask) -> FleetTask {
        let status = FleetTaskStatus(rawValue: wire.status) ?? .todo
        let iso = ISO8601DateFormatter()
        let startedAt: Date? = wire.frontmatter?.startedAt.flatMap { iso.date(from: $0) }
        return FleetTask(
            id: wire.id,
            title: wire.title,
            status: status,
            lockedBy: wire.lockedBy,
            startedAt: startedAt,
            phase: wire.phase
        )
    }
}

extension [FleetWireTask] {
    func toMissions() -> [FleetMission] {
        var buckets: [String: (name: String, tasks: [FleetTask])] = [:]
        var order: [String] = []

        for wire in self {
            let task = FleetTask.from(wire)
            let epicKey = wire.frontmatter?.epic ?? wire.parentId ?? "ungrouped"
            let epicName = wire.frontmatter?.epic ?? "Other"
            if buckets[epicKey] == nil {
                buckets[epicKey] = (name: epicName, tasks: [])
                order.append(epicKey)
            }
            buckets[epicKey]!.tasks.append(task)
        }

        return order.compactMap { key -> FleetMission? in
            guard let bucket = buckets[key] else { return nil }
            return FleetMission(id: key, name: bucket.name, tasks: bucket.tasks)
        }
    }
}
