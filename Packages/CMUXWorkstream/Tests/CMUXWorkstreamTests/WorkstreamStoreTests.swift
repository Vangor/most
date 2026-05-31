import Foundation
import Testing
@testable import CMUXWorkstream

@MainActor
@Suite("WorkstreamStore")
struct WorkstreamStoreTests {
    @Test("ingest creates a pending item for permission requests")
    func ingestPending() {
        let store = WorkstreamStore(ringCapacity: 10)
        store.ingest(.permission("s1", requestId: "r1"))
        #expect(store.items.count == 1)
        #expect(store.pending.count == 1)
        #expect(store.items[0].kind == .permissionRequest)
    }

    @Test("send(.approvePermission) marks the item resolved")
    func resolvePermission() async throws {
        let store = WorkstreamStore(ringCapacity: 10)
        store.ingest(.permission("s1", requestId: "r1"))
        let itemId = store.items[0].id
        try await store.send(.approvePermission(itemId: itemId, mode: .once))
        #expect(store.pending.isEmpty)
        if case .resolved(let decision, _) = store.items[0].status {
            #expect(decision == .permission(.once))
        } else {
            Issue.record("expected .resolved status")
        }
    }

    @Test("Ring buffer evicts oldest items past capacity")
    func ringEviction() {
        let store = WorkstreamStore(ringCapacity: 3)
        for i in 0..<5 {
            store.ingest(.permission("s\(i)", requestId: "r\(i)"))
        }
        #expect(store.items.count == 3)
        #expect(store.items.first?.workstreamId == "s2")
        #expect(store.items.last?.workstreamId == "s4")
    }

    @Test("start loads a small recent slice and pages older persisted rows on demand")
    func lazyLoadPersistedHistory() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-workstream-store-page-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let persistence = WorkstreamPersistence(fileURL: tmp)
        for i in 0..<5 {
            try await persistence.append(WorkstreamItem(
                workstreamId: "s\(i)",
                source: .claude,
                kind: .permissionRequest,
                payload: .permissionRequest(requestId: "r\(i)", toolName: "t", toolInputJSON: "{}", pattern: nil)
            ))
        }

        let store = WorkstreamStore(
            persistence: persistence,
            ringCapacity: 10,
            initialLoadLimit: 2,
            historyPageSize: 2
        )
        await store.start()
        #expect(store.items.map(\.workstreamId) == ["s3", "s4"])
        #expect(store.hasMorePersistedItems)

        await store.loadOlderItems()
        #expect(store.items.map(\.workstreamId) == ["s1", "s2", "s3", "s4"])
        #expect(store.hasMorePersistedItems)

