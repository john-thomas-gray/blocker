import Foundation

public struct BlockerSettings: Codable, Equatable, Sendable {
    public var blockAppsByDefault = true
    public var blockWebsitesByDefault = true

    public init(
        blockAppsByDefault: Bool = true,
        blockWebsitesByDefault: Bool = true
    ) {
        self.blockAppsByDefault = blockAppsByDefault
        self.blockWebsitesByDefault = blockWebsitesByDefault
    }

    private enum CodingKeys: String, CodingKey {
        case blockAppsByDefault
        case blockWebsitesByDefault
        case blockBothAppAndWeb
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let blockAppsByDefault = try container.decodeIfPresent(Bool.self, forKey: .blockAppsByDefault),
           let blockWebsitesByDefault = try container.decodeIfPresent(Bool.self, forKey: .blockWebsitesByDefault) {
            self.blockAppsByDefault = blockAppsByDefault
            self.blockWebsitesByDefault = blockWebsitesByDefault
            return
        }

        if let legacyBlockBoth = try container.decodeIfPresent(Bool.self, forKey: .blockBothAppAndWeb) {
            self.blockAppsByDefault = legacyBlockBoth
            self.blockWebsitesByDefault = legacyBlockBoth
            return
        }

        self.blockAppsByDefault = true
        self.blockWebsitesByDefault = true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(blockAppsByDefault, forKey: .blockAppsByDefault)
        try container.encode(blockWebsitesByDefault, forKey: .blockWebsitesByDefault)
    }
}

public struct PermissionState: Codable, Equatable, Sendable {
    public var hasScreenTimeAccess = false
    public var isDeletingAppsDisabled = false

    public init(
        hasScreenTimeAccess: Bool = false,
        isDeletingAppsDisabled: Bool = false
    ) {
        self.hasScreenTimeAccess = hasScreenTimeAccess
        self.isDeletingAppsDisabled = isDeletingAppsDisabled
    }
}
