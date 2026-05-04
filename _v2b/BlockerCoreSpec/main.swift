import BlockerCore
import Foundation

enum SpecFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message):
            message
        }
    }
}

func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String,
    file: StaticString = #file,
    line: UInt = #line
) throws {
    if !condition() {
        throw SpecFailure.failed("\(file):\(line): \(message)")
    }
}

func run(_ name: String, _ body: () throws -> Void) rethrows {
    try body()
    print("✓ \(name)")
}

try run("setup starts at Screen Time access and routes to setup") {
    let model = BlockerDomainModel()

    try expect(model.route == .setup, "expected initial setup route")
    try expect(model.setup.current == .screenTimeAccess, "expected first setup step")
    try expect(model.setup.current.title == "Screen Time Access", "expected first setup title")
    try expect(!model.setup.isComplete, "setup should not start complete")
}

try run("setup accept advances through every page then completes") {
    var model = BlockerDomainModel()

    let expectedSteps: [SetupStep] = [
        .screenTimeAccess,
        .screenTimePassword,
        .disableDeletingApps,
        .chooseWhatToBlock,
        .blockConfirmation
    ]

    try expect(SetupStep.allCases == expectedSteps, "setup steps changed order")

    for step in expectedSteps.dropLast() {
        try expect(model.setup.current == step, "expected current step \(step)")
        if step == .screenTimeAccess {
            model.setScreenTimePermission(true)
        }
        if step == .disableDeletingApps {
            model.setDeletingAppsDisabled(true)
        }
        if step == .chooseWhatToBlock {
            _ = model.addBlock(named: "TikTok")
        }
        model.acceptSetupStep()
        try expect(!model.setup.isComplete, "setup completed too early")
    }

    try expect(model.setup.current == .blockConfirmation, "expected block confirmation")
    model.acceptSetupStep()

    try expect(model.setup.isComplete, "setup should complete on final accept")
    try expect(model.route == .main, "completed setup should route to main")
}

try run("setup cannot advance past device permission steps until they are enabled") {
    var model = BlockerDomainModel()

    try expect(model.setup.current == .screenTimeAccess, "expected screen time access first")
    try expect(!model.canAdvanceSetup, "setup should wait for actual Screen Time permission")
    model.acceptSetupStep()
    try expect(model.setup.current == .screenTimeAccess, "accept should not skip Screen Time permission")

    model.setScreenTimePermission(true)
    try expect(model.canAdvanceSetup, "granted Screen Time permission should allow continuing")
    model.acceptSetupStep()
    try expect(model.setup.current == .screenTimePassword, "expected Screen Time passcode explanation")

    model.acceptSetupStep()
    try expect(model.setup.current == .disableDeletingApps, "expected delete-apps setup step")
    try expect(!model.canAdvanceSetup, "setup should wait until app deletion is disabled")

    model.acceptSetupStep()
    try expect(model.setup.current == .disableDeletingApps, "accept should not skip delete-apps restriction")
    model.setDeletingAppsDisabled(true)
    try expect(model.canAdvanceSetup, "disabled app deletion should allow continuing")
}

try run("setup cannot leave Choose What To Block empty and can collect several blocks") {
    var model = BlockerDomainModel()
    model.setScreenTimePermission(true)
    model.setDeletingAppsDisabled(true)
    model.acceptSetupStep()
    model.acceptSetupStep()
    model.acceptSetupStep()

    try expect(model.setup.current == .chooseWhatToBlock, "expected block-selection setup step")
    try expect(!model.canAdvanceSetup, "empty block selection should disable progression")

    model.acceptSetupStep()
    try expect(model.setup.current == .chooseWhatToBlock, "empty block selection should stay on the same step")

    _ = model.addBlock(named: "TikTok")
    _ = model.addBlock(named: "Reddit")

    try expect(model.blocks.map(\.name) == ["Reddit", "TikTok"], "setup should allow multiple selected blocks")
    try expect(model.canAdvanceSetup, "active blocks should enable progression")

    model.acceptSetupStep()
    try expect(model.setup.current == .blockConfirmation, "selected blocks should allow confirmation")
}

