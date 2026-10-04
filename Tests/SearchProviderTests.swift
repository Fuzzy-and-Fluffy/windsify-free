import XCTest
@testable import WindsifyMac

final class SearchProviderTests: XCTestCase {
    func testDefaultAndInvalidStoredValuesResolveToSpotlight() {
        for stored: String? in [nil, "", "unknown", "Raycast"] {
            XCTAssertEqual(SearchProvider.resolve(stored), .spotlight)
        }
        XCTAssertEqual(SearchProvider.resolve("raycast"), .raycast)
    }

    func testChoicePersistsAndRestoresThroughInjectedStorage() {
        var stored: String?
        let store = SearchProviderStore(read: { stored }, write: { stored = $0 })
        XCTAssertEqual(store.selection, .spotlight)
        store.select(.raycast)
        XCTAssertEqual(stored, "raycast")
        XCTAssertEqual(SearchProviderStore(read: { stored }, write: { stored = $0 }).selection, .raycast)
        store.select(.spotlight)
        XCTAssertEqual(stored, "spotlight")
    }

    func testSelectedProviderUsesOnlyItsRouteAndReportsRequestOnly() {
        var spotlightRequests = 0
        var raycastLookups = 0
        var raycastRequests = 0
        var outcomes: [SearchActivationPolicy.Outcome] = []
        let url = URL(fileURLWithPath: "/Applications/Raycast.app")
        let policy = SearchActivationPolicy(spotlight: {
            spotlightRequests += 1; return .actionRequested
        }, findRaycast: {
            raycastLookups += 1; return url
        }, launchRaycast: { actual, complete in
            XCTAssertEqual(actual, url)
            raycastRequests += 1; complete(true)
        }, reportFailure: { _ in XCTFail("Successful request must not report failure") })
        policy.activate(.spotlight) { outcomes.append($0) }
        XCTAssertEqual(spotlightRequests, 1)
        XCTAssertEqual(raycastLookups, 0)
        policy.activate(.raycast) { outcomes.append($0) }
        XCTAssertEqual(spotlightRequests, 1)
        XCTAssertEqual(raycastLookups, 1)
        XCTAssertEqual(raycastRequests, 1)
        policy.activate(.spotlight) { outcomes.append($0) }
        XCTAssertEqual(outcomes, [.spotlight(.actionRequested), .raycastActivationRequested,
                                  .spotlight(.actionRequested)])
    }

    func testMissingRaycastNeverFallsBackOrLaunchesAndReportsOnce() {
        var failures: [SearchActivationPolicy.Failure] = []
        var outcomes: [SearchActivationPolicy.Outcome] = []
        let policy = SearchActivationPolicy(spotlight: {
            XCTFail("Missing Raycast must not silently fall back"); return .actionRequested
        }, findRaycast: { nil }, launchRaycast: { _, _ in
            XCTFail("Missing Raycast must not launch")
        }, reportFailure: { failures.append($0) })
        for _ in 0..<3 { policy.activate(.raycast) { outcomes.append($0) } }
        XCTAssertEqual(outcomes, [.raycastUnavailable, .raycastUnavailable, .raycastUnavailable])
        XCTAssertEqual(failures, [.raycastUnavailable])
    }

    func testDeclinedRaycastReportsOnceUntilARequestSucceeds() {
        var accepted = false
        var failures: [SearchActivationPolicy.Failure] = []
        var outcomes: [SearchActivationPolicy.Outcome] = []
        let policy = SearchActivationPolicy(spotlight: {
            XCTFail("Declined Raycast must not fall back"); return .actionRequested
        }, findRaycast: { URL(fileURLWithPath: "/Applications/Raycast.app") },
        launchRaycast: { _, complete in complete(accepted) }, reportFailure: { failures.append($0) })
        for _ in 0..<2 { policy.activate(.raycast) { outcomes.append($0) } }
        XCTAssertEqual(failures, [.raycastActivationDeclined])
        accepted = true
        policy.activate(.raycast) { outcomes.append($0) }
        accepted = false
        policy.activate(.raycast) { outcomes.append($0) }
        XCTAssertEqual(failures, [.raycastActivationDeclined, .raycastActivationDeclined])
        XCTAssertEqual(outcomes, [.raycastActivationDeclined, .raycastActivationDeclined,
                                  .raycastActivationRequested, .raycastActivationDeclined])
    }

    func testRealSearchAdapterAndDefaultStoreRefuseHostedSystemAccess() {
        XCTAssertTrue(InputRuntimeSafety.isTestHost)
        SystemSearchActivation.activate()
        var routes = 0
        SystemSearchActivation.activate(route: { routes += 1 })
        XCTAssertEqual(routes, 0)
        // Default store's read/write closures guard standard defaults in a host.
        let store = SearchProviderStore()
        XCTAssertEqual(store.selection, .spotlight)
        store.select(.raycast)
        XCTAssertEqual(SearchProviderStore().selection, .spotlight)
    }
}
