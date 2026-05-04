import Foundation
import Combine

#if os(iOS) && canImport(FamilyControls) && canImport(ManagedSettings)
import FamilyControls
import ManagedSettings

@MainActor
final class ScreenTimeService: ObservableObject {
    private let store = ManagedSettingsStore()

    func requestAuthorization() async -> Bool {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            return false
        }

        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved, .approvedWithDataAccess:
            return true
        default:
            return false
        }
    }

    @discardableResult
    func revokeAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            let lock = NSLock()
            var didResume = false

            func resumeOnce(_ value: Bool) {
                lock.lock()
                defer { lock.unlock() }

                guard !didResume else {
                    return
                }

                didResume = true
                continuation.resume(returning: value)
            }

            AuthorizationCenter.shared.revokeAuthorization { result in
                switch result {
                case .success:
                    resumeOnce(true)
                case .failure:
                    resumeOnce(false)
                }
            }
        }
    }

    func setDeletingAppsDisabled(_ disabled: Bool) {
        store.application.denyAppRemoval = disabled ? true : nil
    }

    func clearRestrictions() {
        store.application.denyAppRemoval = nil
        store.application.blockedApplications = nil
        store.webContent.blockedByFilter = nil
        store.shield.applications = nil
        store.shield.webDomains = nil
    }

    func resetAuthorizationInBackground() {
        AuthorizationCenter.shared.revokeAuthorization { _ in }
    }

    func apply(_ model: BlockerDomainModel) {
        setDeletingAppsDisabled(model.permissions.isDeletingAppsDisabled)
        store.shield.applications = nil
        store.shield.webDomains = nil

        guard model.permissions.hasScreenTimeAccess else {
            store.application.blockedApplications = nil
            store.webContent.blockedByFilter = nil
            return
        }

        let plan = model.restrictionPlan
        let applications = Set(plan.appBundleIdentifiers.map { Application(bundleIdentifier: $0) })
        store.application.blockedApplications = applications.isEmpty ? nil : applications

        let domains = Set(plan.webDomains.map { WebDomain(domain: $0) })
        store.webContent.blockedByFilter = domains.isEmpty ? nil : .specific(domains)
    }
}
#else
@MainActor
final class ScreenTimeService: ObservableObject {
    func requestAuthorization() async -> Bool {
        true
    }

    func revokeAuthorization() async -> Bool {
        true
    }

    func setDeletingAppsDisabled(_ disabled: Bool) {}

    func clearRestrictions() {}

    func resetAuthorizationInBackground() {}

    func apply(_ model: BlockerDomainModel) {}
}
#endif