try run("setup can navigate backward without losing selected blocks") {
    var model = BlockerDomainModel()
    try expect(!model.canGoBackInSetup, "first setup step should not go back")

    model.setScreenTimePermission(true)
    model.setDeletingAppsDisabled(true)
    model.acceptSetupStep()
    model.acceptSetupStep()
    model.acceptSetupStep()
    _ = model.addBlock(named: "TikTok")
    model.acceptSetupStep()

    try expect(model.setup.current == .blockConfirmation, "expected confirmation before going back")
    try expect(model.canGoBackInSetup, "confirmation should allow going back")

    model.goBackSetupStep()

    try expect(model.setup.current == .chooseWhatToBlock, "back should return to block selection")
    try expect(model.blocks.map(\.name) == ["TikTok"], "back navigation should keep selected blocks")

    model.goBackSetupStep()
    try expect(model.setup.current == .disableDeletingApps, "back should move one step at a time")
}

try run("settings default to blocking app and web and track permissions") {
    var model = BlockerDomainModel()

    try expect(model.settings.blockAppsByDefault, "app default should start on")
    try expect(model.settings.blockWebsitesByDefault, "web default should start on")
    try expect(!model.permissions.hasScreenTimeAccess, "screen time should start unauthorized")
    try expect(!model.permissions.isDeletingAppsDisabled, "deleting apps should start allowed")

    model.setDefaultBlockScope(.app, isBlocked: false)
    model.setDefaultBlockScope(.web, isBlocked: false)
    model.setScreenTimePermission(true)
    model.setDeletingAppsDisabled(true)

    try expect(!model.settings.blockAppsByDefault, "app default should be mutable")
    try expect(!model.settings.blockWebsitesByDefault, "web default should be mutable")
    try expect(model.permissions.hasScreenTimeAccess, "screen time toggle should be saved")
    try expect(model.permissions.isDeletingAppsDisabled, "delete-apps toggle should be saved")
}

try run("popular suggestions match typed app and website names") {
    let model = BlockerDomainModel()
    let suggestions = model.suggestions(matching: "tik")

    try expect(suggestions.first?.name == "TikTok", "expected TikTok as top match")
    try expect(suggestions.first?.domain == "tiktok.com", "expected TikTok website")
}

try run("adding while block-both is enabled creates an app and web block") {
    var model = BlockerDomainModel()
    let outcome = model.addBlock(named: "TikTok")

    try expect(outcome == .added, "block both should add immediately")
    try expect(model.blocks.count == 1, "expected one block")
    try expect(model.blocks[0].name == "TikTok", "expected normalized display name")
    try expect(model.blocks[0].domain == "tiktok.com", "expected normalized domain")
    try expect(model.blocks[0].appBundleIdentifier == "com.zhiliaoapp.musically", "expected known app bundle identifier")
    try expect(model.blocks[0].blocksApp, "expected app to be blocked")
    try expect(model.blocks[0].blocksWeb, "expected web to be blocked")
}

try run("typed popular apps produce app and web restrictions immediately") {
    var model = BlockerDomainModel()
    _ = model.addBlock(named: "TikTok")

    try expect(!model.isBlockingEnabled, "adding an item should not lock Blocker")
    try expect(model.restrictionPlan.appBundleIdentifiers == ["com.zhiliaoapp.musically"], "typed app should produce app bundle restriction")
    try expect(model.restrictionPlan.webDomains == ["tiktok.com"], "typed app should produce website restriction")

    let id = model.blocks[0].id
    model.setBlockScope(id: id, scope: .app, isBlocked: false)

    try expect(model.restrictionPlan.appBundleIdentifiers.isEmpty, "turning app off should remove the app restriction")
    try expect(model.restrictionPlan.webDomains == ["tiktok.com"], "web restriction should remain active")
}

try run("custom websites only create web restrictions when no app is known") {
    var model = BlockerDomainModel()
    _ = model.addBlock(named: "example.com")

    try expect(model.blocks.count == 1, "expected one custom website")
    try expect(model.blocks[0].appBundleIdentifier == nil, "custom website should not invent an app bundle")
    try expect(!model.blocks[0].blocksApp, "custom website should not show a fake app lock")
    try expect(model.blocks[0].blocksWeb, "custom website should still lock web")
    try expect(model.restrictionPlan.appBundleIdentifiers.isEmpty, "custom website should not create app restrictions")
    try expect(model.restrictionPlan.webDomains == ["example.com"], "custom website should create web restriction")
}

