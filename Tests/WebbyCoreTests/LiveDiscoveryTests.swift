import XCTest
import Darwin
@testable import WebbyCore
final class LiveDiscoveryTests: XCTestCase {
    func testZeroConfigListenerAppearsAndDisappears() throws {
        // Only a new socket owned by this test is created and closed. No existing service is touched.
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw XCTSkip("无法创建测试 socket") }
        var closed = false
        defer { if !closed { close(fd) } }
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET); address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { ptr in ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound == 0, listen(fd, 1) == 0 else { throw XCTSkip("沙箱不允许本地监听测试") }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) { ptr in ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
        let port = Int(UInt16(bigEndian: address.sin_port)), pid = Int(getpid())
        let before = try LocalDiscovery.scan()
        let appeared = ServiceMerger.merge(before.listeners, config: .empty, currentUID: Int(getuid()))
        XCTAssertTrue(appeared.contains { $0.listeners.contains { $0.pid == pid && $0.port == port } }, "新建无配置监听应自动出现")
        close(fd); closed = true
        let after = try LocalDiscovery.scan()
        XCTAssertFalse(after.listeners.contains { $0.pid == pid && $0.port == port }, "退出后不得保留旧监听")
        print("Zero-configuration live discovery: appeared and disappeared; no service inventory logged.")
    }
}
