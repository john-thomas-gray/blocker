import Combine
import SwiftUI

struct ContentView: View {
    @StateObject private var model = BlockerAppModel()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            switch model.domain.route {
            case .setup:
                SetupFlowView(model: model)
            case .main:
                MainView(model: model)
            case .unblockReview:
                MainView(model: model)
            }
        }
        .onAppear {
            model.refresh()
        }
        .onReceive(timer) { _ in
            model.refresh()
        }
        .sheet(item: $model.pendingSelection) { pending in
            ScopeSelectionView(model: model, pending: pending)
        }
    }
}

private struct SetupFlowView: View {
    @ObservedObject var model: BlockerAppModel
    @State private var showLockWarning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.domain.setup.current.title)
                    .font(.largeTitle.bold())
                Text(model.domain.setup.current.explanation)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            setupControl

            Spacer(minLength: 12)

            HStack(spacing: 12) {
                Button {
                    model.goBackSetupStep()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!model.domain.canGoBackInSetup)

                Button {
                    if model.domain.setup.current == .blockConfirmation {
                        showLockWarning = true
                    } else {
                        model.acceptSetupStep()
                    }
                } label: {
                    Label(model.domain.setup.current.buttonTitle, systemImage: model.domain.setup.current == .blockConfirmation ? "lock.fill" : "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.domain.canAdvanceSetup)
            }
        }
        .padding(20)
        .navigationTitle("Blocker")
        .alert("Lock Blocker?", isPresented: $showLockWarning) {
            Button("Cancel", role: .cancel) {}
            Button("Lock") {
                model.finishSetupAndBlock()
            }
        } message: {
            Text("Your active blocks are already applied. Locking Blocker prevents changes until the unlock timer finishes.")
        }
    }

    @ViewBuilder
    private var setupControl: some View {
        switch model.domain.setup.current {
        case .screenTimeAccess:
            Button {
                Task {
                    await model.requestScreenTimeAccess()
                }
            } label: {
                Label(model.domain.permissions.hasScreenTimeAccess ? "Access Granted" : "Request Access", systemImage: "hourglass")
            }
            .buttonStyle(.bordered)
        case .screenTimePassword:
            EmptyView()
        case .disableDeletingApps:
            Toggle("Deleting Apps: Don't Allow", isOn: Binding(
                get: { model.domain.permissions.isDeletingAppsDisabled },
                set: { model.setDeletingAppsDisabled($0) }
            ))
        case .chooseWhatToBlock:
            AddBlockInput(model: model)
            ActiveBlocksList(model: model)
        case .blockConfirmation:
            ActiveBlocksList(model: model)
        }
    }
}

private struct MainView: View {
    @ObservedObject var model: BlockerAppModel
    @State private var showLockWarning = false
    @State private var isShowingBlocks = true