try run("blank block input is ignored and never becomes dot com") {
    var model = BlockerDomainModel()
    let invalidInputs = ["", " ", "\n", ".", ".com", "https://", "http://", "www."]

    for input in invalidInputs {
        try expect(model.addBlock(named: input) == .ignored, "expected invalid input '\(input)' to be ignored")
        try expect(model.blocks.isEmpty, "invalid input '\(input)' should not add a block")
    }
}

try run("adding while block-both is disabled asks for app or web scope") {
    var model = BlockerDomainModel()
    model.setDefaultBlockScope(.app, isBlocked: false)
    model.setDefaultBlockScope(.web, isBlocked: false)

    let outcome = model.addBlock(named: "reddit")
    guard case let .needsScopeConfirmation(pending) = outcome else {
        throw SpecFailure.failed("expected add to require scope confirmation")
    }

    model.confirmPendingBlock(pending, blockApp: false, blockWeb: true)

    try expect(model.blocks.count == 1, "expected confirmed block")
    try expect(model.blocks[0].name == "Reddit", "expected normalized name")
    try expect(!model.blocks[0].blocksApp, "app should not be blocked")
    try expect(model.blocks[0].blocksWeb, "web should be blocked")
    try expect(model.restrictionPlan.appBundleIdentifiers.isEmpty, "unselected app should not be restricted")
    try expect(model.restrictionPlan.webDomains == ["reddit.com"], "selected web should be restricted")
}

try run("default app and web scope settings control newly added blocks") {
    var appOnly = BlockerDomainModel()
    appOnly.setDefaultBlockScope(.web, isBlocked: false)
    try expect(appOnly.addBlock(named: "TikTok") == .added, "app-only default should add known apps immediately")
    try expect(appOnly.blocks[0].blocksApp, "app-only default should enable app scope")
    try expect(!appOnly.blocks[0].blocksWeb, "app-only default should not enable web scope")
    try expect(appOnly.restrictionPlan.appBundleIdentifiers == ["com.zhiliaoapp.musically"], "app-only default should restrict app")
    try expect(appOnly.restrictionPlan.webDomains.isEmpty, "app-only default should not restrict web")

    var webOnly = BlockerDomainModel()
    webOnly.setDefaultBlockScope(.app, isBlocked: false)
    try expect(webOnly.addBlock(named: "TikTok") == .added, "web-only default should add immediately")
    try expect(!webOnly.blocks[0].blocksApp, "web-only default should not enable app scope")
    try expect(webOnly.blocks[0].blocksWeb, "web-only default should enable web scope")
    try expect(webOnly.restrictionPlan.appBundleIdentifiers.isEmpty, "web-only default should not restrict app")
    try expect(webOnly.restrictionPlan.webDomains == ["tiktok.com"], "web-only default should restrict web")

    var neither = BlockerDomainModel()
    neither.setDefaultBlockScope(.app, isBlocked: false)
    neither.setDefaultBlockScope(.web, isBlocked: false)
    guard case .needsScopeConfirmation = neither.addBlock(named: "TikTok") else {
        throw SpecFailure.failed("empty defaults should ask for scope")
    }

    var customAppOnly = BlockerDomainModel()
    customAppOnly.setDefaultBlockScope(.web, isBlocked: false)
    guard case .needsScopeConfirmation = customAppOnly.addBlock(named: "example.com") else {
        throw SpecFailure.failed("app-only custom website should ask because no app can be blocked")
    }
}

try run("active block items become deletable only after app and web are unchecked") {
    var model = BlockerDomainModel()
    _ = model.addBlock(named: "TikTok")
    let id = model.blocks[0].id

    model.setBlockScope(id: id, scope: .app, isBlocked: false)
    try expect(!model.blocks[0].blocksApp, "app scope should be unchecked")
    try expect(model.blocks[0].blocksWeb, "web scope should remain checked")
    try expect(!model.blocks[0].canDelete, "item should not be deletable while one scope is active")

    model.setBlockScope(id: id, scope: .web, isBlocked: false)
    try expect(model.blocks[0].canDelete, "item should be deletable once both scopes are inactive")

    model.deleteBlock(id: id)
    try expect(model.blocks.isEmpty, "inactive item should be deleted")
}

