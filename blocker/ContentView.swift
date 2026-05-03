import SwiftUI
import UIKit
import UserNotifications
import FamilyControls
import ManagedSettings
import Combine

struct ContentView: View {
    @StateObject private var model = BlockerViewModel()

    var body: some View {
        NavigationStack {
            if model.isSetupComplete {
                MainView(model: model)
            } else {
                SetupView(model: model)
            }
        }
        .task {
            await model.restoreStateAfterLaunch()
        }
    }
}

struct SetupView: View {
    @ObservedObject var model: BlockerViewModel

    var body: some View {
        Form {
            Section("Screen Time Access") {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(model.authorizationStatusText)
                        .foregroundStyle(model.isAuthorized ? .green : .secondary)
                }

                if !model.isAuthorized {
                    Button("Request Permission") {
                        Task {
                            await model.requestAuthorization()
                        }
                    }
                }
            }

            Section {
                Toggle("Disable Deleting Apps", isOn: Binding(
                    get: { model.isDeleteAppsDisabled },
                    set: { newValue in
                        model.setDeleteAppsDisabled(newValue)
                    }
                ))
                .disabled(!model.isAuthorized)

                Toggle("Show Blocked List while blocked", isOn: Binding(
                    get: { model.showBlockedListWhileBlocked },
                    set: { newValue in
                        model.setShowBlockedListWhileBlocked(newValue)
                    }
                ))
            }
        }
        .navigationTitle("Setup")
    }
}

