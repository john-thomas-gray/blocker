import Foundation
import XCTest

#if canImport(BlockerCore)
@testable import BlockerCore
#else
@testable import blocker
#endif

@MainActor
final class BlockerCoreTests: XCTestCase {
    func testSetupWorkflowRoutesFromSetupToMain() {
        var model = BlockerDomainModel()
        XCTAssertEqual(model.route, .setup)
        XCTAssertEqual(model.setup.current, .screenTimeAccess)

        for step in SetupStep.allCases.dropLast() {
            XCTAssertEqual(model.setup.current, step)
            if step == .screenTimeAccess {
                model.setScreenTimePermission(true)
            }
            if step == .disableDeletingApps {
                model.setDeletingAppsDisabled(true)
            }
            if step == .chooseWhatToBlock {
                model.addBlock(named: "TikTok")
            }
            model.acceptSetupStep()
            XCTAssertFalse(model.setup.isComplete)
        }

        model.acceptSetupStep()
        XCTAssertTrue(model.setup.isComplete)
        XCTAssertEqual(model.route, .main)
    }

    func testSetupCannotAdvancePastDevicePermissionStepsUntilTheyAreEnabled() {
        var model = BlockerDomainModel()

        XCTAssertEqual(model.setup.current, .screenTimeAccess)
        XCTAssertFalse(model.canAdvanceSetup)
        model.acceptSetupStep()
        XCTAssertEqual(model.setup.current, .screenTimeAccess)

        model.setScreenTimePermission(true)
        XCTAssertTrue(model.canAdvanceSetup)
        model.acceptSetupStep()
        XCTAssertEqual(model.setup.current, .screenTimePassword)

        model.acceptSetupStep()
        XCTAssertEqual(model.setup.current, .disableDeletingApps)
        XCTAssertFalse(model.canAdvanceSetup)

        model.acceptSetupStep()
        XCTAssertEqual(model.setup.current, .disableDeletingApps)
        model.setDeletingAppsDisabled(true)
        XCTAssertTrue(model.canAdvanceSetup)
    }

    func testSetupCannotLeaveChooseBlocksEmptyAndCanCollectSeveralBlocks() {
        var model = BlockerDomainModel()
        model.setScreenTimePermission(true)
        model.setDeletingAppsDisabled(true)
        model.acceptSetupStep()
        model.acceptSetupStep()
        model.acceptSetupStep()

        XCTAssertEqual(model.setup.current, .chooseWhatToBlock)
        XCTAssertFalse(model.canAdvanceSetup)

        model.acceptSetupStep()
        XCTAssertEqual(model.setup.current, .chooseWhatToBlock)

        model.addBlock(named: "TikTok")
        model.addBlock(named: "Reddit")

        XCTAssertEqual(model.blocks.map(\.name), ["Reddit", "TikTok"])
        XCTAssertTrue(model.canAdvanceSetup)

        model.acceptSetupStep()
        XCTAssertEqual(model.setup.current, .blockConfirmation)
    }

    func testSetupCanNavigateBackwardWithoutLosingSelectedBlocks() {
        var model = BlockerDomainModel()
        XCTAssertFalse(model.canGoBackInSetup)

        model.setScreenTimePermission(true)
        model.setDeletingAppsDisabled(true)
        model.acceptSetupStep()
        model.acceptSetupStep()
        model.acceptSetupStep()
        model.addBlock(named: "TikTok")
        model.acceptSetupStep()

        XCTAssertEqual(model.setup.current, .blockConfirmation)
        XCTAssertTrue(model.canGoBackInSetup)

        model.goBackSetupStep()

        XCTAssertEqual(model.setup.current, .chooseWhatToBlock)
        XCTAssertEqual(model.blocks.map(\.name), ["TikTok"])

        model.goBackSetupStep()
        XCTAssertEqual(model.setup.current, .disableDeletingApps)
    }

    func testSettingsDefaultsAndPermissionToggles() {
        var model = BlockerDomainModel()
        XCTAssertTrue(model.settings.blockAppsByDefault)
        XCTAssertTrue(model.settings.blockWebsitesByDefault)
        XCTAssertFalse(model.permissions.hasScreenTimeAccess)
        XCTAssertFalse(model.permissions.isDeletingAppsDisabled)

        model.setDefaultBlockScope(.app, isBlocked: false)
        model.setDefaultBlockScope(.web, isBlocked: false)
        model.setScreenTimePermission(true)
        model.setDeletingAppsDisabled(true)

        XCTAssertFalse(model.settings.blockAppsByDefault)
        XCTAssertFalse(model.settings.blockWebsitesByDefault)
        XCTAssertTrue(model.permissions.hasScreenTimeAccess)
        XCTAssertTrue(model.permissions.isDeletingAppsDisabled)
    }

