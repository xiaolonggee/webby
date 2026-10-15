import XCTest
@testable import Webby

@MainActor final class StartupTests: XCTestCase {
    private func freshConfig() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("absent.json")
    }
    func testFreshLaunchWithoutPersonalConfigUsesRealDiscovery() async {
        let store = Store(arguments: ["Webby"], configURL: freshConfig())
        XCTAssertFalse(store.demo)
        await store.refresh()
        XCTAssertNil(store.error)
        XCTAssertNotNil(store.updated)
        XCTAssertTrue(store.configuration.services.isEmpty)
        XCTAssertTrue(store.services.allSatisfy { $0.config == nil })
    }
    func testNewInstanceAfterDemoDoesNotRememberDemo() async {
        let demo = Store(arguments: ["Webby", "--demo"], configURL: freshConfig())
        await demo.refresh()
        XCTAssertTrue(demo.demo)
        XCTAssertFalse(demo.services.isEmpty)
        let nextLaunch = Store(arguments: ["Webby"], configURL: freshConfig())
        XCTAssertFalse(nextLaunch.demo)
        await nextLaunch.refresh()
        XCTAssertNil(nextLaunch.error)
        XCTAssertTrue(nextLaunch.configuration.services.isEmpty)
        XCTAssertTrue(nextLaunch.services.allSatisfy { $0.config == nil })
    }
    func testDemoRequiresExactExplicitArgument() {
        for arguments in [["Webby"], ["--demo"], ["Webby", "--demo-dark"], ["Webby", "--demo=false"], ["Webby", "document.json"]] {
            XCTAssertFalse(Store(arguments: arguments, configURL: freshConfig()).demo)
        }
        XCTAssertTrue(Store(arguments: ["Webby", "--demo"], configURL: freshConfig()).demo)
    }
    func testLeavingDemoClearsSyntheticRowsBeforeLabelChanges() async {
        let store = Store(arguments: ["Webby", "--demo"], configURL: freshConfig())
        await store.refresh()
        XCTAssertFalse(store.services.isEmpty)
        store.leaveDemo()
        XCTAssertFalse(store.demo)
        XCTAssertTrue(store.services.isEmpty)
        XCTAssertTrue(store.configuration.services.isEmpty)
        XCTAssertNil(store.updated)
        XCTAssertNil(store.selected)
    }
}
