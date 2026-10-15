import Foundation

public struct Listener: Hashable, Sendable {
    public var pid: Int
    public var name: String
    public var uid: Int
    public var host: String
    public var port: Int
    public init(pid: Int, name: String, uid: Int, host: String, port: Int) {
        self.pid = pid; self.name = name; self.uid = uid; self.host = host; self.port = port
    }
}
public enum DiscoveryParser {
    // lsof field output: process records followed by one or more file records.
    public static func parse(_ text: String) -> [Listener] {
        var pid = 0, uid = -1, name = "", result = Set<Listener>()
        for line in text.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p": pid = Int(value) ?? 0; uid = -1; name = ""
            case "u": uid = Int(value) ?? -1
            case "c": name = value
            case "n":
                guard pid > 0, let colon = value.lastIndex(of: ":"), let port = Int(value[value.index(after: colon)...]), (1...65535).contains(port) else { continue }
                let host = String(value[..<colon]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                result.insert(Listener(pid: pid, name: name, uid: uid, host: host, port: port))
            default: break
            }
        }
        return result.sorted { ($0.pid, $0.port, $0.host) < ($1.pid, $1.port, $1.host) }
    }
}
public struct ServiceConfig: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var process: String
    public var port: Int
    public var group: String?
    public var url: String?
    public var directory: String?
    public var configPath: String?
    public var accountReference: String?
}
public struct Configuration: Codable, Sendable {
    public var version: Int
    public var ignoredProcesses: [String]
    public var ignoredPorts: [Int]
    public var services: [ServiceConfig]
    public static let empty = Configuration(version: 1, ignoredProcesses: [], ignoredPorts: [], services: [])
    public static func decode(_ data: Data) throws -> Configuration {
        let config = try JSONDecoder().decode(Self.self, from: data)
        try config.validate(); return config
    }
    public func validate() throws {
        guard version == 1 else { throw ConfigError.invalid("仅支持配置版本 1") }
        guard Set(services.map(\.id)).count == services.count else { throw ConfigError.invalid("服务 ID 重复") }
        guard Set(services.map { "\($0.process):\($0.port)" }).count == services.count else { throw ConfigError.invalid("进程和端口匹配规则重复") }
        guard ignoredPorts.allSatisfy({ (1...65535).contains($0) }) else { throw ConfigError.invalid("忽略端口超出范围") }
        for service in services {
            guard !service.id.isEmpty, !service.name.isEmpty, !service.process.isEmpty, (1...65535).contains(service.port) else { throw ConfigError.invalid("服务名称、ID、进程或端口无效") }
            if let url = service.url {
                guard let parsed = URLComponents(string: url), ["http", "https"].contains(parsed.scheme), parsed.host != nil, parsed.user == nil, parsed.password == nil, parsed.query == nil, parsed.fragment == nil else { throw ConfigError.invalid("URL 必须为无凭据、无查询参数的 HTTP(S) 地址") }
            }
        }
    }
}
public enum ConfigError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}
public struct Service: Identifiable, Sendable {
    public var id: String
    public var name: String
    public var group: String
    public var listeners: [Listener]
    public var config: ServiceConfig?
    public var isListening: Bool { !listeners.isEmpty }
    public var url: URL? { config?.url.flatMap(URL.init(string:)) }
}
public enum ServiceMerger {
    public static let systemProcesses: Set<String> = ["ControlCenter", "rapportd", "sharingd", "AirPlayXPCHelper", "mDNSResponder", "launchd", "UserEventAgent", "systemstats"]
    public static func merge(_ listeners: [Listener], config: Configuration, currentUID: Int) -> [Service] {
        let visible = listeners.filter { $0.uid == currentUID && !systemProcesses.contains($0.name) && !config.ignoredProcesses.contains($0.name) && !config.ignoredPorts.contains($0.port) }
        var claimed = Set<Listener>(), result: [Service] = []
        for item in config.services where !config.ignoredProcesses.contains(item.process) && !config.ignoredPorts.contains(item.port) {
            let matches = visible.filter { $0.name == item.process && $0.port == item.port }
            claimed.formUnion(matches)
            result.append(Service(id: "config:\(item.id)", name: item.name, group: item.group ?? "已配置", listeners: matches, config: item))
        }
        let groups = Dictionary(grouping: visible.filter { !claimed.contains($0) }, by: \.pid)
        for (pid, rows) in groups {
            result.append(Service(id: "auto:\(pid):\(rows[0].name):\(rows.map(\.port).sorted())", name: rows[0].name, group: "自动发现", listeners: rows, config: nil))
        }
        return result.sorted { ($0.group, $0.name, $0.id) < ($1.group, $1.name, $1.id) }
    }
}
public enum SecretMask {
    public static func display(_ value: String?, revealed: Bool) -> String { revealed ? (value ?? "未配置") : "••••••••" }
}
