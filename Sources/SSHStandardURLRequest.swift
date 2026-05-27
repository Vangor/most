import Foundation

struct SSHStandardURLRequest: Equatable {
    let originalURL: URL
    let destination: String
    let port: Int?
    let title: String?
    let workingDirectory: String?

    static func parse(_ url: URL) -> Result<SSHStandardURLRequest?, CmuxSSHURLParseError> {
        guard url.scheme?.lowercased() == "ssh" else {
            return .success(nil)
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .failure(.missingDestination)
        }

        guard let hostValue = normalizedHost(components.host) else {
            return .failure(.missingDestination)
        }
        guard !hostValue.hasPrefix("-") else {
            return .failure(.destinationStartsWithDash)
        }
        guard isAllowedSSHHost(hostValue) else {
            return .failure(.destinationContainsUnsafeCharacters)
        }

        let userValue = normalizedUser(components.user)
        if let userValue {
            guard !userValue.hasPrefix("-") else {
                return .failure(.destinationStartsWithDash)
            }
            guard isAllowedSSHUser(userValue) else {
                return .failure(.destinationContainsUnsafeCharacters)
            }
        }

        let destination = userValue.map { "\($0)@\(hostValue)" } ?? hostValue
        guard destination.count <= CmuxSSHURLRequest.maxDestinationLength else {
            return .failure(.destinationTooLong(maxLength: CmuxSSHURLRequest.maxDestinationLength))
        }

        if let port = components.port, !(1...65535).contains(port) {
            return .failure(.invalidPort)
        }

        let workingDirectory = normalizedWorkingDirectory(from: components.path)
        if let workingDirectory,
           strippedLeadingSlashes(from: workingDirectory).hasPrefix("-") {
            return .failure(.destinationStartsWithDash)
        }

        let queryItems = components.queryItems ?? []
        let allowedQueryNames: Set<String> = ["fragment"]
        var seenQueryNames = Set<String>()
        for item in queryItems {
            let name = item.name.lowercased()
            guard allowedQueryNames.contains(name) else {
                return .failure(.unsupportedParameter(displayParameterName(item.name)))
            }
            guard seenQueryNames.insert(name).inserted else {
                return .failure(.duplicateParameter(displayParameterName(item.name)))
            }
        }

        let titleValue = normalizedQueryValue(namedAnyOf: ["fragment"], in: queryItems)
            ?? normalizedComponentValue(components.fragment)
        if let titleValue {
            guard titleValue.count <= CmuxSSHURLRequest.maxTitleLength else {
                return .failure(.titleTooLong(maxLength: CmuxSSHURLRequest.maxTitleLength))
            }
            guard !containsUnsafeHiddenCharacter(titleValue) else {
                return .failure(.titleContainsUnsafeCharacters)
            }
        }

        return .success(
            SSHStandardURLRequest(
                originalURL: url,
                destination: destination,
                port: components.port,
                title: titleValue,
                workingDirectory: workingDirectory
            )
        )
    }

    private static func normalizedHost(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedUser(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedWorkingDirectory(from path: String) -> String? {
        return path.isEmpty ? nil : path
    }

    private static func normalizedComponentValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedQueryValue(namedAnyOf names: Set<String>, in queryItems: [URLQueryItem]) -> String? {
        guard let value = queryItems.first(where: { names.contains($0.name.lowercased()) })?.value else {
            return nil
        }
        return normalizedComponentValue(value)
    }

    private static func isAllowedSSHHost(_ value: String) -> Bool {
        guard !containsUnsafeHiddenCharacter(value) else { return false }
        if value.hasPrefix("[") || value.hasSuffix("]") {
            guard value.hasPrefix("["), value.hasSuffix("]") else { return false }
            let inner = String(value.dropFirst().dropLast())
            guard !inner.isEmpty else { return false }
            let allowed = CharacterSet(charactersIn: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz:.%")
            return inner.unicodeScalars.allSatisfy { allowed.contains($0) }
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._%-")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func isAllowedSSHUser(_ value: String) -> Bool {
        guard !containsUnsafeHiddenCharacter(value) else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._%+=,:-")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func containsUnsafeHiddenCharacter(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator:
                return true
            default:
                return false
            }
        }
    }

    private static func strippedLeadingSlashes(from value: String) -> String {
        var index = value.startIndex
        while index < value.endIndex, value[index] == "/" {
            index = value.index(after: index)
        }
        return String(value[index...])
    }

    private static func displayParameterName(_ name: String) -> String {
        if name.isEmpty || containsUnsafeHiddenCharacter(name) {
            return "?"
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        guard name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return "?"
        }
        let prefix = String(name.prefix(64))
        return prefix.count == name.count ? prefix : "\(prefix)..."
    }
}

extension CmuxSSHURLRequest {
    init(standardRequest request: SSHStandardURLRequest) {
        self.init(
            originalURL: request.originalURL,
            destination: request.destination,
            port: request.port,
            title: request.title,
            workingDirectory: request.workingDirectory,
            sshOptions: [],
            noFocus: false
        )
    }
}