struct MainView: View {
    @ObservedObject var model: BlockerViewModel
    @State private var isShowingSetup = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if isShowingSetup {
                SetupView(model: model)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") {
                                isShowingSetup = false
                            }
                        }
                    }
            } else {
                Form {
                    Section {
                        Toggle(
                            model.isBlockingEnabled ? "Request Unblock" : "Enable Blocking",
                            isOn: Binding(
                                get: { model.isBlockingEnabled },
                                set: { newValue in
                                    if newValue {
                                        model.showEnableConfirmation = true
                                    } else {
                                        model.beginUnblockRequest()
                                    }
                                }
                            )
                        )
                        .disabled(model.isUnblockPending || model.pendingSuccumbConfirmation)
                        .alert("Are you sure?", isPresented: $model.showEnableConfirmation) {
                            Button("Cancel", role: .cancel) { }
                            Button("Enable") {
                                Task {
                                    await model.confirmEnableBlocking()
                                }
                            }
                        } message: {
                            Text("This will enable blocking for your saved domains.")
                        }

                        if model.isUnblockPending {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Your unblock request has been submitted.\n\nTime remaining: \(model.countdownFormattedHHMMSS)")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)

                                Button("Cancel") {
                                    model.cancelUnblockRequest()
                                }
                                .font(.footnote)
                                .foregroundStyle(.blue)
                                .buttonStyle(.plain)
                            }
                        }

                        if model.pendingSuccumbConfirmation && !model.isUnblockPending {
                            Text("Your timer has ended. Confirm below to finish unblocking.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }

                    if !model.isBlockingEnabled || model.showBlockedListWhileBlocked {
                        Section {
                            NavigationLink("Blocked Domains") {
                                BlockedDomainsView(model: model)
                            }

                            if !model.isBlockingEnabled {
                                Button {
                                    isShowingSetup = true
                                } label: {
                                    HStack {
                                        Text("Setup")
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .navigationTitle("Filter")
            }
        }
        .onChange(of: model.isSetupComplete) { _, complete in
            if complete {
                isShowingSetup = false
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                model.presentSuccumbPromptIfNeededOnBecomeActive()
            }
        }
        .overlay {
            if model.showSuccumbConfirmation {
                SuccumbConfirmationOverlay(model: model)
            }
        }
    }
}

private struct SuccumbConfirmationOverlay: View {
    @ObservedObject var model: BlockerViewModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            VStack(spacing: 20) {
                Text("Do you want to succumb?")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button("No") {
                        model.declineSuccumb()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Yes") {
                        model.confirmSuccumb()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.large)
                }
            }
            .padding(24)
            .frame(maxWidth: 300)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
        }
        .accessibilityAddTraits(.isModal)
    }
}

struct BlockedDomainsView: View {
    @ObservedObject var model: BlockerViewModel
    @State private var isShowingAppPicker = false

    var body: some View {
        Form {
            if !model.isBlockingEnabled {
                Section("Blocked Apps") {
                    Button("Choose Apps") {
                        isShowingAppPicker = true
                    }

                    if model.blockedAppsCount == 0 {
                        Text("No blocked apps selected")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(model.blockedAppsCount) app(s) selected")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Add Domain") {
                HStack {
                    TextField("example.com", text: $model.newDomain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button("Add") {
                        model.addDomain()
                    }
                    .disabled(model.newDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section("Blocked Domains") {
                if model.domains.isEmpty {
                    Text("No blocked domains yet")
                        .foregroundStyle(.secondary)
                } else if model.isBlockingEnabled {
                    ForEach(model.domains, id: \.self) { domain in
                        Text(domain)
                    }
                } else {
                    ForEach(model.domains, id: \.self) { domain in
                        Text(domain)
                    }
                    .onDelete(perform: model.removeDomains)
                }
            }
        }
        .navigationTitle("Blocked Domains")
        .familyActivityPicker(
            isPresented: $isShowingAppPicker,
            selection: $model.blockedActivitySelection
        )
    }
}

@MainActor
final class BlockerViewModel: ObservableObject {
    @Published var newDomain = ""
    @Published var domains: [String] = []
    @Published var isBlockingEnabled = false
    @Published var isAuthorized = false
    @Published var isDeleteAppsDisabled = false
    @Published var showBlockedListWhileBlocked = false
    @Published var blockedActivitySelection = FamilyActivitySelection() {
        didSet {
            saveBlockedActivitySelection()

            if isAuthorized && isBlockingEnabled {
                applyStoredBlocking()
            }
        }
    }
    @Published var showEnableConfirmation = false
    @Published var countdownRemaining = 1
    @Published var isUnblockPending = false
    @Published var pendingSuccumbConfirmation = false
    @Published var showSuccumbConfirmation = false

    private var countdownTask: Task<Void, Never>?
    private var authorizationStatusCancellable: AnyCancellable?

    private let store = ManagedSettingsStore()
    private let defaultsKey = "blockedDomains"
    private let enabledKey = "blockingEnabled"
    private let deleteAppsDisabledKey = "deleteAppsDisabled"
    private let showBlockedListWhileBlockedKey = "showBlockedListWhileBlocked"
    private let blockedActivitySelectionKey = "blockedActivitySelection"
    private let unblockDelay = 5
    private let unblockTimerFinishedNotificationId = "unblockTimerFinished"

    init() {
        loadDomains()
        loadEnabledState()
        loadDeleteAppsDisabledState()
        loadShowBlockedListWhileBlockedState()
        loadBlockedActivitySelection()
        refreshAuthorizationStatus()

        authorizationStatusCancellable = AuthorizationCenter.shared.$authorizationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.updateAuthorized(from: status)
            }
    }

    var authorizationStatusText: String {
        isAuthorized ? "Authorized" : "Not Authorized"
    }

    var countdownFormattedHHMMSS: String {
        let total = max(0, countdownRemaining)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    var isSetupComplete: Bool {
        isAuthorized && isDeleteAppsDisabled
    }

    var blockedAppsCount: Int {
        blockedActivitySelection.applicationTokens.count
    }

    func restoreStateAfterLaunch() async {
        refreshAuthorizationStatus()

        guard isAuthorized else {
            return
        }

        if isBlockingEnabled {
            applyStoredBlocking()
        }

        applyDeleteAppsRestriction()
    }

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
        }

        refreshAuthorizationStatus()

        if isAuthorized {
            if isBlockingEnabled {
                applyStoredBlocking()
            }

            applyDeleteAppsRestriction()
        }
    }

    func setBlockingEnabled(_ enabled: Bool) async {
        guard isAuthorized else {
            isBlockingEnabled = false
            UserDefaults.standard.set(false, forKey: enabledKey)
            return
        }

        if !enabled {
            isBlockingEnabled = true
            return
        }

        guard !domains.isEmpty || !blockedActivitySelection.applicationTokens.isEmpty else {
            isBlockingEnabled = false
            UserDefaults.standard.set(false, forKey: enabledKey)
            return
        }

        isBlockingEnabled = true
        UserDefaults.standard.set(true, forKey: enabledKey)
        applyStoredBlocking()
    }

    func confirmEnableBlocking() async {
        await setBlockingEnabled(true)
    }

    func cancelUnblockRequest() {
        removeUnblockTimerNotifications()
        countdownTask?.cancel()
        countdownTask = nil
        isUnblockPending = false
        pendingSuccumbConfirmation = false
        showSuccumbConfirmation = false
    }

    func beginUnblockRequest() {
        guard isAuthorized, isBlockingEnabled else {
            return
        }

        pendingSuccumbConfirmation = false
        showSuccumbConfirmation = false
        removeUnblockTimerNotifications()

        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }

        isUnblockPending = true
        countdownRemaining = unblockDelay

        countdownTask?.cancel()
        countdownTask = Task { @MainActor in
            while countdownRemaining > 0 {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                countdownRemaining -= 1
            }
            guard !Task.isCancelled else {
                return
            }
            onUnblockTimerFinished()
            countdownTask = nil
        }
    }

    func presentSuccumbPromptIfNeededOnBecomeActive() {
        guard pendingSuccumbConfirmation else {
            return
        }
        showSuccumbConfirmation = true
    }

    func confirmSuccumb() {
        removeUnblockTimerNotifications()
        pendingSuccumbConfirmation = false
        showSuccumbConfirmation = false
        clearBlocking()
    }

    func declineSuccumb() {
        removeUnblockTimerNotifications()
        pendingSuccumbConfirmation = false
        showSuccumbConfirmation = false
    }

    func clearBlocking() {
        removeUnblockTimerNotifications()
        countdownTask?.cancel()
        countdownTask = nil
        store.webContent.blockedByFilter = nil
        store.shield.applications = nil
        isBlockingEnabled = false
        isUnblockPending = false
        pendingSuccumbConfirmation = false
        showSuccumbConfirmation = false
        UserDefaults.standard.set(false, forKey: enabledKey)
    }

    private func onUnblockTimerFinished() {
        guard isBlockingEnabled else {
            isUnblockPending = false
            return
        }

        isUnblockPending = false
        pendingSuccumbConfirmation = true

        if UIApplication.shared.applicationState == .active {
            showSuccumbConfirmation = true
        } else {
            Task {
                await scheduleUnblockTimerFinishedNotification()
            }
        }
    }

    private func scheduleUnblockTimerFinishedNotification() async {
        let content = UNMutableNotificationContent()
        content.title = "Filter"
        content.body = "Your unblock timer has finished. Open the app to continue."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(
            identifier: unblockTimerFinishedNotificationId,
            content: content,
            trigger: trigger
        )

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [unblockTimerFinishedNotificationId])
        try? await center.add(request)
    }

    private func removeUnblockTimerNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [unblockTimerFinishedNotificationId])
        center.removeDeliveredNotifications(withIdentifiers: [unblockTimerFinishedNotificationId])
    }

    func setDeleteAppsDisabled(_ disabled: Bool) {
        guard isAuthorized else {
            isDeleteAppsDisabled = false
            UserDefaults.standard.set(false, forKey: deleteAppsDisabledKey)
            return
        }

        isDeleteAppsDisabled = disabled
        UserDefaults.standard.set(disabled, forKey: deleteAppsDisabledKey)
        applyDeleteAppsRestriction()
    }

    func setShowBlockedListWhileBlocked(_ enabled: Bool) {
        showBlockedListWhileBlocked = enabled
        UserDefaults.standard.set(enabled, forKey: showBlockedListWhileBlockedKey)
    }

    func addDomain() {
        let cleaned = normalizeDomain(newDomain)

        guard !cleaned.isEmpty else {
            return
        }

        guard !domains.contains(cleaned) else {
            newDomain = ""
            return
        }

        domains.append(cleaned)
        domains.sort()
        saveDomains()
        newDomain = ""

        if isAuthorized && isBlockingEnabled {
            applyStoredBlocking()
        }
    }

    func removeDomains(at offsets: IndexSet) {
        domains.remove(atOffsets: offsets)
        domains.sort()
        saveDomains()

        if domains.isEmpty {
            clearBlocking()
            return
        }

        if isAuthorized && isBlockingEnabled {
            applyStoredBlocking()
        }
    }

    private func refreshAuthorizationStatus() {
        updateAuthorized(from: AuthorizationCenter.shared.authorizationStatus)
    }

    private func updateAuthorized(from status: AuthorizationStatus) {
        switch status {
        case .approved, .approvedWithDataAccess:
            isAuthorized = true
        default:
            isAuthorized = false
        }
    }

    private func applyStoredBlocking() {
        let webDomains = Set(domains.map { WebDomain(domain: $0) })
        store.webContent.blockedByFilter = .specific(webDomains)

        let appTokens = blockedActivitySelection.applicationTokens
        store.shield.applications = appTokens.isEmpty ? nil : appTokens
    }

    private func applyDeleteAppsRestriction() {
        store.application.denyAppRemoval = isDeleteAppsDisabled ? true : nil
    }

    private func loadDomains() {
        domains = (UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []).sorted()
    }

    private func saveDomains() {
        UserDefaults.standard.set(domains.sorted(), forKey: defaultsKey)
    }

    private func loadEnabledState() {
        isBlockingEnabled = UserDefaults.standard.bool(forKey: enabledKey)
    }

    private func loadDeleteAppsDisabledState() {
        isDeleteAppsDisabled = UserDefaults.standard.bool(forKey: deleteAppsDisabledKey)
    }

    private func loadShowBlockedListWhileBlockedState() {
        showBlockedListWhileBlocked = UserDefaults.standard.bool(forKey: showBlockedListWhileBlockedKey)
    }

    private func saveBlockedActivitySelection() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(blockedActivitySelection) else {
            return
        }

        UserDefaults.standard.set(data, forKey: blockedActivitySelectionKey)
    }

    private func loadBlockedActivitySelection() {
        guard let data = UserDefaults.standard.data(forKey: blockedActivitySelectionKey) else {
            return
        }

        let decoder = JSONDecoder()
        guard let selection = try? decoder.decode(FamilyActivitySelection.self, from: data) else {
            return
        }

        blockedActivitySelection = selection
    }

    private func normalizeDomain(_ input: String) -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        value = value.replacingOccurrences(of: "https://", with: "")
        value = value.replacingOccurrences(of: "http://", with: "")
        value = value.replacingOccurrences(of: "www.", with: "")

        if let slashIndex = value.firstIndex(of: "/") {
            value = String(value[..<slashIndex])
        }

        while value.hasSuffix(".") {
            value.removeLast()
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")
        let filteredScalars = value.unicodeScalars.filter { allowed.contains($0) }
        value = String(String.UnicodeScalarView(filteredScalars))

        if value.isEmpty || !value.contains(".") {
            return ""
        }

        return value
    }
}
