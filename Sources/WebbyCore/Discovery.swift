import Foundation
import Darwin

public struct Snapshot: Sendable { public var listeners: [Listener]; public var directories: [Int: String]; public var identities: [Int: ProcessIdentity] }
public enum LocalDiscovery {
    public static func scan() throws -> Snapshot {
        let text = try run(["+c", "0", "-nP", "-a", "-u", String(getuid()), "-iTCP", "-sTCP:LISTEN", "-Fpcun"])
        var identities: [Int: ProcessIdentity] = [:]
        let listeners = DiscoveryParser.parse(text).filter { listener in
            var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let count = proc_pidpath(Int32(listener.pid), &buffer, UInt32(buffer.count))
            guard count > 0 else { return kill(Int32(listener.pid), 0) == 0 || errno == EPERM } // Keep live unknown candidates; drop exited processes.
            let path = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            var identity = ProcessIdentity(pid: listener.pid, executable: path)
            // Outermost bundle folds Electron helpers and other child executables into the parent app.
            if let range = path.range(of: ".app/") {
                let appPath = String(path[..<range.upperBound].dropLast())
                if let bundle = Bundle(path: appPath) {
                    identity.bundleID = bundle.bundleIdentifier
                    identity.bundleName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    identity.appPath = appPath
                }
            }
            identities[listener.pid] = identity
            return !path.hasPrefix("/System/") && !path.hasPrefix("/usr/libexec/") && !path.hasPrefix("/usr/sbin/")
        }
        // Read only cwd descriptors for matched processes; never arguments or environment.
        var directories: [Int: String] = [:]
        let pids = Set(listeners.map(\.pid))
        if !pids.isEmpty, let cwd = try? run(["-a", "-p", pids.sorted().map(String.init).joined(separator: ","), "-d", "cwd", "-Fpn"]) {
            var pid = 0
            for line in cwd.split(separator: "\n") {
                if line.first == "p" { pid = Int(line.dropFirst()) ?? 0 }
                if line.first == "n", pids.contains(pid) { directories[pid] = String(line.dropFirst()) }
            }
        }
        for (pid, directory) in directories { identities[pid]?.workingDirectory = directory }
        return Snapshot(listeners: listeners, directories: directories, identities: identities)
    }
    private static func run(_ arguments: [String]) throws -> String {
        let process = Process(), output = Pipe(), errors = Pipe()
        let errorData = ReadBuffer()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = arguments; process.standardOutput = output; process.standardError = errors
        try process.run()
        // Drain pipes concurrently to avoid a pipe-buffer deadlock. lsof has a bounded timeout.
        let group = DispatchGroup(); group.enter()
        DispatchQueue.global().async { errorData.data = errors.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: watchdog)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit(); watchdog.cancel(); group.wait()
        guard process.terminationReason == .exit, process.terminationStatus == 0 || (process.terminationStatus == 1 && data.isEmpty && errorData.data.isEmpty) else { throw ConfigError.invalid("服务检测失败，请刷新重试。未申请额外权限。") }
        return String(decoding: data, as: UTF8.self)
    }
}

// Written by one pipe reader, read only after DispatchGroup completion.
private final class ReadBuffer: @unchecked Sendable { var data = Data() }
