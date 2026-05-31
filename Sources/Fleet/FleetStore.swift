import Foundation

@MainActor
final class FleetStore: ObservableObject {
    @Published private(set) var missions: [FleetMission] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isOffline: Bool = false

    static let shared = FleetStore()

    private var pollTask: Task<Void, Never>?
    private let pollInterval: TimeInterval = 8

    var knowledgeEndpoint: String {
        UserDefaults.standard.string(forKey: "fleet.knowledgeEndpoint") ?? "http://knowledge.4et.dev"
    }

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.reload()
                try? await Task.sleep(nanoseconds: UInt64((self?.pollInterval ?? 8) * 1_000_000_000))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func reload() async {
        guard let url = URL(string: "\(knowledgeEndpoint)/mcp") else { return }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": [
                "name": "tasks_query",
                "arguments": [
                    "limit": 200
                ]
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        request.httpBody = data

        do {
            let (responseData, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(FleetTasksQueryResponse.self, from: responseData)
            guard let text = decoded.result?.content.first(where: { $0.type == "text" })?.text,
                  let jsonData = text.data(using: .utf8) else {
                isOffline = true
                return
            }
            let wireTasks = try JSONDecoder().decode([FleetWireTask].self, from: jsonData)
            missions = wireTasks.toMissions()
            lastUpdated = Date()
            isOffline = false
        } catch {
            isOffline = true
        }
    }
}