try run("locking requires permissions and active blocks then locks edits without activating restrictions") {
    var model = completedSetupModel()
    model.setScreenTimePermission(true)
    model.setDeletingAppsDisabled(true)

    let initialPlan = model.restrictionPlan
    try expect(!model.isBlockingEnabled, "active locks should apply before Blocker is locked")
    try expect(initialPlan.appBundleIdentifiers == ["com.zhiliaoapp.musically"], "typed app should already be restricted before locking")
    try expect(initialPlan.webDomains == ["tiktok.com"], "typed website should already be restricted before locking")

    let id = model.blocks[0].id
    model.setBlockScope(id: id, scope: .app, isBlocked: false)
    model.setBlockScope(id: id, scope: .web, isBlocked: false)
    model.deleteBlock(id: id)
    try expect(model.enableBlocking() == .emptyBlockList, "empty lists should not lock Blocker")

    _ = model.addBlock(named: "TikTok")
    let activePlan = model.restrictionPlan
    try expect(model.canEditPermissions, "permissions should be editable before locking")
    try expect(model.enableBlocking() == .enabled, "valid setup should lock Blocker")
    try expect(model.isBlockingEnabled, "lock flag should be on")
    try expect(!model.canEditPermissions, "permissions should be locked while Blocker is locked")
    try expect(!model.canEditBlocks, "active locks should not be editable while Blocker is locked")
    try expect(model.restrictionPlan == activePlan, "locking should not change active restrictions")

    model.setScreenTimePermission(false)
    model.setDeletingAppsDisabled(false)
    model.setBlockScope(id: model.blocks[0].id, scope: .app, isBlocked: false)
    _ = model.addBlock(named: "Reddit")
    model.setDefaultBlockScope(.app, isBlocked: false)

    try expect(model.permissions.hasScreenTimeAccess, "screen time should not change while locked")
    try expect(model.permissions.isDeletingAppsDisabled, "delete-apps should not change while locked")
    try expect(model.blocks[0].blocksApp, "active locks should not change while locked")
    try expect(model.blocks.map(\.name) == ["TikTok"], "new blocks should not be added while locked")
    try expect(model.settings.blockAppsByDefault, "block settings should not change while locked")
}

try run("restored enabled blocking bypasses stale setup route") {
    var model = try blockingModelWithStaleSetupRoute()

    try expect(model.route == .setup, "fixture should simulate a stale setup route")
    try expect(!model.setup.isComplete, "fixture should simulate stale incomplete setup")
    try expect(model.isBlockingEnabled, "fixture should already have blocking enabled")

    model.refresh(now: Date(timeIntervalSince1970: 1_500))

    try expect(model.setup.isComplete, "enabled blocking should recover setup completion")
    try expect(model.route == .main, "enabled blocking should never show the setup flow")
    try expect(!model.canEditPermissions, "permissions should remain locked while blocking")
}

try run("unblock request starts a persisted three second countdown") {
    var model = readyForBlockingModel()
    _ = model.enableBlocking()

    let start = Date(timeIntervalSince1970: 1_000)
    try expect(model.requestUnblock(now: start) == .started, "expected unblock request to start")
    try expect(model.isUnblockPending, "unblock should be pending")
    try expect(model.remainingUnblockSeconds(now: start) == 3, "expected full test countdown")

    let data = try JSONEncoder().encode(model)
    var restored = try JSONDecoder().decode(BlockerDomainModel.self, from: data)
    let twoSecondsLater = start.addingTimeInterval(2)
    restored.refresh(now: twoSecondsLater)

    try expect(restored.isUnblockPending, "restored countdown should still be pending")
    try expect(restored.remainingUnblockSeconds(now: twoSecondsLater) == 1, "countdown should continue after restore")
    try expect(restored.isBlockingEnabled, "blocking should remain enabled during pending unblock")
    try expect(restored.scheduledNotifications.isEmpty, "single timer should not schedule midpoint prompts")
}