        await store.loadOlderItems()
        #expect(store.items.map(\.workstreamId) == ["s0", "s1", "s2", "s3", "s4"])
        #expect(!store.hasMorePersistedItems)
    }

    @Test("expireAbandonedItems expires items whose agent PID is dead")
    func expireAbandoned() {
        let clock = TestClock(initial: Date(timeIntervalSince1970: 0))
        let store = WorkstreamStore(ringCapacity: 10, clock: { clock.now })
        // Alive agent (pid=1000), dead agent (pid=2000).
        store.ingest(.permission("alive", requestId: "r1", at: clock.now, ppid: 1000))
        store.ingest(.permission("dead", requestId: "r2", at: clock.now, ppid: 2000))
        store.ingest(.permission("untracked", requestId: "r3", at: clock.now))
        // Injected liveness: only 1000 is alive.
        store.expireAbandonedItems { pid in pid == 1000 }
        #expect(store.items.count == 3)
        #expect(store.items[0].status.isPending)
        if case .expired = store.items[1].status {} else {
            Issue.record("dead-pid item should be expired")
        }
        // Item with no ppid: no change (we don't know liveness).
        #expect(store.items[2].status.isPending)
    }

    @Test("expirePending moves stale pending items to expired")
    func expirePending() {
        let clock = TestClock(initial: Date(timeIntervalSince1970: 0))
        let store = WorkstreamStore(ringCapacity: 10, clock: { clock.now })
        store.ingest(.permission("s1", requestId: "r1", at: clock.now))
        clock.advance(200)
        store.expirePending(olderThan: 60)
        if case .expired = store.items[0].status {
            // ok
        } else {
            Issue.record("expected .expired status after timeout")
        }
    }

    @Test("expireStalePending expires only old pending items that are not locally alive")
    func expireStalePending() {
        let clock = TestClock(initial: Date(timeIntervalSince1970: 0))
        let ttl: TimeInterval = 60
        let store = WorkstreamStore(ringCapacity: 10, clock: { clock.now })

        store.ingest(.permission("remote-old", requestId: "r1", at: clock.now))
        store.ingest(.permission("local-live", requestId: "r3", at: clock.now, ppid: 1000))
        store.ingest(.permission("local-dead", requestId: "r4", at: clock.now, ppid: 2000))
        clock.advance(ttl + 1)
        store.ingest(.permission("remote-fresh", requestId: "r2", at: clock.now))

        store.expireStalePending(now: clock.now, ttl: ttl) { pid in pid == 1000 }

        if case .expired = store.items[0].status {
            // ok
        } else {
            Issue.record("remote-old item should expire")
        }
        #expect(store.items[1].status.isPending)
        if case .expired = store.items[2].status {
            // ok
        } else {
            Issue.record("local-dead item should expire")
        }
        #expect(store.items[3].status.isPending)
    }

    @Test("Telemetry items (toolUse) never enter pending")
    func telemetryNeverPending() {
        let store = WorkstreamStore(ringCapacity: 10)
        store.ingest(WorkstreamEvent(
            sessionId: "s1",
            hookEventName: .preToolUse,
            source: "claude",
            toolName: "Read"
        ))
        #expect(store.items.count == 1)
        #expect(store.pending.isEmpty)
        #expect(store.items[0].kind == .toolUse)
    }

    @Test("Telemetry payloads preserve prompt, stop, and todo content")
    func telemetryContent() {
        let store = WorkstreamStore(ringCapacity: 10)
        store.ingest(WorkstreamEvent(
            sessionId: "s1",
            hookEventName: .userPromptSubmit,
            source: "claude",
            toolInputJSON: #"{"prompt":"ship it"}"#
        ))
        store.ingest(WorkstreamEvent(
            sessionId: "s1",
            hookEventName: .stop,
            source: "claude",
            toolInputJSON: #"{"reason":"done"}"#
        ))
        store.ingest(WorkstreamEvent(
            sessionId: "s1",
            hookEventName: .todoWrite,
            source: "claude",
            toolInputJSON: #"{"todos":[{"id":"t1","content":"test","status":"in_progress"}]}"#
        ))

        if case .userPrompt(let text) = store.items[0].payload {
            #expect(text == "ship it")
        } else {
            Issue.record("expected user prompt payload")
        }
        if case .stop(let reason) = store.items[1].payload {
            #expect(reason == "done")
        } else {
            Issue.record("expected stop payload")
        }
        if case .todos(let todos) = store.items[2].payload {
            #expect(todos.first?.content == "test")
            #expect(todos.first?.state == .inProgress)
        } else {
            Issue.record("expected todos payload")
        }
    }

    @Test("Prompt context carries into later permission requests")
    func promptContextCarriesIntoPermission() {
        let store = WorkstreamStore(ringCapacity: 10)
        store.ingest(WorkstreamEvent(
            sessionId: "s1",
            hookEventName: .userPromptSubmit,
            source: "claude",
            toolInputJSON: #"{"prompt":"demo the permission UI"}"#,
            context: WorkstreamContext(permissionMode: "plan")
        ))
        store.ingest(WorkstreamEvent(
            sessionId: "s1",
            hookEventName: .permissionRequest,
            source: "claude",
            toolName: "Bash",
            toolInputJSON: #"{"command":"echo hi"}"#,
            requestId: "r1"
        ))

        #expect(store.items[1].context?.lastUserMessage == "demo the permission UI")
        #expect(store.items[1].context?.permissionMode == "plan")
    }

    @Test("Exit plan context parses plan JSON")
    func exitPlanParsesContext() {
        let store = WorkstreamStore(ringCapacity: 10)
        store.ingest(WorkstreamEvent(
            sessionId: "s1",
            hookEventName: .exitPlanMode,
            source: "claude",
            toolName: "ExitPlanMode",
            toolInputJSON: #"""
            {
              "plan": "# Demo Plan\n\n## Context\nShow the new feed UI.",
              "allowedPrompts": [
                {"tool": "Bash", "prompt": "run reload.sh --tag feedctx"}
              ],
              "planFilePath": "/tmp/demo.md"
            }
            """#,
            context: WorkstreamContext(lastUserMessage: "make a plan"),
            requestId: "plan-1"
        ))

        let item = store.items[0]
        #expect(item.context?.lastUserMessage == "make a plan")
        #expect(item.context?.planSummary == "Show the new feed UI.")
        #expect(item.context?.allowedPrompts.first?.tool == "Bash")
        #expect(item.context?.allowedPrompts.first?.prompt == "run reload.sh --tag feedctx")
    }

    // MARK: - dismiss(id:) tests

    @Test("dismiss(id:) removes a pending item unconditionally")
    func dismissPendingItem() {
        let store = WorkstreamStore(ringCapacity: 10)
        store.ingest(.permission("s1", requestId: "r1"))
        store.ingest(.permission("s1", requestId: "r2"))
        let targetId = store.items[0].id
        #expect(store.items.count == 2)
        #expect(store.items[0].status.isPending)

        store.dismiss(id: targetId)

        #expect(store.items.count == 1)
        #expect(store.items[0].id != targetId)
        // Remaining item is unaffected.
        #expect(store.items[0].status.isPending)
    }

    @Test("dismiss(id:) removes a resolved item")
    func dismissResolvedItem() async throws {
        let store = WorkstreamStore(ringCapacity: 10)
        store.ingest(.permission("s1", requestId: "r1"))
        let itemId = store.items[0].id
        try await store.send(.approvePermission(itemId: itemId, mode: .once))
        #expect(!store.items[0].status.isPending)

        store.dismiss(id: itemId)

        #expect(store.items.isEmpty)
    }

    @Test("dismiss(id:) is a no-op for an unknown id")
    func dismissUnknownId() {
        let store = WorkstreamStore(ringCapacity: 10)
        store.ingest(.permission("s1", requestId: "r1"))
        #expect(store.items.count == 1)

        store.dismiss(id: UUID())

        #expect(store.items.count == 1)
    }

    // MARK: - clearAll() tests

    @Test("clearAll() empties the store including pending items")
    func clearAllRemovesPendingItems() {
        let store = WorkstreamStore(ringCapacity: 10)
        // Mix of pending and telemetry items.
        store.ingest(.permission("s1", requestId: "r1"))
        store.ingest(.permission("s2", requestId: "r2"))
        store.ingest(WorkstreamEvent(
            sessionId: "s1",
            hookEventName: .preToolUse,
            source: "claude",
            toolName: "Read"
        ))
        #expect(store.items.count == 3)
        #expect(store.pending.count == 2)

        store.clearAll()

        #expect(store.items.isEmpty)
        #expect(store.pending.isEmpty)
    }

    @Test("clearAll() on an empty store is a no-op")
    func clearAllEmptyStoreNoOp() {
        let store = WorkstreamStore(ringCapacity: 10)
        store.clearAll()
        #expect(store.items.isEmpty)
    }

    // MARK: - expireItems(forWorkstreamId:) + session-end tests

    @Test("expireItems(forWorkstreamId:) marks matching pending items expired")
    func expireByWorkstreamId() {
        let clock = TestClock(initial: Date(timeIntervalSince1970: 0))
        let store = WorkstreamStore(ringCapacity: 10, clock: { clock.now })
        store.ingest(.permission("ws-a", requestId: "r1", at: clock.now))
        store.ingest(.permission("ws-a", requestId: "r2", at: clock.now))
        store.ingest(.permission("ws-b", requestId: "r3", at: clock.now))

        store.expireItems(forWorkstreamId: "ws-a")

        if case .expired = store.items[0].status {} else {
            Issue.record("ws-a item[0] should be expired")
        }
        if case .expired = store.items[1].status {} else {
            Issue.record("ws-a item[1] should be expired")
        }
        // ws-b item must remain pending — different workstream.
        #expect(store.items[2].status.isPending)
    }

    @Test("expireItems(forWorkstreamId:) leaves already-resolved items unchanged")
    func expireByWorkstreamIdSkipsResolved() async throws {
        let store = WorkstreamStore(ringCapacity: 10)
        store.ingest(.permission("ws-a", requestId: "r1"))
        let itemId = store.items[0].id
        try await store.send(.approvePermission(itemId: itemId, mode: .once))

        store.expireItems(forWorkstreamId: "ws-a")

        // Resolved status must survive: expireItems only touches .pending.
        if case .resolved(let decision, _) = store.items[0].status {
            #expect(decision == .permission(.once))
        } else {
            Issue.record("resolved item should not be overwritten by expireItems(forWorkstreamId:)")
        }
    }

    @Test("ingest of SessionEnd expires pending items for that workstream then clearInactionable removes them")
    func sessionEndExpiresAndClearRemoves() {
        let store = WorkstreamStore(ringCapacity: 10)
        store.ingest(.permission("ws-dying", requestId: "r1"))
        store.ingest(.permission("ws-alive", requestId: "r2"))
        #expect(store.pending.count == 2)

        // Simulate the agent sending a SessionEnd hook event.
        store.ingest(WorkstreamEvent(
            sessionId: "ws-dying",
            hookEventName: .sessionEnd,
            source: "claude"
        ))

        // ws-dying's pending item should now be expired.
        let dyingItem = store.items.first { $0.workstreamId == "ws-dying" && $0.kind == .permissionRequest }
        if let dyingItem {
            if case .expired = dyingItem.status {} else {
                Issue.record("pending item for ws-dying should be expired after SessionEnd")
            }
        } else {
            Issue.record("could not find ws-dying permission item")
        }
        // ws-alive is untouched.
        let aliveItem = store.items.first { $0.workstreamId == "ws-alive" }
        #expect(aliveItem?.status.isPending == true)

        // clearInactionable removes the expired item + the sessionEnd telemetry,
        // but leaves ws-alive's pending item.
        store.clearInactionable()
        #expect(store.items.count == 1)
        #expect(store.items[0].workstreamId == "ws-alive")
        #expect(store.items[0].status.isPending)
    }
}

/// Mutable clock wrapper safe to capture by a `@Sendable` closure in tests.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date
    init(initial: Date) { _now = initial }
    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return _now
    }
    func advance(_ seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        _now = _now.addingTimeInterval(seconds)
    }
}

private extension WorkstreamEvent {
    static func permission(
        _ sessionId: String,
        requestId: String,
        at date: Date = Date(),
        ppid: Int? = nil
    ) -> WorkstreamEvent {
        WorkstreamEvent(
            sessionId: sessionId,
            hookEventName: .permissionRequest,
            source: "claude",
            cwd: "/tmp",
            toolName: "Write",
            toolInputJSON: "{}",
            requestId: requestId,
            ppid: ppid,
            receivedAt: date
        )
    }
}