    func testSuggestionsAndScopedAddFlow() {
        var model = BlockerDomainModel()
        XCTAssertEqual(model.suggestions(matching: "tik").first?.name, "TikTok")

        XCTAssertEqual(model.addBlock(named: "TikTok"), .added)
        XCTAssertEqual(model.blocks.first?.domain, "tiktok.com")
        XCTAssertEqual(model.blocks.first?.appBundleIdentifier, "com.zhiliaoapp.musically")
        XCTAssertEqual(model.blocks.first?.blocksApp, true)
        XCTAssertEqual(model.blocks.first?.blocksWeb, true)
        XCTAssertEqual(model.restrictionPlan.appBundleIdentifiers, ["com.zhiliaoapp.musically"])
        XCTAssertEqual(model.restrictionPlan.webDomains, ["tiktok.com"])

        var scoped = BlockerDomainModel()
        scoped.setDefaultBlockScope(.app, isBlocked: false)
        scoped.setDefaultBlockScope(.web, isBlocked: false)
        guard case let .needsScopeConfirmation(pending) = scoped.addBlock(named: "reddit") else {
            XCTFail("Expected scoped confirmation")
            return
        }

        scoped.confirmPendingBlock(pending, blockApp: false, blockWeb: true)
        XCTAssertEqual(scoped.blocks.first?.name, "Reddit")
        XCTAssertEqual(scoped.blocks.first?.blocksApp, false)
        XCTAssertEqual(scoped.blocks.first?.blocksWeb, true)
        XCTAssertTrue(scoped.restrictionPlan.appBundleIdentifiers.isEmpty)
        XCTAssertEqual(scoped.restrictionPlan.webDomains, ["reddit.com"])
    }

    func testDefaultAppAndWebScopeSettingsControlNewBlocks() {
        var appOnly = BlockerDomainModel()
        appOnly.setDefaultBlockScope(.web, isBlocked: false)
        XCTAssertEqual(appOnly.addBlock(named: "TikTok"), .added)
        XCTAssertEqual(appOnly.blocks[0].blocksApp, true)
        XCTAssertEqual(appOnly.blocks[0].blocksWeb, false)
        XCTAssertEqual(appOnly.restrictionPlan.appBundleIdentifiers, ["com.zhiliaoapp.musically"])
        XCTAssertTrue(appOnly.restrictionPlan.webDomains.isEmpty)

        var webOnly = BlockerDomainModel()
        webOnly.setDefaultBlockScope(.app, isBlocked: false)
        XCTAssertEqual(webOnly.addBlock(named: "TikTok"), .added)
        XCTAssertEqual(webOnly.blocks[0].blocksApp, false)
        XCTAssertEqual(webOnly.blocks[0].blocksWeb, true)
        XCTAssertTrue(webOnly.restrictionPlan.appBundleIdentifiers.isEmpty)
        XCTAssertEqual(webOnly.restrictionPlan.webDomains, ["tiktok.com"])

        var neither = BlockerDomainModel()
        neither.setDefaultBlockScope(.app, isBlocked: false)
        neither.setDefaultBlockScope(.web, isBlocked: false)
        guard case .needsScopeConfirmation = neither.addBlock(named: "TikTok") else {
            XCTFail("Expected empty defaults to ask for scope")
            return
        }

        var customAppOnly = BlockerDomainModel()
        customAppOnly.setDefaultBlockScope(.web, isBlocked: false)
        guard case .needsScopeConfirmation = customAppOnly.addBlock(named: "example.com") else {
            XCTFail("Expected app-only custom website to ask for scope")
            return
        }
    }

    func testTypedPopularAppsProduceAppAndWebRestrictionsImmediately() {
        var model = BlockerDomainModel()
        model.addBlock(named: "TikTok")

        XCTAssertFalse(model.isBlockingEnabled)
        XCTAssertEqual(model.restrictionPlan.appBundleIdentifiers, ["com.zhiliaoapp.musically"])
        XCTAssertEqual(model.restrictionPlan.webDomains, ["tiktok.com"])

        let id = model.blocks[0].id
        model.setBlockScope(id: id, scope: .app, isBlocked: false)

        XCTAssertTrue(model.restrictionPlan.appBundleIdentifiers.isEmpty)
        XCTAssertEqual(model.restrictionPlan.webDomains, ["tiktok.com"])
    }

