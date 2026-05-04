import Foundation

public enum EnableBlockingResult: String, Codable, Equatable, Sendable {
    case enabled
    case setupIncomplete
    case missingPermissions
    case emptyBlockList
}

public struct RestrictionPlan: Codable, Equatable, Sendable {
    public var appBundleIdentifiers: Set<String>
    public var webDomains: Set<String>

    public init(
        appBundleIdentifiers: Set<String> = [],
        webDomains: Set<String> = []
    ) {
        self.appBundleIdentifiers = appBundleIdentifiers
        self.webDomains = webDomains
    }

    public var isEmpty: Bool {
        appBundleIdentifiers.isEmpty && webDomains.isEmpty
    }
}
