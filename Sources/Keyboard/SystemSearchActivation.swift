import AppKit

/// Dependency-only routing policy; tests supply fake lookup and activation.
final class SearchActivationPolicy {
    enum Outcome: Equatable {
        case spotlight(SystemSpotlightActivation.Outcome)
        case raycastActivationRequested
        case raycastUnavailable
        case raycastActivationDeclined
    }
    enum Failure: Equatable { case raycastUnavailable, raycastActivationDeclined }

    private let spotlight: () -> SystemSpotlightActivation.Outcome
    private let findRaycast: () -> URL?
    private let launchRaycast: (URL, @escaping (Bool) -> Void) -> Void
    private let reportFailure: (Failure) -> Void
    private var failureWasReported = false

    init(spotlight: @escaping () -> SystemSpotlightActivation.Outcome,
         findRaycast: @escaping () -> URL?,
         launchRaycast: @escaping (URL, @escaping (Bool) -> Void) -> Void,
         reportFailure: @escaping (Failure) -> Void) {
        self.spotlight = spotlight
        self.findRaycast = findRaycast
        self.launchRaycast = launchRaycast
        self.reportFailure = reportFailure
    }

    func activate(_ provider: SearchProvider, completion: @escaping (Outcome) -> Void = { _ in }) {
        guard provider == .raycast else {
            failureWasReported = false
            completion(.spotlight(spotlight()))
            return
        }
        guard let url = findRaycast() else {
            reportOnce(.raycastUnavailable)
            completion(.raycastUnavailable)
            return
        }
        launchRaycast(url) { [self] accepted in
            if accepted {
                failureWasReported = false
                // Public app activation completion does not prove Root Search visibility.
                completion(.raycastActivationRequested)
            } else {
                reportOnce(.raycastActivationDeclined)
                completion(.raycastActivationDeclined)
            }
        }
    }

    private func reportOnce(_ failure: Failure) {
        guard !failureWasReported else { return }
        failureWasReported = true
        reportFailure(failure)
    }
}

enum SystemSearchActivation {
    static let raycastBundleIdentifier = "com.raycast.macos"
    private static let policy = SearchActivationPolicy(
        spotlight: { SystemSpotlightActivation.shared.activate() },
        findRaycast: verifiedRaycastURL,
        launchRaycast: launchRaycast,
        reportFailure: showFailure
    )

    /// Both bare Windows and Pro Win+S reach this one production entry point.
    static func activate(route: () -> Void = activateSelectedProvider) {
        // Hard guard cannot be replaced by an injected policy in hosted tests.
        guard !InputRuntimeSafety.isTestHost else { return }
        route()
    }

    private static func activateSelectedProvider() {
        policy.activate(SearchProviderStore.shared.selection)
    }

    private static func verifiedRaycastURL() -> URL? {
        guard !InputRuntimeSafety.isTestHost,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: raycastBundleIdentifier),
              Bundle(url: url)?.bundleIdentifier == raycastBundleIdentifier else { return nil }
        return url
    }

    private static func launchRaycast(at url: URL, completion: @escaping (Bool) -> Void) {
        guard !InputRuntimeSafety.isTestHost,
              Bundle(url: url)?.bundleIdentifier == raycastBundleIdentifier else {
            completion(false)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            DispatchQueue.main.async {
                guard !InputRuntimeSafety.isTestHost else { return }
                completion(error == nil && app?.bundleIdentifier == raycastBundleIdentifier)
            }
        }
    }

    private static func showFailure(_ failure: SearchActivationPolicy.Failure) {
        guard !InputRuntimeSafety.isTestHost else { return }
        let alert = NSAlert()
        alert.messageText = L10n.text("Raycast could not open")
        switch failure {
        case .raycastUnavailable:
            alert.informativeText = L10n.text("Raycast is not installed or its app identity could not be verified. Install Raycast from raycast.com, or choose Spotlight in Windsify settings, then try again.")
        case .raycastActivationDeclined:
            alert.informativeText = L10n.text("Raycast could not be activated. Open Raycast from Applications and try again, or choose Spotlight in Windsify settings.")
        }
        alert.addButton(withTitle: L10n.text("OK"))
        alert.runModal()
    }
}
