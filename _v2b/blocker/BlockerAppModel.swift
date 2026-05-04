import Foundation
import Combine
import SwiftUI

@MainActor
final class BlockerAppModel: ObservableObject {
    @Published private(set) var domain: BlockerDomainModel
    @Published var newBlockText = ""
    @Published var pendingSelection: PendingBlockSelection?

    private let persistence = BlockerPersistence()
    private let notifications = BlockerNotificationScheduler()
    private let screenTime = ScreenTimeService()
    private var notificationCancellable: AnyCancellable?

    init() {
        self.domain = persistence.load() ?? BlockerDomainModel()
        recoverSetupIfNeeded()
        notificationCancellable = NotificationCenter.default
            .publisher(for: .blockerNotificationAction)
            .sink { [weak self] notification in
                guard let action = notification.object as? String else {
                    return
                }

                Task { @MainActor in
                    self?.handleNotificationAction(action)
                }
            }
        refresh()
    }

    var countdownText: String {
        let remaining = domain.remainingUnblockSeconds(now: Date())
        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func refresh() {
        domain.refresh(now: Date())
        applyRestrictions()
        save()
    }

    func acceptSetupStep() {
        domain.acceptSetupStep()
        save()
    }

    func goBackSetupStep() {
        domain.goBackSetupStep()
        save()
    }

    func finishSetupAndBlock() {
        domain.acceptSetupStep()
        enableBlocking()
    }

    func setDefaultBlockScope(_ scope: BlockScope, isBlocked: Bool) {
        domain.setDefaultBlockScope(scope, isBlocked: isBlocked)
        save()
    }

    func setScreenTimePermission(_ enabled: Bool) {
        domain.setScreenTimePermission(enabled)
        applyRestrictions()
        save()
    }

    func revokeScreenTimeAccess() async {
        _ = await screenTime.revokeAuthorization()
        domain.setScreenTimePermission(false)
        applyRestrictions()
        save()
    }

    func setDeletingAppsDisabled(_ disabled: Bool) {
        domain.setDeletingAppsDisabled(disabled)
        screenTime.setDeletingAppsDisabled(disabled)
        save()
    }

    func requestScreenTimeAccess() async {
        let granted = await screenTime.requestAuthorization()
        domain.setScreenTimePermission(granted)
        applyRestrictions()
        save()
    }

    func resetForDevelopment() {
        notifications.cancelAllNotifications()
        screenTime.clearRestrictions()
        pendingSelection = nil
        newBlockText = ""
        domain = BlockerDomainModel()
        persistence.reset()
        save()
        screenTime.resetAuthorizationInBackground()
    }

    func addTypedBlock() {
        guard !newBlockText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        addBlock(named: newBlockText)
    }

    func addBlock(named name: String) {
        let outcome = domain.addBlock(named: name)
        handleAddOutcome(outcome)
    }

    func confirmPendingBlock(blockApp: Bool, blockWeb: Bool) {
        guard let pending = pendingSelection else {
            return
        }

        let outcome = domain.confirmPendingBlock(pending, blockApp: blockApp, blockWeb: blockWeb)
        pendingSelection = nil
        handleAddOutcome(outcome)
    }

    func cancelPendingBlock() {
        pendingSelection = nil
    }

    func setBlockScope(id: BlockItem.ID, scope: BlockScope, isBlocked: Bool) {
        domain.setBlockScope(id: id, scope: scope, isBlocked: isBlocked)
        recoverSetupIfNeeded()
        applyRestrictions()
        save()
    }

    func deleteBlock(id: BlockItem.ID) {
        domain.deleteBlock(id: id)
        recoverSetupIfNeeded()
        applyRestrictions()
        save()
    }

    func enableBlocking() {
        _ = domain.enableBlocking()
        applyRestrictions()
        save()
    }

    func requestUnblock() {
        let result = domain.requestUnblock(now: Date())
        if result == .started {
            Task {
                await notifications.requestAuthorization()
                await notifications.schedule(
                    .unblockReady,
                    after: TimeInterval(UnblockRequest.defaultDurationSeconds)
                )
            }
        }
        save()
    }

    func cancelUnblockRequest() {
        domain.cancelUnblockRequest()
        notifications.cancelUnblockNotifications()
        applyRestrictions()
        save()
    }

    func handleNotificationAction(_: String) {
        refresh()
    }

    private func handleAddOutcome(_ outcome: AddBlockOutcome) {
        switch outcome {
        case .added:
            newBlockText = ""
            applyRestrictions()
            save()
        case let .needsScopeConfirmation(pending):
            pendingSelection = pending
        case .ignored:
            break
        }
    }

    private func applyRestrictions() {
        screenTime.apply(domain)
    }

    private func recoverSetupIfNeeded() {
        var updated = domain
        updated.recoverBlockMetadata()
        updated.recoverSetupAfterBlockingEnabled()
        updated.recoverSetupAfterBlocksEmptied()
        updated.recoverLegacyUnblockReviewRoute()
        if updated != domain {
            domain = updated
        }
    }

    private func save() {
        persistence.save(domain)
    }
}

private struct BlockerPersistence {
    private let key = "blocker.domain.model.v1"

    func load() -> BlockerDomainModel? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(BlockerDomainModel.self, from: data)
    }

    func save(_ model: BlockerDomainModel) {
        guard let data = try? JSONEncoder().encode(model) else {
            return
        }

        UserDefaults.standard.set(data, forKey: key)
    }

    func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
