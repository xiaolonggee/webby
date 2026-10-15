import Foundation

public enum AppCategory: String, Codable, CaseIterable, Sendable {
    case ai = "AI / 模型", development = "开发工具", data = "数据服务", other = "其他"
}
public struct ProcessIdentity: Sendable {
    public var pid: Int
    public var executable: String?
    public var bundleID: String?
    public var bundleName: String?
    public var appPath: String?
    public var workingDirectory: String?
    public init(pid: Int, executable: String? = nil, bundleID: String? = nil, bundleName: String? = nil, appPath: String? = nil, workingDirectory: String? = nil) {
        self.pid = pid; self.executable = executable; self.bundleID = bundleID; self.bundleName = bundleName; self.appPath = appPath; self.workingDirectory = workingDirectory
    }
}
public struct EntryRule: Codable, Sendable {
    public var kind: String // management, application, api
    public var port: Int
    public var path: String
    public var titleMarker: String? // management/application require read-only HTML title verification
}
public struct AppAdapter: Codable, Sendable {
    public var id: String
    public var name: String
    public var category: AppCategory
    public var bundleIDs: [String]
    public var processNames: [String]
    public var entries: [EntryRule]
    public var settingsHint: String?
    public var note: String
    public var source: String
}
public struct AdapterCatalog: Codable, Sendable {
    public var version: Int
    public var adapters: [AppAdapter]
    public static func decode(_ data: Data) throws -> Self {
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.version == 1, Set(result.adapters.map(\.id)).count == result.adapters.count else { throw ConfigError.invalid("应用规则版本或 ID 无效") }
        for adapter in result.adapters {
            guard !adapter.id.isEmpty, !adapter.name.isEmpty, !adapter.source.isEmpty, !adapter.bundleIDs.isEmpty || !adapter.processNames.isEmpty else { throw ConfigError.invalid("应用规则缺少身份或来源") }
            for entry in adapter.entries {
                guard ["management", "application", "api"].contains(entry.kind), (1...65535).contains(entry.port), entry.path.hasPrefix("/"), !entry.path.contains("?"), !entry.path.hasPrefix("//"), !entry.path.contains("\n"), entry.kind == "api" || !(entry.titleMarker ?? "").isEmpty else { throw ConfigError.invalid("入口规则无效：网页必须提供验证标识") }
            }
        }
        return result
    }
}
public struct AppPreference: Codable, Sendable, Equatable {
    public var favorite = false
    public var hidden = false
    public var category: AppCategory?
    public var managementURL: String?
    public var applicationURL: String?
    public var apiEndpoint: String?
    public init(favorite: Bool = false, hidden: Bool = false, category: AppCategory? = nil, managementURL: String? = nil, applicationURL: String? = nil, apiEndpoint: String? = nil) {
        self.favorite = favorite; self.hidden = hidden; self.category = category; self.managementURL = managementURL; self.applicationURL = applicationURL; self.apiEndpoint = apiEndpoint
    }
    public func validate() throws {
        for value in [managementURL, applicationURL, apiEndpoint].compactMap({ $0 }) where !value.isEmpty {
            guard let url = URLComponents(string: value), ["http", "https"].contains(url.scheme), let host = url.host, !host.isEmpty, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil || ["settings", "chat", "models", "monitor"].contains(url.fragment!) else { throw ConfigError.invalid("入口须为 HTTP(S)，不含凭据或查询串；片段仅支持 settings/chat/models/monitor") }
        }
    }
}
public struct AppPreferences: Codable, Sendable {
    public var version = 1
    public var applications: [String: AppPreference] = [:]
    public init() {}
    public static func decode(_ data: Data) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.version == 1 else { throw ConfigError.invalid("偏好版本不受支持") }
        for preference in value.applications.values { try preference.validate() }
        return value
    }
    public func save(to url: URL) throws {
        for preference in applications.values { try preference.validate() }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
public struct AppRecord: Identifiable, Sendable {
    public var id: String
    public var name: String
    public var category: AppCategory
    public var listeners: [Listener]
    public var appPath: String?
    public var managementURL: String?
    public var applicationURL: String?
    public var apiEndpoints: [String]
    public var settingsHint: String?
    public var note: String
    public var source: String
    public var confidence: String
    public var recognized: Bool
    public var favorite: Bool
    public var hidden: Bool
    public var legacyConfig: ServiceConfig?
    public var hasEntry: Bool { managementURL != nil || applicationURL != nil || appPath != nil }
    public var apiOnly: Bool { !apiEndpoints.isEmpty && !hasEntry }
    public var onHome: Bool { !hidden && (favorite || (recognized && hasEntry)) }
    public var kindLabel: String {
        if managementURL != nil { return "Web 管理页" }
        if applicationURL != nil { return "Web 应用" }
        if appPath != nil { return "原生应用" }
        if !apiEndpoints.isEmpty { return "仅 API · 无已确认 Web 管理页" }
        return "入口待识别"
    }
}
public enum ApplicationResolver {
    // Use identity first, never infer a protocol or application from a port alone.
    public static func resolve(listeners: [Listener], identities: [Int: ProcessIdentity], adapters: [AppAdapter], verifiedPages: Set<String> = [], preferences: AppPreferences = .init(), config: Configuration = .empty, uid: Int) -> [AppRecord] {
        let visible = listeners.filter { $0.uid == uid && !ServiceMerger.systemProcesses.contains($0.name) && !config.ignoredProcesses.contains($0.name) && !config.ignoredPorts.contains($0.port) }
        func processIdentity(for row: Listener) -> ProcessIdentity? {
            guard let identity = identities[row.pid] else { return nil }
            // Python.app is an interpreter bundle, not the identity of every Python service it hosts.
            if identity.appPath?.hasSuffix("/Python.app") == true { return ProcessIdentity(pid: identity.pid, executable: identity.executable, workingDirectory: identity.workingDirectory) }
            return identity
        }
        func adapter(for row: Listener) -> AppAdapter? {
            if let bundle = processIdentity(for: row)?.bundleID, let exact = adapters.first(where: { $0.bundleIDs.contains(bundle) }) { return exact }
            return adapters.first { $0.processNames.contains(row.name) }
        }
        let portsByPID = Dictionary(grouping: visible, by: \.pid).mapValues { Array(Set($0.map(\.port))).sorted().map(String.init).joined(separator: ",") }
        func key(_ row: Listener) -> String {
            if let match = adapter(for: row) { return "adapter:\(match.id)" }
            if let bundle = processIdentity(for: row)?.bundleID { return "bundle:\(bundle)" }
            // Multiple independent generic runtimes must not merge merely because both are named node/Python.
            return "process:\(identities[row.pid]?.executable ?? row.name):\(identities[row.pid]?.workingDirectory ?? "pid-\(row.pid)"):\(portsByPID[row.pid] ?? String(row.port))"
        }
        let groups = Dictionary(grouping: visible, by: key)
        return groups.map { id, rows in
            let match = adapter(for: rows[0]), identity = rows.compactMap { processIdentity(for: $0) }.first { $0.appPath != nil }
            let preference = preferences.applications[id] ?? AppPreference()
            var management: String?, application: String?, api: [String] = []
            for rule in match?.entries ?? [] {
                guard let row = rows.first(where: { $0.port == rule.port }), let base = localBase(row) else { continue }
                let url = base + rule.path
                if rule.kind == "api" { api.append(url) }
                else if verifiedPages.contains(base) {
                    if rule.kind == "management" { management = url } else { application = url }
                }
            }
            // V1 generic `url` means an application link, never a management assertion.
            let legacy = config.services.first { item in rows.contains { $0.name == item.process && $0.port == item.port } }
            if let url = legacy?.url { application = url }
            if let value = preference.managementURL { management = value.isEmpty ? nil : value }
            if let value = preference.applicationURL { application = value.isEmpty ? nil : value }
            if let value = preference.apiEndpoint { api = value.isEmpty ? [] : [value] }
            let override = preference.managementURL != nil || preference.applicationURL != nil || preference.apiEndpoint != nil
            return AppRecord(id: id, name: legacy?.name ?? match?.name ?? identity?.bundleName ?? rows[0].name, category: preference.category ?? match?.category ?? .other, listeners: rows.sorted { ($0.pid, $0.port) < ($1.pid, $1.port) }, appPath: identity?.appPath, managementURL: management, applicationURL: application, apiEndpoints: Array(Set(api)).sorted(), settingsHint: match?.settingsHint, note: match?.note ?? "已发现应用或监听；尚无经过核实的管理入口。", source: override ? "用户入口覆盖；" + (match?.source ?? "本机应用包元数据") : (match?.source ?? (identity == nil ? "进程与 TCP 监听快照" : "本机应用包元数据")), confidence: override ? "用户指定" : (management != nil || application != nil ? "身份规则 + HTML 标识验证" : (match != nil ? "身份规则匹配" : "候选 / 待确认")), recognized: match != nil || legacy != nil || override, favorite: preference.favorite, hidden: preference.hidden, legacyConfig: legacy)
        }.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }
    public static func localBase(_ listener: Listener) -> String? {
        let host: String
        switch listener.host {
        case "*", "0.0.0.0", "127.0.0.1", "localhost": host = "127.0.0.1"
        case "::", "::1": host = "[::1]"
        default: return nil // Do not probe arbitrary LAN/remote addresses.
        }
        return "http://\(host):\(listener.port)"
    }
}
