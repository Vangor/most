import Foundation
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Tests for vault.maxAgeDays and vault.maxEntriesPerAgent config keys.
///
/// Covers:
/// 1. CmuxVaultConfigDefinition decodes valid / invalid / absent values correctly.
/// 2. CmuxVaultAgentRegistry.load() propagates both limits into the registry.
/// 3. SessionIndexStore age-cutoff filter is applied to scanAll-equivalent logic.
final class VaultDisplayLimitsTests: XCTestCase {

    // MARK: - CmuxVaultConfigDefinition decoding

    func testMaxAgeDaysDecodesValidPositiveValue() throws {
        let json = #"{"agents": [], "maxAgeDays": 7}"#
        let decoded = try JSONDecoder().decode(CmuxVaultConfigDefinition.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.maxAgeDays, 7)
    }

    func testMaxEntriesPerAgentDecodesValidPositiveValue() throws {
        let json = #"{"agents": [], "maxEntriesPerAgent": 10}"#
        let decoded = try JSONDecoder().decode(CmuxVaultConfigDefinition.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.maxEntriesPerAgent, 10)
    }

    func testMaxAgeDaysZeroIsIgnoredAsNil() throws {
        // 0 means "no cutoff" — treated the same as absent.
        let json = #"{"agents": [], "maxAgeDays": 0}"#
        let decoded = try JSONDecoder().decode(CmuxVaultConfigDefinition.self, from: Data(json.utf8))
        XCTAssertNil(decoded.maxAgeDays, "maxAgeDays: 0 should be treated as absent (no cutoff)")
    }

    func testMaxEntriesPerAgentZeroIsIgnoredAsNil() throws {
        let json = #"{"agents": [], "maxEntriesPerAgent": 0}"#
        let decoded = try JSONDecoder().decode(CmuxVaultConfigDefinition.self, from: Data(json.utf8))
        XCTAssertNil(decoded.maxEntriesPerAgent, "maxEntriesPerAgent: 0 should be treated as absent")
    }

    func testMaxAgeDaysNegativeIsIgnoredAsNil() throws {
        let json = #"{"agents": [], "maxAgeDays": -5}"#
        let decoded = try JSONDecoder().decode(CmuxVaultConfigDefinition.self, from: Data(json.utf8))
        XCTAssertNil(decoded.maxAgeDays, "negative maxAgeDays should be treated as absent")
    }

    func testMaxEntriesPerAgentNegativeIsIgnoredAsNil() throws {
        let json = #"{"agents": [], "maxEntriesPerAgent": -1}"#
        let decoded = try JSONDecoder().decode(CmuxVaultConfigDefinition.self, from: Data(json.utf8))
        XCTAssertNil(decoded.maxEntriesPerAgent, "negative maxEntriesPerAgent should be treated as absent")
    }

    func testAbsentLimitsDefaultToNil() throws {
        let json = #"{"agents": []}"#
        let decoded = try JSONDecoder().decode(CmuxVaultConfigDefinition.self, from: Data(json.utf8))
        XCTAssertNil(decoded.maxAgeDays)
        XCTAssertNil(decoded.maxEntriesPerAgent)
    }

    // MARK: - CmuxVaultAgentRegistry.load propagation

