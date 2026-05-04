import Foundation

public enum UnblockRequestResult: String, Codable, Equatable, Sendable {
    case started
    case blockingInactive
}

public enum ScheduledNotificationKind: String, Codable, Equatable, Sendable {
    case unblockReady
}

public struct ScheduledNotification: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let kind: ScheduledNotificationKind

    public static let unblockReady = ScheduledNotification(
        id: "unblock-ready",
        title: "Blocker is unlocked",
        body: "Your unlock timer is done. Open Blocker to edit your active blocks.",
        kind: .unblockReady
    )
}

public enum UnblockRequestStatus: Codable, Equatable, Sendable {
    case running
    case finished

    public var isPending: Bool {
        self == .running
    }

    private enum CodingKeys: String, CodingKey {
        case running
        case finished
    }

    private struct EmptyPayload: Codable {}

    public init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let rawValue = try? singleValue.decode(String.self) {
            self = rawValue == CodingKeys.finished.rawValue ? .finished : .running
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = container.contains(.finished) ? .finished : .running
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .running:
            try container.encode(EmptyPayload(), forKey: .running)
        case .finished:
            try container.encode(EmptyPayload(), forKey: .finished)
        }
    }
}

public struct UnblockRequest: Codable, Equatable, Sendable {
    public static let testIntervalSeconds = 3
    public static let defaultDurationSeconds = testIntervalSeconds

    public var anchorDate: Date
    public var remainingAtAnchor: Int
    public var status: UnblockRequestStatus

    public init(startedAt: Date) {
        self.anchorDate = startedAt
        self.remainingAtAnchor = Self.defaultDurationSeconds
        self.status = .running
    }

    private enum CodingKeys: String, CodingKey {
        case anchorDate
        case remainingAtAnchor
        case status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        anchorDate = try container.decode(Date.self, forKey: .anchorDate)
        status = try container.decodeIfPresent(UnblockRequestStatus.self, forKey: .status) ?? .running

        let decodedRemaining = try container.decodeIfPresent(Int.self, forKey: .remainingAtAnchor) ?? Self.defaultDurationSeconds
        remainingAtAnchor = status.isPending ? min(max(0, decodedRemaining), Self.defaultDurationSeconds) : 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(anchorDate, forKey: .anchorDate)
        try container.encode(remainingAtAnchor, forKey: .remainingAtAnchor)
        try container.encode(status, forKey: .status)
    }

    public func remainingSeconds(now: Date) -> Int {
        switch status {
        case .running:
            let elapsed = max(0, Int(now.timeIntervalSince(anchorDate)))
            return max(0, remainingAtAnchor - elapsed)
        case .finished:
            return 0
        }
    }

    public mutating func refresh(now: Date) -> ScheduledNotification? {
        guard status == .running else {
            return nil
        }

        let currentRemaining = remainingSeconds(now: now)

        if currentRemaining <= 0 {
            status = .finished
            anchorDate = now
            remainingAtAnchor = 0
            return .unblockReady
        }

        return nil
    }
}