    func testCustomWebsitesOnlyCreateWebRestrictionsWhenNoAppIsKnown() {
        var model = BlockerDomainModel()
        model.addBlock(named: "example.com")

        XCTAssertEqual(model.blocks.count, 1)
        XCTAssertNil(model.blocks[0].appBundleIdentifier)
        XCTAssertFalse(model.blocks[0].blocksApp)
        XCTAssertTrue(model.blocks[0].blocksWeb)
        XCTAssertTrue(model.restrictionPlan.appBundleIdentifiers.isEmpty)
        XCTAssertEqual(model.restrictionPlan.webDomains, ["example.com"])
    }

    func testBlankBlockInputIsIgnoredAndNeverBecomesDotCom() {
        var model = BlockerDomainModel()
        let invalidInputs = ["", " ", "\n", ".", ".com", "https://", "http://", "www."]

        for input in invalidInputs {
            XCTAssertEqual(model.addBlock(named: input), .ignored)
            XCTAssertTrue(model.blocks.isEmpty)
        }
    }

    func testBlockItemsAreDeletedOnlyWhenInactive() {
        var model = BlockerDomainModel()
        model.addBlock(named: "TikTok")
        let id = model.blocks[0].id

        model.setBlockScope(id: id, scope: .app, isBlocked: false)
        XCTAssertFalse(model.blocks[0].canDelete)

        model.setBlockScope(id: id, scope: .web, isBlocked: false)
        XCTAssertTrue(model.blocks[0].canDelete)

        model.deleteBlock(id: id)
        XCTAssertTrue(model.blocks.isEmpty)
    }

    func testSetupReturnsToChooseBlocksWhenConfirmationHasNoActiveScopes() {
        var model = BlockerDomainModel()
        model.setScreenTimePermission(true)
        model.setDeletingAppsDisabled(true)
        model.acceptSetupStep()
        model.acceptSetupStep()
        model.acceptSetupStep()
        XCTAssertEqual(model.setup.current, .chooseWhatToBlock)

        _ = model.addBlock(named: "TikTok")
        model.acceptSetupStep()
        XCTAssertEqual(model.setup.current, .blockConfirmation)

        let id = model.blocks[0].id
        model.setBlockScope(id: id, scope: .app, isBlocked: false)
        model.setBlockScope(id: id, scope: .web, isBlocked: false)
        XCTAssertFalse(model.hasActiveBlocks)

        model.recoverSetupAfterBlocksEmptied()
        XCTAssertEqual(model.setup.current, .chooseWhatToBlock)
        XCTAssertEqual(model.route, .setup)
    }

    func testLockingRequiresPermissionsAndActiveLocksThenLocksEditsWithoutActivatingRestrictions() {
        var model = readyForBlocking()
        let initialPlan = model.restrictionPlan
        XCTAssertFalse(model.isBlockingEnabled)
        XCTAssertEqual(initialPlan.appBundleIdentifiers, ["com.zhiliaoapp.musically"])
        XCTAssertEqual(initialPlan.webDomains, ["tiktok.com"])

        XCTAssertEqual(model.enableBlocking(), .enabled)
        XCTAssertTrue(model.isBlockingEnabled)
        XCTAssertFalse(model.canEditPermissions)
        XCTAssertFalse(model.canEditBlocks)
        XCTAssertEqual(model.restrictionPlan, initialPlan)

        model.setScreenTimePermission(false)
        model.setDeletingAppsDisabled(false)
        model.setBlockScope(id: model.blocks[0].id, scope: .app, isBlocked: false)
        model.addBlock(named: "Reddit")
        model.setDefaultBlockScope(.app, isBlocked: false)

        XCTAssertTrue(model.permissions.hasScreenTimeAccess)
        XCTAssertTrue(model.permissions.isDeletingAppsDisabled)
        XCTAssertTrue(model.blocks[0].blocksApp)
        XCTAssertEqual(model.blocks.map(\.name), ["TikTok"])
        XCTAssertTrue(model.settings.blockAppsByDefault)
    }

    func testRestoredEnabledBlockingBypassesStaleSetupRoute() throws {
        var model = try blockingModelWithStaleSetupRoute()
        XCTAssertEqual(model.route, .setup)
        XCTAssertFalse(model.setup.isComplete)
        XCTAssertTrue(model.isBlockingEnabled)

        model.refresh(now: Date(timeIntervalSince1970: 1_500))

        XCTAssertTrue(model.setup.isComplete)
        XCTAssertEqual(model.route, .main)
        XCTAssertFalse(model.canEditPermissions)
    }

