import Foundation

public struct PopularBlockSuggestion: Codable, Equatable, Identifiable, Sendable {
    public var id: String { domain }
    public let name: String
    public let domain: String
    public let appBundleIdentifier: String?
    public let aliases: [String]

    public init(
        name: String,
        domain: String,
        appBundleIdentifier: String? = nil,
        aliases: [String] = []
    ) {
        self.name = name
        self.domain = domain
        self.appBundleIdentifier = appBundleIdentifier
        self.aliases = aliases
    }
}

public struct PendingBlockSelection: Codable, Equatable, Identifiable, Sendable {
    public var id: String { suggestion.id }
    public let suggestion: PopularBlockSuggestion
}

public enum AddBlockOutcome: Codable, Equatable, Sendable {
    case added
    case needsScopeConfirmation(PendingBlockSelection)
    case ignored
}

public enum BlockScope: String, Codable, Equatable, Sendable {
    case app
    case web
}

public struct BlockItem: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var domain: String
    public var appBundleIdentifier: String?
    public var blocksApp: Bool
    public var blocksWeb: Bool

    public init(
        name: String,
        domain: String,
        appBundleIdentifier: String? = nil,
        blocksApp: Bool,
        blocksWeb: Bool
    ) {
        self.id = domain
        self.name = name
        self.domain = domain
        self.appBundleIdentifier = appBundleIdentifier
        self.blocksApp = blocksApp
        self.blocksWeb = blocksWeb
    }

    public var canBlockApp: Bool {
        appBundleIdentifier != nil
    }

    public var isActive: Bool {
        blocksApp || blocksWeb
    }

    public var canDelete: Bool {
        !isActive
    }
}

public enum PopularBlockCatalog {
    public static let suggestions: [PopularBlockSuggestion] = [
        .init(name: "TikTok", domain: "tiktok.com", appBundleIdentifier: "com.zhiliaoapp.musically", aliases: ["tik tok"]),
        .init(name: "Instagram", domain: "instagram.com", appBundleIdentifier: "com.burbn.instagram", aliases: ["ig"]),
        .init(name: "YouTube", domain: "youtube.com", appBundleIdentifier: "com.google.ios.youtube", aliases: ["yt"]),
        .init(name: "Reddit", domain: "reddit.com", appBundleIdentifier: "com.reddit.Reddit", aliases: []),
        .init(name: "X", domain: "x.com", appBundleIdentifier: "com.atebits.Tweetie2", aliases: ["twitter"]),
        .init(name: "Facebook", domain: "facebook.com", appBundleIdentifier: "com.facebook.Facebook", aliases: ["fb"]),
        .init(name: "Snapchat", domain: "snapchat.com", appBundleIdentifier: "com.toyopagroup.picaboo", aliases: ["snap"]),
        .init(name: "Discord", domain: "discord.com", appBundleIdentifier: "com.hammerandchisel.discord", aliases: []),
        .init(name: "Netflix", domain: "netflix.com", appBundleIdentifier: "com.netflix.Netflix", aliases: []),
        .init(name: "Pornhub", domain: "pornhub.com", aliases: [])
    ]

    public static func knownAppBundleIdentifier(for domain: String) -> String? {
        suggestions.first { $0.domain == domain }?.appBundleIdentifier
    }

    public static func matching(_ query: String) -> [PopularBlockSuggestion] {
        let normalized = normalizeQuery(query)

        guard !normalized.isEmpty else {
            return Array(suggestions.prefix(6))
        }

        return suggestions.filter { suggestion in
            let fields = [suggestion.name, suggestion.domain] + suggestion.aliases
            return fields.contains { normalizeQuery($0).contains(normalized) }
        }
    }

    public static func resolve(_ input: String) -> PopularBlockSuggestion? {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let host = normalizeDomain(input)
        let query = normalizeQuery(input)

        if let exact = suggestions.first(where: { suggestion in
            suggestion.domain == host ||
                normalizeQuery(suggestion.name) == query ||
                suggestion.aliases.contains(where: { normalizeQuery($0) == query })
        }) {
            return exact
        }

        guard !host.isEmpty else {
            return nil
        }

        let label = host.split(separator: ".").first.map(String.init) ?? host
        return PopularBlockSuggestion(name: titleCase(label), domain: host)
    }

    public static func normalizeDomain(_ input: String) -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        for prefix in ["https://", "http://"] {
            if value.hasPrefix(prefix) {
                value.removeFirst(prefix.count)
            }
        }

        if value.hasPrefix("www.") {
            value.removeFirst(4)
        }

        if let slash = value.firstIndex(of: "/") {
            value = String(value[..<slash])
        }

        while value.hasSuffix(".") {
            value.removeLast()
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")
        let filtered = value.unicodeScalars.filter { allowed.contains($0) }
        value = String(String.UnicodeScalarView(filtered))

        while value.hasSuffix(".") {
            value.removeLast()
        }

        guard !value.isEmpty,
              !value.hasPrefix("."),
              !value.contains("..") else {
            return ""
        }

        if !value.contains(".") {
            value += ".com"
        }

        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2,
              labels.allSatisfy({ !$0.isEmpty }) else {
            return ""
        }

        return value
    }

    private static func normalizeQuery(_ input: String) -> String {
        input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "." }
    }

    private static func titleCase(_ input: String) -> String {
        guard let first = input.first else {
            return input
        }

        return first.uppercased() + input.dropFirst()
    }
}
