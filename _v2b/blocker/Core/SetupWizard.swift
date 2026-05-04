import Foundation

public enum AppRoute: String, Codable, Equatable, Sendable {
    case setup
    case main
    /// Legacy persisted route from builds that used a separate post-timer review screen.
    case unblockReview
}

public enum SetupStep: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case screenTimeAccess
    case screenTimePassword
    case disableDeletingApps
    case chooseWhatToBlock
    case blockConfirmation

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .screenTimeAccess:
            "Screen Time Access"
        case .screenTimePassword:
            "Screen Time Password"
        case .disableDeletingApps:
            "Disable App Deletion"
        case .chooseWhatToBlock:
            "Choose What To Block"
        case .blockConfirmation:
            "Ready To Block"
        }
    }

    public var explanation: String {
        switch self {
        case .screenTimeAccess:
            "Blocker needs Screen Time access before it can shield apps or websites."
        case .screenTimePassword:
            "Set a Screen Time passcode in Settings if you have not already. This keeps the system controls harder to bypass."
        case .disableDeletingApps:
            "Set Deleting Apps to Don't Allow so Blocker cannot be removed while a lock is active."
        case .chooseWhatToBlock:
            "Pick a first app or website. You can always add more later."
        case .blockConfirmation:
            "Your saved blocks apply as soon as they are added. Locking Blocker prevents changes until the unlock timer finishes."
        }
    }

    public var buttonTitle: String {
        self == .blockConfirmation ? "Lock" : "Accept"
    }
}

public struct SetupWizard: Codable, Equatable, Sendable {
    public private(set) var current: SetupStep = .screenTimeAccess
    public private(set) var isComplete = false

    public init() {}

    public var canGoBack: Bool {
        guard !isComplete,
              let index = SetupStep.allCases.firstIndex(of: current) else {
            return false
        }

        return index > 0
    }

    public mutating func accept() {
        guard !isComplete else {
            return
        }

        let steps = SetupStep.allCases
        guard let index = steps.firstIndex(of: current) else {
            return
        }

        if index + 1 < steps.count {
            current = steps[index + 1]
        } else {
            isComplete = true
        }
    }

    public mutating func goBack() {
        guard canGoBack,
              let index = SetupStep.allCases.firstIndex(of: current) else {
            return
        }

        current = SetupStep.allCases[index - 1]
    }

    /// Moves to a step without completing setup. Used when the user clears every active scope on the confirmation screen so they can add items again.
    public mutating func move(to step: SetupStep) {
        guard !isComplete else {
            return
        }

        current = step
    }

    public mutating func complete() {
        isComplete = true
    }
}

public struct BlockerDomainModel: Codable, Equatable, Sendable {
    public private(set) var setup = SetupWizard()
    public private(set) var route: AppRoute = .setup
    public private(set) var settings = BlockerSettings()
    public private(set) var permissions = PermissionState()
    public private(set) var blocks: [BlockItem] = []
    public private(set) var isBlockingEnabled = false
    public private(set) var unblockRequest: UnblockRequest?
    public private(set) var scheduledNotifications: [ScheduledNotification] = []

    public init() {}

    public var canAdvanceSetup: Bool {
        guard route == .setup, !setup.isComplete else {
            return false
        }

        switch setup.current {
        case .chooseWhatToBlock, .blockConfirmation:
            return hasActiveBlocks
        case .screenTimeAccess:
            return permissions.hasScreenTimeAccess
        case .disableDeletingApps:
            return permissions.isDeletingAppsDisabled
        case .screenTimePassword:
            return true
        }
    }

    public var canGoBackInSetup: Bool {
        route == .setup && setup.canGoBack
    }

    public mutating func acceptSetupStep() {
        guard canAdvanceSetup else {
            return
        }

        setup.accept()

        if setup.isComplete {
            route = .main
        }
    }

    public mutating func goBackSetupStep() {
        guard route == .setup else {
            return
        }

        setup.goBack()
    }


    /// Returns the user to "Choose What To Block" when they have no active scopes on the confirmation step; otherwise the Lock control stays disabled with no way to add items.
    public mutating func recoverSetupAfterBlocksEmptied() {
        guard route == .setup, !setup.isComplete, setup.current == .blockConfirmation, !hasActiveBlocks else {
            return
        }

        setup.move(to: .chooseWhatToBlock)
    }

    /// A persisted active block means setup already succeeded, even if an older launch saved a stale setup route.
    public mutating func recoverSetupAfterBlockingEnabled() {
        guard isBlockingEnabled else {
            return
        }

        setup.complete()

        if route == .setup {
            route = .main
        }
    }

    public mutating func setDefaultBlockScope(_ scope: BlockScope, isBlocked: Bool) {
        guard canEditBlocks else {
            return
        }

        switch scope {
        case .app:
            settings.blockAppsByDefault = isBlocked
        case .web:
            settings.blockWebsitesByDefault = isBlocked
        }
    }

    public mutating func setScreenTimePermission(_ enabled: Bool) {
        guard canEditPermissions else {
            return
        }

        permissions.hasScreenTimeAccess = enabled
    }

    public mutating func setDeletingAppsDisabled(_ disabled: Bool) {
        guard canEditPermissions else {
            return
        }

        permissions.isDeletingAppsDisabled = disabled
    }

    public var canEditPermissions: Bool {
        !isBlockingEnabled
    }

    public var hasActiveBlocks: Bool {
        blocks.contains(where: \.isActive)
    }

    public var canEditBlocks: Bool {
        !isBlockingEnabled
    }