    func testUnblockCountdownPersistsAndFinishesAfterSingleTimer() throws {
        var model = readyForBlocking()
        model.enableBlocking()

        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(model.requestUnblock(now: start), .started)

        let data = try JSONEncoder().encode(model)
        var restored = try JSONDecoder().decode(BlockerDomainModel.self, from: data)
        let twoSecondsLater = start.addingTimeInterval(2)
        restored.refresh(now: twoSecondsLater)

        XCTAssertEqual(restored.remainingUnblockSeconds(now: twoSecondsLater), 1)
        XCTAssertTrue(restored.isBlockingEnabled)
        XCTAssertTrue(restored.isUnblockPending)
        XCTAssertTrue(restored.scheduledNotifications.isEmpty)

        let finished = start.addingTimeInterval(3)
        restored.refresh(now: finished)
        XCTAssertEqual(restored.route, .main)
        XCTAssertFalse(restored.isUnblockPending)
        XCTAssertEqual(restored.scheduledNotifications.map(\.kind), [.unblockReady])
        XCTAssertFalse(restored.isBlockingEnabled)
        XCTAssertTrue(restored.canEditBlocks)
    }

    func testPendingUnblockCanBeCanceledToKeepFullBlock() {
        var runningModel = readyForBlocking()
        runningModel.enableBlocking()

        let start = Date(timeIntervalSince1970: 1_800)
        runningModel.requestUnblock(now: start)

        runningModel.cancelUnblockRequest()

        XCTAssertFalse(runningModel.isUnblockPending)
        XCTAssertTrue(runningModel.isBlockingEnabled)
        XCTAssertEqual(runningModel.route, .main)
        XCTAssertEqual(runningModel.remainingUnblockSeconds(now: start), 0)
        XCTAssertTrue(runningModel.scheduledNotifications.isEmpty)
    }

    func testFinishedUnlockAllowsMainPageBlockEdits() {
        var model = modelAfterFinishedUnlock()
        let tiktok = model.blocks.first { $0.name == "TikTok" }!

        XCTAssertEqual(model.route, .main)
        XCTAssertFalse(model.isBlockingEnabled)
        XCTAssertEqual(model.restrictionPlan.appBundleIdentifiers, ["com.zhiliaoapp.musically"])

        model.setBlockScope(id: tiktok.id, scope: .app, isBlocked: false)
        XCTAssertTrue(model.restrictionPlan.appBundleIdentifiers.isEmpty)

        model.setBlockScope(id: tiktok.id, scope: .app, isBlocked: true)
        XCTAssertEqual(model.restrictionPlan.appBundleIdentifiers, ["com.zhiliaoapp.musically"])
    }

    private func readyForBlocking(extraBlock: String? = nil) -> BlockerDomainModel {
        var model = BlockerDomainModel()
        model.setScreenTimePermission(true)
        model.setDeletingAppsDisabled(true)
        for _ in SetupStep.allCases {
            if model.setup.current == .chooseWhatToBlock {
                model.addBlock(named: "TikTok")
            }

            model.acceptSetupStep()
        }
        model.setScreenTimePermission(true)
        model.setDeletingAppsDisabled(true)
        if let extraBlock {
            model.addBlock(named: extraBlock)
        }
        return model
    }

    private func blockingModelWithStaleSetupRoute() throws -> BlockerDomainModel {
        var model = readyForBlocking()
        model.enableBlocking()

        let data = try JSONEncoder().encode(model)
        guard var payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var setup = payload["setup"] as? [String: Any] else {
            XCTFail("Could not create stale setup payload")
            return model
        }

        setup["isComplete"] = false
        setup["current"] = SetupStep.blockConfirmation.rawValue
        payload["setup"] = setup
        payload["route"] = AppRoute.setup.rawValue

        let staleData = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(BlockerDomainModel.self, from: staleData)
    }

    private func modelAfterFinishedUnlock(extraBlock: String? = nil) -> BlockerDomainModel {
        var model = readyForBlocking(extraBlock: extraBlock)
        model.enableBlocking()

        let start = Date(timeIntervalSince1970: 2_000)
        model.requestUnblock(now: start)
        model.refresh(now: start.addingTimeInterval(3))
        return model
    }
}
