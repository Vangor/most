import XCTest

#if canImport(most_DEV)
@testable import most_DEV
#elseif canImport(most)
@testable import most
#elseif canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

// MARK: - Fork regression guards: com.4etverg.most bundle-ID classification
//
// These tests guard the bundle-identifier constants and classification logic that the
// `most` fork introduced.  If an upstream migration silently replaces
// "com.4etverg.most" with a different prefix (e.g. the upstream "com.cmuxterm.app"),
// every test here will fail — surfacing the regression before users see it.
//
// Guarded features
//   • SocketControlSettings.baseDebugBundleIdentifier == "com.4etverg.most.debug"
//   • SocketControlSettings.isDebugLikeBundleIdentifier() recognises com.4etverg.most.debug[.*]
//   • SocketControlSettings.isStagingBundleIdentifier() recognises com.4etverg.most.staging[.*]
//   • SocketControlSettings.isTaggedDevBuild() recognises com.4etverg.most.debug.<tag>
//   • SocketControlSettings.shouldBlockUntaggedDebugLaunch() uses the fork's base debug ID
//   • SocketControlSettings.socketPath() routes com.4etverg.most (release) to the stable path
//     rather than falling through to a foreign (cmuxterm) socket path

final class ForkBundleIdentifierClassificationTests: XCTestCase {

    // MARK: isDebugLikeBundleIdentifier

    func testDebugBundleIdentifierIsRecognisedAsDebugLike() {
        XCTAssertTrue(
            SocketControlSettings.isDebugLikeBundleIdentifier("com.4etverg.most.debug"),
            "Bare debug bundle ID must be debug-like"
        )
    }

    func testTaggedDebugBundleIdentifierIsRecognisedAsDebugLike() {
        XCTAssertTrue(
            SocketControlSettings.isDebugLikeBundleIdentifier("com.4etverg.most.debug.my-feature"),
            "Tagged debug bundle ID must be debug-like"
        )
    }

    func testReleaseBundleIdentifierIsNotDebugLike() {
        XCTAssertFalse(
            SocketControlSettings.isDebugLikeBundleIdentifier("com.4etverg.most"),
            "Production release bundle ID must not be debug-like"
        )
    }

    func testNightlyBundleIdentifierIsNotDebugLike() {
        XCTAssertFalse(
            SocketControlSettings.isDebugLikeBundleIdentifier("com.4etverg.most.nightly"),
            "Nightly bundle ID must not be debug-like"
        )
    }

    func testStagingBundleIdentifierIsNotDebugLike() {
        XCTAssertFalse(
            SocketControlSettings.isDebugLikeBundleIdentifier("com.4etverg.most.staging"),
            "Staging bundle ID must not be debug-like"
        )
    }

    func testUpstreamBundleIdentifierIsNotDebugLikeForFork() {
        // A bundle ID from the upstream cmux namespace must NOT be treated as debug-like
        // by the fork's classification — this would merge unrelated processes into the
        // fork's socket space.
        XCTAssertFalse(
            SocketControlSettings.isDebugLikeBundleIdentifier("com.cmuxterm.app.debug"),
            "Upstream bundle ID must not be debug-like in the fork's classifier"
        )
    }

    // MARK: isStagingBundleIdentifier

    func testStagingBundleIdentifierIsRecognisedAsStaging() {
        XCTAssertTrue(
            SocketControlSettings.isStagingBundleIdentifier("com.4etverg.most.staging"),
            "Bare staging bundle ID must be recognised as staging"
        )
    }

    func testTaggedStagingBundleIdentifierIsRecognisedAsStaging() {
        XCTAssertTrue(
            SocketControlSettings.isStagingBundleIdentifier("com.4etverg.most.staging.my-feature"),
            "Tagged staging bundle ID must be recognised as staging"
        )
    }

    func testReleaseBundleIdentifierIsNotStaging() {
        XCTAssertFalse(
            SocketControlSettings.isStagingBundleIdentifier("com.4etverg.most"),
            "Production release bundle ID must not be staging"
        )
    }

    func testDebugBundleIdentifierIsNotStaging() {
        XCTAssertFalse(
            SocketControlSettings.isStagingBundleIdentifier("com.4etverg.most.debug"),
            "Debug bundle ID must not be staging"
        )
    }

    func testUpstreamStagingBundleIdentifierIsNotStagingForFork() {
        XCTAssertFalse(
            SocketControlSettings.isStagingBundleIdentifier("com.cmuxterm.app.staging"),
            "Upstream staging bundle ID must not be staging in the fork's classifier"
        )
    }

    // MARK: isTaggedDevBuild

    func testTaggedDebugBundleIdentifierIsTaggedDevBuild() {
        XCTAssertTrue(
            SocketControlSettings.isTaggedDevBuild(bundleIdentifier: "com.4etverg.most.debug.feature-x"),
            "Tagged debug bundle must be a tagged dev build"
        )
    }

    func testBareDebugBundleIdentifierIsNotTaggedDevBuild() {
        // Untagged debug = the base bundle; tagged debug = base + suffix.
        // shouldBlockUntaggedDebugLaunch relies on this distinction.
        XCTAssertFalse(
            SocketControlSettings.isTaggedDevBuild(bundleIdentifier: "com.4etverg.most.debug"),
            "Bare debug bundle must not be a tagged dev build"
        )
    }

