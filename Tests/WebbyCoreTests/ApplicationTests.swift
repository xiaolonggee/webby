import XCTest
@testable import WebbyCore
final class ApplicationTests: XCTestCase {
    func adapter(entries: String = "[]") throws -> AppAdapter {
        try AdapterCatalog.decode(Data("""
        {"version":1,"adapters":[{"id":"example","name":"Example","category":"AI / 模型","bundleIDs":["org.example.studio"],"processNames":["example-server"],"entries":\(entries),"note":"Example only","source":"https://example.com/docs"}]}
        """.utf8)).adapters[0]
    }
    func row(_ pid: Int = 1, _ port: Int = 8000, name: String = "example-server") -> Listener { Listener(pid: pid, name: name, uid: 501, host: "::1", port: port) }
    func testAPIEndpointIsNeverPromotedToManagement() throws {
        let rule = try adapter(entries: "[{\"kind\":\"api\",\"port\":8000,\"path\":\"/v1\"}]")
        let app = ApplicationResolver.resolve(listeners: [row()], identities: [:], adapters: [rule], verifiedPages: ["http://[::1]:8000"], uid: 501)[0]
        XCTAssertNil(app.managementURL); XCTAssertNil(app.applicationURL)
        XCTAssertEqual(app.apiEndpoints, ["http://[::1]:8000/v1"])
        XCTAssertTrue(app.apiOnly); XCTAssertFalse(app.onHome)
        XCTAssertEqual(app.category, .ai)
    }
    func testManagementRequiresIdentityAndPageEvidence() throws {
        let rule = try adapter(entries: "[{\"kind\":\"management\",\"port\":8000,\"path\":\"/#settings\",\"titleMarker\":\"Example Studio\"}]")
        let unverified = ApplicationResolver.resolve(listeners: [row()], identities: [:], adapters: [rule], uid: 501)[0]
        XCTAssertNil(unverified.managementURL); XCTAssertFalse(unverified.onHome)
        let verified = ApplicationResolver.resolve(listeners: [row()], identities: [:], adapters: [rule], verifiedPages: ["http://[::1]:8000"], uid: 501)[0]
        XCTAssertEqual(verified.managementURL, "http://[::1]:8000/#settings"); XCTAssertTrue(verified.onHome)
        let other = ApplicationResolver.resolve(listeners: [row(name: "unrelated")], identities: [:], adapters: [rule], verifiedPages: ["http://[::1]:8000"], uid: 501)[0]
        XCTAssertNil(other.managementURL)
    }
    func testBundleChildProcessesAndMultiplePortsBecomeOneApplication() throws {
        let identities = [1: ProcessIdentity(pid: 1, bundleID: "org.example.studio", bundleName: "Example", appPath: "/Applications/Example.app"), 2: ProcessIdentity(pid: 2, bundleID: "org.example.studio", bundleName: "Example", appPath: "/Applications/Example.app")]
        let apps = ApplicationResolver.resolve(listeners: [row(1, 8000, name: "main"), row(2, 8001, name: "helper"), row(2, 8002, name: "helper")], identities: identities, adapters: [try adapter()], uid: 501)
        XCTAssertEqual(apps.count, 1); XCTAssertEqual(apps[0].listeners.count, 3)
        XCTAssertEqual(apps[0].appPath, "/Applications/Example.app")
        XCTAssertNil(apps[0].managementURL)
    }
    func testUnknownMultiportProcessIsOneDiagnosticCandidate() {
        let apps = ApplicationResolver.resolve(listeners: [row(1, 8000, name: "node"), row(1, 8001, name: "node"), row(2, 9000, name: "node")], identities: [:], adapters: [], uid: 501)
        XCTAssertEqual(apps.count, 2)
        XCTAssertTrue(apps.allSatisfy { !$0.onHome && !$0.recognized })
        XCTAssertEqual(apps.map { $0.listeners.count }.sorted(), [1, 2])
    }
    func testGenericRuntimePortReuseDoesNotInheritAnotherProjectsPreferences() {
        let one = [1: ProcessIdentity(pid: 1, executable: "/usr/bin/example-runtime", workingDirectory: "/tmp/example-project-a")]
        let two = [2: ProcessIdentity(pid: 2, executable: "/usr/bin/example-runtime", workingDirectory: "/tmp/example-project-b")]
        let first = ApplicationResolver.resolve(listeners: [row(1, name: "node")], identities: one, adapters: [], uid: 501)[0]
        var preferences = AppPreferences()
        preferences.applications[first.id] = AppPreference(managementURL: "http://localhost:8000/settings")
        let second = ApplicationResolver.resolve(listeners: [row(2, name: "node")], identities: two, adapters: [], preferences: preferences, uid: 501)[0]
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNil(second.managementURL)
    }
    func testPythonInterpreterBundleDoesNotMergeIndependentServices() {
        let identities = [1: ProcessIdentity(pid: 1, executable: "/example/Python.app/Contents/MacOS/Python", bundleID: "org.python.python", bundleName: "Python", appPath: "/example/Python.app", workingDirectory: "/tmp/example-a"), 2: ProcessIdentity(pid: 2, executable: "/example/Python.app/Contents/MacOS/Python", bundleID: "org.python.python", bundleName: "Python", appPath: "/example/Python.app", workingDirectory: "/tmp/example-b")]
        let result = ApplicationResolver.resolve(listeners: [row(1, 8000, name: "Python"), row(2, 9000, name: "Python")], identities: identities, adapters: [], uid: 501)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { $0.appPath == nil && !$0.onHome })
    }
    func testPreferencesRoundtripCategoryFavoriteAndHide() throws {
        let rule = try adapter()
        var preferences = AppPreferences()
        preferences.applications["adapter:example"] = AppPreference(favorite: true, hidden: true, category: .data)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("preferences.local.json")
        try preferences.save(to: file)
        let restored = try AppPreferences.decode(Data(contentsOf: file))
        var app = ApplicationResolver.resolve(listeners: [row()], identities: [:], adapters: [rule], preferences: restored, uid: 501)[0]
        XCTAssertTrue(app.hidden); XCTAssertTrue(app.favorite); XCTAssertFalse(app.onHome); XCTAssertEqual(app.category, .data)
        preferences.applications["adapter:example"]?.hidden = false
        app = ApplicationResolver.resolve(listeners: [row()], identities: [:], adapters: [rule], preferences: preferences, uid: 501)[0]
        XCTAssertTrue(app.onHome)
    }
    func testUserAPIOverrideDoesNotBecomeWebPage() throws {
        var prefs = AppPreferences()
        prefs.applications["adapter:example"] = AppPreference(apiEndpoint: "http://localhost:8000/v1")
        let app = ApplicationResolver.resolve(listeners: [row()], identities: [:], adapters: [try adapter()], preferences: prefs, uid: 501)[0]
        XCTAssertTrue(app.apiOnly); XCTAssertFalse(app.onHome); XCTAssertNil(app.managementURL)
    }
    func testRejectCredentialURLsAndUnsafeRuleDefinitions() throws {
        XCTAssertThrowsError(try AppPreference(managementURL: "http://user:pass@localhost/").validate())
        XCTAssertThrowsError(try AppPreference(apiEndpoint: "http://localhost/?token=example").validate())
        XCTAssertThrowsError(try adapter(entries: "[{\"kind\":\"management\",\"port\":8000,\"path\":\"/\"}]"))
        XCTAssertThrowsError(try AppPreferences.decode(Data("{\"version\":2,\"applications\":{}}".utf8)))
    }
}
