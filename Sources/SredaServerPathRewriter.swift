import Foundation

/// Rewrites sreda server-side absolute paths to their locally-mounted equivalents.
///
/// sreda NFS/autofs mounts:
///   /srv/nvme/git/<rest>   →  /Users/Shared/sreda-git/<rest>
///   /srv/nvme/vault/<rest> →  /Users/Shared/sreda-vault/<rest>
///
/// Also accepts paths already under the local mount prefixes (pass-through).
///
/// Mirrors the semantics of `~/Git/dotfiles/bin/srvopen`.
enum SredaServerPathRewriter {
    // MARK: - Prefix constants (one place to update if mounts move)

    static let serverGitPrefix = "/srv/nvme/git"
    static let localGitPrefix = "/Users/Shared/sreda-git"

    static let serverVaultPrefix = "/srv/nvme/vault"
    static let localVaultPrefix = "/Users/Shared/sreda-vault"

    // MARK: - Public API

    struct RewriteResult {
        let path: String
        let line: Int?
        let col: Int?
    }

    /// Attempt to rewrite a raw path string (possibly with a trailing `:LINE` or
    /// `:LINE:COL` suffix) to a local mount path.
    ///
    /// Returns `nil` when:
    /// - The input is not a sreda server path (or a local-mount alias).
    /// - The rewritten local path does not exist on disk.
    ///
    /// This function is **pure** (no side effects) and safe to call off the main thread.
    static func localPath(forServerPath raw: String) -> RewriteResult? {
        let stripped = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return nil }

        // 1. Strip optional :LINE:COL or :LINE tail.
        let (pathPart, line, col) = stripLineCol(from: stripped)

        // 2. Rewrite prefix.
        guard let localPath = rewritePrefix(pathPart) else { return nil }

        // 3. Existence check — reject phantom paths.
        guard FileManager.default.fileExists(atPath: localPath) else { return nil }

        return RewriteResult(path: localPath, line: line, col: col)
    }

    /// Returns `true` when the raw string looks like a sreda server path
    /// (or its local-mount alias), regardless of existence. Cheap prefix test,
    /// no filesystem I/O.
    static func isSredaPath(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.hasPrefix(serverGitPrefix + "/")
            || s.hasPrefix(serverVaultPrefix + "/")
            || s.hasPrefix(localGitPrefix + "/")
            || s.hasPrefix(localVaultPrefix + "/")
    }

    // MARK: - Internals

    /// Strip a `:LINE:COL` or `:LINE` suffix from a path string.
    /// Returns `(pathWithoutSuffix, line, col)`.
    private static func stripLineCol(from s: String) -> (String, Int?, Int?) {
        // Pattern: <path>:digits:digits
        if let m = s.range(of: #"^(.+):(\d+):(\d+)$"#, options: .regularExpression) {
            _ = m // use full-match range just to confirm
            // Re-extract via NSRegularExpression for capture groups.
            if let (p, l, c) = extractLineCol2(s) {
                return (p, l, c)
            }
        }
        // Pattern: <path>:digits
        if let (p, l) = extractLineCol1(s) {
            return (p, l, nil)
        }
        return (s, nil, nil)
    }

    private static func extractLineCol2(_ s: String) -> (String, Int, Int)? {
        guard let regex = try? NSRegularExpression(pattern: #"^(.+):(\d+):(\d+)$"#) else { return nil }
        let ns = s as NSString
        guard let m = regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges == 4 else { return nil }
        let path = ns.substring(with: m.range(at: 1))
        guard let line = Int(ns.substring(with: m.range(at: 2))),
              let col  = Int(ns.substring(with: m.range(at: 3))) else { return nil }
        return (path, line, col)
    }

    private static func extractLineCol1(_ s: String) -> (String, Int)? {
        guard let regex = try? NSRegularExpression(pattern: #"^(.+):(\d+)$"#) else { return nil }
        let ns = s as NSString
        guard let m = regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges == 3 else { return nil }
        let path = ns.substring(with: m.range(at: 1))
        guard let line = Int(ns.substring(with: m.range(at: 2))) else { return nil }
        return (path, line)
    }

    /// Map a server-side (or already-local) path to the local mount path.
    /// Returns `nil` for non-sreda inputs.
    private static func rewritePrefix(_ path: String) -> String? {
        if path.hasPrefix(serverGitPrefix + "/") {
            return localGitPrefix + path.dropFirst(serverGitPrefix.count)
        }
        if path.hasPrefix(serverVaultPrefix + "/") {
            return localVaultPrefix + path.dropFirst(serverVaultPrefix.count)
        }
        // Already using the local mount prefix — pass through.
        if path.hasPrefix(localGitPrefix + "/") || path == localGitPrefix {
            return path
        }
        if path.hasPrefix(localVaultPrefix + "/") || path == localVaultPrefix {
            return path
        }
        return nil
    }
}
