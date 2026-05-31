import Foundation

#if canImport(most_DEV)
@testable import most_DEV
#elseif canImport(most)
@testable import most
#elseif canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
extension KeyboardShortcutSettings {
    static func installIsolatedTestFileStore(prefix: String) -> KeyboardShortcutSettingsFileStore {
        let original = settingsFileStore
        let settingsFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).json", isDirectory: false)
        settingsFileStore = KeyboardShortcutSettingsFileStore(
            primaryPath: settingsFileURL.path,
            fallbackPath: nil,
            additionalFallbackPaths: [],
            startWatching: false
        )
        return original
    }
}