try run("pending unblock can be canceled to keep the full block") {
    var runningModel = readyForBlockingModel()
    _ = runningModel.enableBlocking()

    let start = Date(timeIntervalSince1970: 1_800)
    _ = runningModel.requestUnblock(now: start)

    runningModel.cancelUnblockRequest()

    try expect(!runningModel.isUnblockPending, "cancel should clear a running unblock timer")
    try expect(runningModel.isBlockingEnabled, "cancel should keep blocking enabled")
    try expect(runningModel.route == .main, "cancel should stay on the main route")
    try expect(runningModel.remainingUnblockSeconds(now: start) == 0, "cancel should remove countdown state")
    try expect(runningModel.scheduledNotifications.isEmpty, "cancel should clear scheduled unblock notifications")
}

try run("unlock countdown finishes after one three second interval and unlocks the main page") {
    var model = readyForBlockingModel()
    _ = model.enableBlocking()

    let start = Date(timeIntervalSince1970: 2_000)
    _ = model.requestUnblock(now: start)

    let almostFinished = start.addingTimeInterval(2)
    model.refresh(now: almostFinished)

    try expect(model.isUnblockPending, "timer should keep running before three seconds")
    try expect(model.remainingUnblockSeconds(now: almostFinished) == 1, "timer should have one second left")
    try expect(model.scheduledNotifications.isEmpty, "timer should not schedule midpoint reconsider prompts")

    let finished = start.addingTimeInterval(3)
    model.refresh(now: finished)

    try expect(!model.isUnblockPending, "finished timer should no longer be pending")
    try expect(model.route == .main, "finished timer should return to the main page")
    try expect(model.scheduledNotifications.map(\.kind) == [.unblockReady], "finished timer should schedule only unblock-ready")
    try expect(!model.isBlockingEnabled, "finished timer should unlock Blocker")
    try expect(model.canEditBlocks, "main page blocks should be editable after unlocking")

    let id = model.blocks[0].id
    model.setBlockScope(id: id, scope: .app, isBlocked: false)
    try expect(model.restrictionPlan.appBundleIdentifiers.isEmpty, "unlocked main page edits should update app restrictions")
}

try run("legacy unlock review route recovers to unlocked main page") {
    var model = readyForBlockingModel()
    _ = model.enableBlocking()

    let start = Date(timeIntervalSince1970: 3_500)
    _ = model.requestUnblock(now: start)
    model.refresh(now: start.addingTimeInterval(3))

    try expect(model.route == .main, "completed unlock timers should no longer show a review route")
    try expect(!model.isBlockingEnabled, "completed unlock timers should unlock Blocker")
}

print("All BlockerCore specs passed.")

func completedSetupModel(initialBlock: String = "TikTok") -> BlockerDomainModel {
    var model = BlockerDomainModel()
    model.setScreenTimePermission(true)
    model.setDeletingAppsDisabled(true)

    for _ in SetupStep.allCases {
        if model.setup.current == .chooseWhatToBlock {
            _ = model.addBlock(named: initialBlock)
        }

        model.acceptSetupStep()
    }

    return model
}

func readyForBlockingModel(initialBlock: String = "TikTok") -> BlockerDomainModel {
    var model = completedSetupModel(initialBlock: initialBlock)
    model.setScreenTimePermission(true)
    model.setDeletingAppsDisabled(true)
    return model
}

func blockingModelWithStaleSetupRoute() throws -> BlockerDomainModel {
    var model = readyForBlockingModel()
    _ = model.enableBlocking()

    let data = try JSONEncoder().encode(model)
    guard var payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          var setup = payload["setup"] as? [String: Any] else {
        throw SpecFailure.failed("could not create stale setup payload")
    }

    setup["isComplete"] = false
    setup["current"] = SetupStep.blockConfirmation.rawValue
    payload["setup"] = setup
    payload["route"] = AppRoute.setup.rawValue

    let staleData = try JSONSerialization.data(withJSONObject: payload)
    return try JSONDecoder().decode(BlockerDomainModel.self, from: staleData)
}