    func testRegistryLoadPropagatesMaxAgeDays() throws {
        let tmp = try makeTempConfigDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let configJSON = #"""
        {
            "vault": {
                "agents": [],
                "maxAgeDays": 14
            }
        }
        """#
        try writeGlobalConfig(configJSON, in: tmp)

        let registry = CmuxVaultAgentRegistry.load(
            homeDirectory: tmp.path,
            workingDirectory: nil,
            environment: [:],
            fileManager: .default
        )

        XCTAssertEqual(registry.maxAgeDays, 14)
    }

    func testRegistryLoadPropagatesMaxEntriesPerAgent() throws {
        let tmp = try makeTempConfigDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let configJSON = #"""
        {
            "vault": {
                "agents": [],
                "maxEntriesPerAgent": 5
            }
        }
        """#
        try writeGlobalConfig(configJSON, in: tmp)

        let registry = CmuxVaultAgentRegistry.load(
            homeDirectory: tmp.path,
            workingDirectory: nil,
            environment: [:],
            fileManager: .default
        )

        XCTAssertEqual(registry.maxEntriesPerAgent, 5)
    }

    func testRegistryLoadAbsentLimitsProduceNil() throws {
        let tmp = try makeTempConfigDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let configJSON = #"""
        {
            "vault": {
                "agents": []
            }
        }
        """#
        try writeGlobalConfig(configJSON, in: tmp)

        let registry = CmuxVaultAgentRegistry.load(
            homeDirectory: tmp.path,
            workingDirectory: nil,
            environment: [:],
            fileManager: .default
        )

        XCTAssertNil(registry.maxAgeDays)
        XCTAssertNil(registry.maxEntriesPerAgent)
    }

    func testRegistryLoadNoConfigProducesNilLimits() {
        // No config file at all — all limits stay nil (today's behavior).
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-vdl-noconfig-\(UUID().uuidString)", isDirectory: true)
        // Don't create the directory — config lookup will simply find nothing.

        let registry = CmuxVaultAgentRegistry.load(
            homeDirectory: tmp.path,
            workingDirectory: nil,
            environment: [:],
            fileManager: .default
        )

        XCTAssertNil(registry.maxAgeDays, "No config should produce nil maxAgeDays (no cutoff)")
        XCTAssertNil(registry.maxEntriesPerAgent, "No config should produce nil maxEntriesPerAgent (use built-in default)")
    }

    // MARK: - Age-cutoff filter (store-level, MainActor)

    /// Verifies that the shared applyAgeCutoff helper (used by both scanAll and
    /// loadDirectorySnapshot) drops entries older than now - maxAgeDays days while
    /// keeping recent ones. Tests the production code path directly.
    @MainActor
    func testAgeCutoffDropsStaleEntriesAndKeepsRecentOnes() {
        let now = Date()
        let dayInSeconds: TimeInterval = 86_400

        // Entry modified 3 days ago — should pass a 7-day cutoff.
        let recent = makeEntry(title: "recent", modified: now.addingTimeInterval(-3 * dayInSeconds))
        // Entry modified 10 days ago — should be dropped by a 7-day cutoff.
        let stale = makeEntry(title: "stale", modified: now.addingTimeInterval(-10 * dayInSeconds))

        let filtered = SessionIndexStore.applyAgeCutoff([recent, stale], maxAgeDays: 7, now: now)

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.title, "recent")
    }

    /// Verifies that when maxAgeDays is nil the shared applyAgeCutoff helper
    /// returns the full list unchanged — no entries are dropped (today's behavior).
    @MainActor
    func testAgeCutoffAbsentKeepsAllEntries() {
        let now = Date()
        let dayInSeconds: TimeInterval = 86_400

        let old = makeEntry(title: "old", modified: now.addingTimeInterval(-365 * dayInSeconds))
        let recent = makeEntry(title: "recent", modified: now)

        // nil maxAgeDays → skip branch, all entries survive.
        let filtered = SessionIndexStore.applyAgeCutoff([old, recent], maxAgeDays: nil, now: now)

        XCTAssertEqual(filtered.count, 2, "nil maxAgeDays must not drop any entries")
    }

    // MARK: - Helpers

    private func makeEntry(
        title: String,
        modified: Date = .distantPast
    ) -> SessionEntry {
        SessionEntry(
            id: UUID().uuidString,
            agent: .claude,
            sessionId: UUID().uuidString,
            title: title,
            cwd: nil,
            gitBranch: nil,
            pullRequest: nil,
            modified: modified,
            fileURL: nil,
            specifics: .claude(model: nil, permissionMode: nil, configDirectoryForResume: nil)
        )
    }

    /// Create a temp directory that acts as the "home directory" for config loading tests.
    /// Writes the ~/.config/cmux/ structure inside it.
    private func makeTempConfigDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-vdl-\(UUID().uuidString)", isDirectory: true)
        let configDir = tmp.appendingPathComponent(".config/cmux", isDirectory: true)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        return tmp
    }

    private func writeGlobalConfig(_ json: String, in homeDir: URL) throws {
        let configPath = homeDir
            .appendingPathComponent(".config/cmux/cmux.json")
        try Data(json.utf8).write(to: configPath)
    }
}