    var body: some View {
        List {
            Section {
                Button {
                    if model.domain.isBlockingEnabled {
                        model.requestUnblock()
                    } else {
                        showLockWarning = true
                    }
                } label: {
                    Label(model.domain.isBlockingEnabled ? "Unlock" : "Lock", systemImage: model.domain.isBlockingEnabled ? "lock.open" : "lock")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.domain.isUnblockPending || !model.domain.hasActiveBlocks)

                if model.domain.isUnblockPending {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(model.countdownText)
                                .font(.title2.monospacedDigit())
                            Text("Unlock request pending")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            model.cancelUnblockRequest()
                        } label: {
                            Label("Cancel", systemImage: "xmark.circle")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                AddBlockInput(model: model)
            }
            .disabled(!model.domain.canEditBlocks)

            Section {
                DisclosureGroup(isExpanded: $isShowingBlocks) {
                    ActiveBlocksList(model: model)
                } label: {
                    Text("Active Blocks")
                        .font(.headline)
                }
            }

            Section {
                NavigationLink {
                    SettingsView(model: model)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .navigationTitle("Blocker")
        .alert("Lock Blocker?", isPresented: $showLockWarning) {
            Button("Cancel", role: .cancel) {}
            Button("Lock") {
                model.enableBlocking()
            }
        } message: {
            Text("Your active blocks are already applied. Locking Blocker prevents changes until the unlock timer finishes.")
        }
    }
}

private struct AddBlockInput: View {
    @ObservedObject var model: BlockerAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("App or website", text: $model.newBlockText)
                    .blockerTextField {
                        model.addTypedBlock()
                    }

                Button {
                    model.addTypedBlock()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .disabled(model.newBlockText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            let suggestions = model.domain.suggestions(matching: model.newBlockText)
            if !model.newBlockText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !suggestions.isEmpty {
                ForEach(suggestions.prefix(4)) { suggestion in
                    Button {
                        model.addBlock(named: suggestion.name)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.name)
                                Text(suggestion.domain)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "plus")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func blockerTextField(onSubmit: @escaping () -> Void) -> some View {
        #if os(iOS)
        self
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit(onSubmit)
        #else
        self
            .onSubmit(onSubmit)
        #endif
    }
}

private struct ActiveBlocksList: View {
    @ObservedObject var model: BlockerAppModel

    var body: some View {
        if model.domain.blocks.isEmpty {
            Text("No active blocks")
                .foregroundStyle(.secondary)
        } else {
            ForEach(model.domain.blocks) { item in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                        Text(item.domain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("App", isOn: Binding(
                        get: { item.blocksApp },
                        set: { model.setBlockScope(id: item.id, scope: .app, isBlocked: $0) }
                    ))
                    .labelsHidden()
                    .disabled(!model.domain.canEditBlocks || !item.canBlockApp)

                    Text("App")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Web", isOn: Binding(
                        get: { item.blocksWeb },
                        set: { model.setBlockScope(id: item.id, scope: .web, isBlocked: $0) }
                    ))
                    .labelsHidden()
                    .disabled(!model.domain.canEditBlocks)

                    Text("Web")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if item.canDelete {
                        Button(role: .destructive) {
                            model.deleteBlock(id: item.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .disabled(!model.domain.canEditBlocks)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct ScopeSelectionView: View {
    @ObservedObject var model: BlockerAppModel
    let pending: PendingBlockSelection
    @State private var blockApp = true
    @State private var blockWeb = true

    var body: some View {
        NavigationStack {
            Form {
                Section(pending.suggestion.name) {
                    Toggle("App", isOn: $blockApp)
                        .disabled(pending.suggestion.appBundleIdentifier == nil)
                    Toggle("Web", isOn: $blockWeb)
                }
            }
            .navigationTitle("Block")
            .onAppear {
                if pending.suggestion.appBundleIdentifier == nil {
                    blockApp = false
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.cancelPendingBlock()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        model.confirmPendingBlock(blockApp: blockApp, blockWeb: blockWeb)
                    }
                    .disabled(!blockApp && !blockWeb)
                }
            }
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var model: BlockerAppModel

    var body: some View {
        Form {
            Section("Blocking") {
                Toggle("App", isOn: Binding(
                    get: { model.domain.settings.blockAppsByDefault },
                    set: { model.setDefaultBlockScope(.app, isBlocked: $0) }
                ))
                .disabled(!model.domain.canEditBlocks)

                Toggle("Web", isOn: Binding(
                    get: { model.domain.settings.blockWebsitesByDefault },
                    set: { model.setDefaultBlockScope(.web, isBlocked: $0) }
                ))
                .disabled(!model.domain.canEditBlocks)
            }

            Section("Permissions") {
                Toggle("Screen Time Permissions", isOn: Binding(
                    get: { model.domain.permissions.hasScreenTimeAccess },
                    set: { enabled in
                        if enabled {
                            Task {
                                await model.requestScreenTimeAccess()
                            }
                        } else {
                            Task {
                                await model.revokeScreenTimeAccess()
                            }
                        }
                    }
                ))
                .disabled(!model.domain.canEditPermissions)

                Toggle("Deleting Apps", isOn: Binding(
                    get: { model.domain.permissions.isDeletingAppsDisabled },
                    set: { model.setDeletingAppsDisabled($0) }
                ))
                .disabled(!model.domain.canEditPermissions)
            }

#if DEBUG
            Section("Development") {
                Button(role: .destructive) {
                    model.resetForDevelopment()
                } label: {
                    Label("Reset Permissions and Setup", systemImage: "arrow.counterclockwise")
                }
            }
#endif
        }
        .navigationTitle("Settings")
    }
}