    public var restrictionPlan: RestrictionPlan {
        RestrictionPlan(
            appBundleIdentifiers: Set(blocks.compactMap { item in
                item.blocksApp ? item.appBundleIdentifier : nil
            }),
            webDomains: Set(blocks.compactMap { item in
                item.blocksWeb ? item.domain : nil
            })
        )
    }

    @discardableResult
    public mutating func enableBlocking() -> EnableBlockingResult {
        guard setup.isComplete else {
            isBlockingEnabled = false
            return .setupIncomplete
        }

        guard permissions.hasScreenTimeAccess && permissions.isDeletingAppsDisabled else {
            isBlockingEnabled = false
            return .missingPermissions
        }

        guard hasActiveBlocks else {
            isBlockingEnabled = false
            return .emptyBlockList
        }

        isBlockingEnabled = true
        route = .main
        return .enabled
    }

    public var isUnblockPending: Bool {
        unblockRequest?.status.isPending == true
    }

    @discardableResult
    public mutating func requestUnblock(now: Date) -> UnblockRequestResult {
        guard isBlockingEnabled else {
            return .blockingInactive
        }

        unblockRequest = UnblockRequest(startedAt: now)
        scheduledNotifications = []
        route = .main
        return .started
    }

    public func remainingUnblockSeconds(now: Date) -> Int {
        unblockRequest?.remainingSeconds(now: now) ?? 0
    }

    public mutating func refresh(now: Date) {
        recoverBlockMetadata()
        recoverSetupAfterBlockingEnabled()
        recoverLegacyUnblockReviewRoute()

        guard var request = unblockRequest else {
            return
        }

        if let notification = request.refresh(now: now) {
            scheduledNotifications.append(notification)
        }

        if request.status == .finished {
            unblockRequest = nil
            isBlockingEnabled = false
            route = .main
            return
        }

        unblockRequest = request
    }

    public mutating func recoverLegacyUnblockReviewRoute() {
        guard route == .unblockReview else {
            return
        }

        unblockRequest = nil
        isBlockingEnabled = false
        route = .main
    }

    public mutating func cancelUnblockRequest() {
        guard unblockRequest != nil else {
            return
        }

        unblockRequest = nil
        scheduledNotifications = []
        isBlockingEnabled = true
        route = .main
    }

    public func suggestions(matching query: String) -> [PopularBlockSuggestion] {
        PopularBlockCatalog.matching(query)
    }

    @discardableResult
    public mutating func addBlock(named input: String) -> AddBlockOutcome {
        guard canEditBlocks else {
            return .ignored
        }

        guard let suggestion = PopularBlockCatalog.resolve(input) else {
            return .ignored
        }

        let shouldAskForScope = !settings.blockAppsByDefault && !settings.blockWebsitesByDefault
            || (settings.blockAppsByDefault && !settings.blockWebsitesByDefault && suggestion.appBundleIdentifier == nil)

        if shouldAskForScope {
            return .needsScopeConfirmation(PendingBlockSelection(suggestion: suggestion))
        }

        if settings.blockAppsByDefault || settings.blockWebsitesByDefault {
            upsertBlock(
                suggestion,
                blockApp: settings.blockAppsByDefault,
                blockWeb: settings.blockWebsitesByDefault
            )
            return .added
        }

        return .ignored
    }

    @discardableResult
    public mutating func confirmPendingBlock(
        _ pending: PendingBlockSelection,
        blockApp: Bool,
        blockWeb: Bool
    ) -> AddBlockOutcome {
        guard canEditBlocks else {
            return .ignored
        }

        guard blockApp || blockWeb else {
            return .ignored
        }

        upsertBlock(pending.suggestion, blockApp: blockApp, blockWeb: blockWeb)
        return .added
    }

    private mutating func upsertBlock(
        _ suggestion: PopularBlockSuggestion,
        blockApp: Bool,
        blockWeb: Bool
    ) {
        let appBundleIdentifier = suggestion.appBundleIdentifier
        let shouldBlockApp = blockApp && appBundleIdentifier != nil

        if let index = blocks.firstIndex(where: { $0.id == suggestion.domain }) {
            blocks[index].appBundleIdentifier = blocks[index].appBundleIdentifier ?? appBundleIdentifier
            blocks[index].blocksApp = blocks[index].blocksApp || shouldBlockApp
            blocks[index].blocksWeb = blocks[index].blocksWeb || blockWeb
            return
        }

        blocks.append(
            BlockItem(
                name: suggestion.name,
                domain: suggestion.domain,
                appBundleIdentifier: appBundleIdentifier,
                blocksApp: shouldBlockApp,
                blocksWeb: blockWeb
            )
        )
        blocks.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public mutating func setBlockScope(
        id: BlockItem.ID,
        scope: BlockScope,
        isBlocked: Bool
    ) {
        guard canEditBlocks else {
            return
        }

        guard let index = blocks.firstIndex(where: { $0.id == id }) else {
            return
        }

        switch scope {
        case .app:
            guard !isBlocked || blocks[index].canBlockApp else {
                return
            }

            blocks[index].blocksApp = isBlocked
        case .web:
            blocks[index].blocksWeb = isBlocked
        }
    }

    public mutating func deleteBlock(id: BlockItem.ID) {
        guard canEditBlocks else {
            return
        }

        guard let index = blocks.firstIndex(where: { $0.id == id }),
              blocks[index].canDelete else {
            return
        }

        blocks.remove(at: index)
    }

    public mutating func recoverBlockMetadata() {
        for index in blocks.indices {
            if blocks[index].appBundleIdentifier == nil {
                blocks[index].appBundleIdentifier = PopularBlockCatalog.knownAppBundleIdentifier(for: blocks[index].domain)
            }

            if blocks[index].appBundleIdentifier == nil {
                blocks[index].blocksApp = false
            }
        }
    }
}
