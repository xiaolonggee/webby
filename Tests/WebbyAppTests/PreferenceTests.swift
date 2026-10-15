import XCTest
@testable import Webby
import WebbyCore

@MainActor final class PreferenceTests: XCTestCase {
    func testFavoriteHideRestoreAndCategoryFilterUseActualStore() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = Store(arguments: ["Webby", "--demo"], configURL: folder.appendingPathComponent("config.json"))
        await store.refresh()
        let app = try XCTUnwrap(store.applications.first { $0.legacyConfig?.id == "web" })
        store.updatePreference(app.id) { $0.favorite = true; $0.category = .development }
        store.scope = "已关注"
        XCTAssertTrue(store.visibleApps.contains { $0.id == app.id })
        store.updatePreference(app.id) { $0.hidden = true }
        XCTAssertFalse(store.visibleApps.contains { $0.id == app.id })
        store.scope = "已隐藏"
        XCTAssertTrue(store.visibleApps.contains { $0.id == app.id })
        store.updatePreference(app.id) { $0.hidden = false }
        store.scope = AppCategory.development.rawValue
        XCTAssertTrue(store.visibleApps.contains { $0.id == app.id })
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.preferencesURL.path), "Demo edits must never write user preferences")
    }
    func testPreferencesLoadAndPersistOnlyUserChanges() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let config = folder.appendingPathComponent("config.json")
        let first = Store(arguments: ["Webby"], configURL: config)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.preferencesURL.path))
        first.updatePreference("adapter:example") { $0.favorite = true; $0.hidden = true; $0.category = .data }
        let second = Store(arguments: ["Webby"], configURL: config)
        XCTAssertTrue(second.preferences.applications["adapter:example"]?.hidden == true)
        XCTAssertTrue(second.preferences.applications["adapter:example"]?.favorite == true)
        XCTAssertEqual(second.preferences.applications["adapter:example"]?.category, .data)
        XCTAssertFalse(second.demo)
    }
    func testMalformedPreferencesAreNotOverwritten() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("preferences.local.json"), original = Data("invalid synthetic fixture".utf8)
        try original.write(to: file)
        let store = Store(arguments: ["Webby"], configURL: folder.appendingPathComponent("config.json"))
        XCTAssertFalse(store.preferencesWritable)
        store.updatePreference("adapter:example") { $0.hidden = true }
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
}