    func testReleaseBundleIdentifierIsNotTaggedDevBuild() {
        XCTAssertFalse(
            SocketControlSettings.isTaggedDevBuild(bundleIdentifier: "com.4etverg.most"),
            "Release bundle must not be a tagged dev build"
        )
    }

    // MARK: shouldBlockUntaggedDebugLaunch — fork bundle IDs

    func testForkUntaggedDebugBundleIsBlockedInDebugBuild() {
        // The untagged fork debug bundle launched without CMUX_TAG must be blocked so that
        // agent-launched debug instances don't accidentally share the default debug socket.
        XCTAssertTrue(
            SocketControlSettings.shouldBlockUntaggedDebugLaunch(
                environment: [:],
                bundleIdentifier: "com.4etverg.most.debug",
                isDebugBuild: true
            ),
            "Untagged fork debug bundle must be blocked in a debug build"
        )
    }

    func testForkUntaggedDebugBundleIsAllowedWithLaunchTag() {
        XCTAssertFalse(
            SocketControlSettings.shouldBlockUntaggedDebugLaunch(
                environment: ["CMUX_TAG": "my-feature"],
                bundleIdentifier: "com.4etverg.most.debug",
                isDebugBuild: true
            ),
            "Untagged fork debug bundle must NOT be blocked when CMUX_TAG is set"
        )
    }

    func testForkTaggedDebugBundleIsAlwaysAllowed() {
        XCTAssertFalse(
            SocketControlSettings.shouldBlockUntaggedDebugLaunch(
                environment: [:],
                bundleIdentifier: "com.4etverg.most.debug.my-feature",
                isDebugBuild: true
            ),
            "Tagged fork debug bundle must never be blocked (carries its own socket slug)"
        )
    }

    func testForkReleaseBundleIsNeverBlocked() {
        XCTAssertFalse(
            SocketControlSettings.shouldBlockUntaggedDebugLaunch(
                environment: [:],
                bundleIdentifier: "com.4etverg.most",
                isDebugBuild: true
            ),
            "Fork release bundle ID must never trigger the untagged-debug block"
        )
    }

    // MARK: socketPath routing — fork release bundle resolves to stable most.sock

    func testForkReleaseBundleRoutesToStableSocketPath() {
        // com.4etverg.most (release) must resolve to the stable most.sock path, not fall
        // through to a debug or nightly socket.  If upstream migration removes the fork's
        // stable-socket reservation, the Release app's socket will silently change and
        // the CLI will no longer find `most.sock`.
        let stable = SocketControlSettings.stableDefaultSocketPath
        let resolved = SocketControlSettings.socketPath(
            environment: [:],
            bundleIdentifier: "com.4etverg.most",
            isDebugBuild: false,
            // UID is irrelevant for this path; any value works
            currentUserID: 501,
            probeStableDefaultPathEntry: { _ in .missing }
        )
        XCTAssertEqual(
            resolved,
            stable,
            "Fork release bundle must resolve to the stable socket path (\(stable))"
        )
    }

    func testForkDebugBundleRoutesToDebugSocket() {
        // com.4etverg.most.debug with empty env and probe=.missing deterministically maps to
        // SocketPathMarkerFiles.defaultDebugSocketPath ("/tmp/cmux-debug.sock") — the bare
        // untagged debug socket.  Verified against SocketPathMarkerFiles.defaultSocketPath:
        // variant(.dev(slug:nil)) → debugSocketPath default = "/tmp/cmux-debug.sock".
        let resolved = SocketControlSettings.socketPath(
            environment: [:],
            bundleIdentifier: "com.4etverg.most.debug",
            isDebugBuild: true,
            // UID is irrelevant for this path; any value works
            currentUserID: 501,
            probeStableDefaultPathEntry: { _ in .missing }
        )
        XCTAssertEqual(resolved, "/tmp/cmux-debug.sock", "Fork debug bundle must resolve to the bare debug socket path")
        XCTAssertNotEqual(
            resolved,
            SocketControlSettings.stableDefaultSocketPath,
            "Fork debug bundle must NOT resolve to the stable most.sock"
        )
    }

    // MARK: shouldBlockUntaggedDebugLaunch — XCTest escape-hatch

    func testForkDebugBundleAllowedUnderXCTest() {
        // XCTestConfigurationFilePath in the environment triggers the XCTest escape-hatch path,
        // so the untagged debug bundle must NOT be blocked even without CMUX_TAG.
        XCTAssertFalse(
            SocketControlSettings.shouldBlockUntaggedDebugLaunch(
                environment: ["XCTestConfigurationFilePath": "/tmp/x"],
                bundleIdentifier: "com.4etverg.most.debug",
                isDebugBuild: true
            ),
            "Untagged fork debug bundle must NOT be blocked when running under XCTest"
        )
    }

    // MARK: isStagingBundleIdentifier — nightly is not staging

    func testNightlyBundleIdentifierIsNotStaging() {
        XCTAssertFalse(
            SocketControlSettings.isStagingBundleIdentifier("com.4etverg.most.nightly"),
            "Nightly bundle ID must not be classified as staging"
        )
    }
}
