import XCTest
@testable import WebbyCore
final class CoreTests: XCTestCase {
    func config(_ services: String = "[]", extra: String = "") throws -> Configuration {
        try Configuration.decode(Data("{\"version\":1,\"ignoredProcesses\":[],\"ignoredPorts\":[],\"services\":\(services)\(extra)}".utf8))
    }
    func testIPv4IPv6WildcardMultiportAndDedup() {
        let text = "p42\ncnode\nu501\nf1\nn127.0.0.1:3000\nf2\nn[::1]:3000\nf3\nn*:4000\nn*:4000\nninvalid\nnlocalhost:70000"
        let rows = DiscoveryParser.parse(text)
        XCTAssertEqual(rows.count, 3); XCTAssertEqual(Set(rows.map(\.port)), [3000, 4000]); XCTAssertTrue(rows.contains { $0.host == "::1" })
    }
    func testMissingUIDAndBrokenPIDDoNotLeakPreviousRecord() {
        let rows = DiscoveryParser.parse("p2\ncnode\nu501\nn*:80\np3\ncother\nn*:90\npbad\nn*:91")
        XCTAssertEqual(ServiceMerger.merge(rows, config: .empty, currentUID: 501).count, 1)
    }
    func testSystemAndOtherUserFiltered() {
        let rows = [Listener(pid: 1, name: "launchd", uid: 501, host: "*", port: 80), Listener(pid: 2, name: "node", uid: 0, host: "*", port: 81), Listener(pid: 3, name: "node", uid: 501, host: "::", port: 3000)]
        let merged = ServiceMerger.merge(rows, config: .empty, currentUID: 501)
        XCTAssertEqual(merged.count, 1); XCTAssertNil(merged[0].url); XCTAssertNil(merged[0].config)
    }
    func testOverrideRequiresProcessAndPort() throws {
        let c = try config("[{\"id\":\"web\",\"name\":\"Website\",\"process\":\"node\",\"port\":3000,\"url\":\"http://localhost:3000/docs\"}]")
        let rows = [Listener(pid: 2, name: "python", uid: 501, host: "*", port: 3000)]
        let merged = ServiceMerger.merge(rows, config: c, currentUID: 501)
        XCTAssertEqual(merged.count, 2); XCTAssertFalse(merged.first { $0.config != nil }!.isListening)
        XCTAssertNil(merged.first { $0.config == nil }!.url)
    }
    func testExitAndPortReuseReplaceSnapshot() {
        let a = ServiceMerger.merge([Listener(pid: 2, name: "node", uid: 501, host: "*", port: 3000)], config: .empty, currentUID: 501)
        XCTAssertEqual(ServiceMerger.merge([], config: .empty, currentUID: 501).count, 0)
        let b = ServiceMerger.merge([Listener(pid: 3, name: "python", uid: 501, host: "*", port: 3000)], config: .empty, currentUID: 501)
        XCTAssertNotEqual(a[0].id, b[0].id)
    }
    func testIgnoreWinsOverConfiguration() throws {
        let data = Data("{\"version\":1,\"ignoredProcesses\":[],\"ignoredPorts\":[3000],\"services\":[{\"id\":\"a\",\"name\":\"A\",\"process\":\"node\",\"port\":3000}]}".utf8)
        let rows = [Listener(pid: 2, name: "node", uid: 501, host: "*", port: 3000)]
        XCTAssertTrue(ServiceMerger.merge(rows, config: try Configuration.decode(data), currentUID: 501).isEmpty)
    }
    func testInvalidConfigurations() throws {
        for url in ["file:///tmp/test", "http://user:pass@localhost/", "http://localhost/?token=example", "http://localhost/#example"] {
            XCTAssertThrowsError(try config("[{\"id\":\"a\",\"name\":\"A\",\"process\":\"node\",\"port\":3000,\"url\":\"\(url)\"}]"))
        }
        XCTAssertThrowsError(try Configuration.decode(Data("{\"version\":2,\"ignoredProcesses\":[],\"ignoredPorts\":[],\"services\":[]}".utf8)))
        XCTAssertThrowsError(try config("[{\"id\":\"a\",\"name\":\"A\",\"process\":\"node\",\"port\":0}]"))
        let item = "{\"id\":\"a\",\"name\":\"A\",\"process\":\"node\",\"port\":3000}"
        XCTAssertThrowsError(try config("[\(item),\(item)]"))
    }
    func testBundledAppsPythonMLXAndCustomNamesNeedNoAllowlist() {
        let names = ["Example Desktop", "Python", "python3.13", "mlx-serve", "custom-worker"]
        let records = names.enumerated().map { Listener(pid: $0.offset + 20, name: $0.element, uid: 501, host: "::", port: 4000 + $0.offset) }
        let services = ServiceMerger.merge(records, config: .empty, currentUID: 501)
        XCTAssertEqual(Set(services.map(\.name)), Set(names))
        XCTAssertTrue(services.allSatisfy { $0.config == nil && $0.url == nil && $0.isListening })
    }
    func testMaskDoesNotExposeContentOrLength() {
        XCTAssertEqual(SecretMask.display("example-only", revealed: false), "••••••••")
        XCTAssertEqual(SecretMask.display("x", revealed: false), SecretMask.display(nil, revealed: false))
        XCTAssertEqual(SecretMask.display("example-only", revealed: true), "example-only")
    }
}
