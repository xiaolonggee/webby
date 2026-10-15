import SwiftUI
import AppKit
import WebbyCore

@MainActor @Observable final class Store {
    var services: [Service] = []
    var directories: [Int: String] = [:]
    var selected: String?
    var search = ""
    var scope = "全部服务"
    var error: String?
    var busy = false
    var updated: Date?
    var configuration = Configuration.empty
    var demo = CommandLine.arguments.contains("--demo")
    var configURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Webby/config.json")
    var filtered: [Service] { services.filter { (scope == "全部服务" || (scope == "自动发现" ? $0.config == nil : $0.config != nil)) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.listeners.contains { String($0.port).contains(search) }) } }
    func refresh() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        var configWarning: String?
        do {
            if demo {
                configuration = try Configuration.decode(Data(Self.demoConfig.utf8))
                let samples = [Listener(pid: 1201, name: "node", uid: Int(getuid()), host: "127.0.0.1", port: 3000), Listener(pid: 1202, name: "postgres", uid: Int(getuid()), host: "::1", port: 5432), Listener(pid: 1203, name: "python", uid: Int(getuid()), host: "127.0.0.1", port: 8000)]
                services = ServiceMerger.merge(samples, config: configuration, currentUID: Int(getuid()))
            } else {
                var config = Configuration.empty
                if FileManager.default.fileExists(atPath: configURL.path) {
                    do { config = try Configuration.decode(Data(contentsOf: configURL)) }
                    catch { configWarning = "配置无效，已继续零配置自动发现。请检查配置格式与权限。" }
                }
                let snapshot = try await Task.detached { try LocalDiscovery.scan() }.value
                configuration = config; directories = snapshot.directories
                services = ServiceMerger.merge(snapshot.listeners, config: config, currentUID: Int(getuid()))
            }
            error = configWarning; updated = Date()
            if !services.contains(where: { $0.id == selected }) { selected = services.first?.id }
        } catch {
            // Do not present a stale observation as a current running state.
            services = []; directories = [:]; selected = nil
            self.error = (error as? ConfigError)?.localizedDescription ?? "配置读取失败。请检查 JSON 格式和文件权限；文件内容不会记录到日志。"
        }
    }
    func chooseConfig() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = "选择你主动创建的 Webby JSON 配置"
        if panel.runModal() == .OK, let url = panel.url { configURL = url; Task { await refresh() } }
    }
    static let demoConfig = """
    {"version":1,"ignoredProcesses":[],"ignoredPorts":[],"services":[{"id":"web","name":"工作台","process":"node","port":3000,"group":"开发环境","url":"http://localhost:3000/","directory":"~/Projects/example","configPath":"~/Projects/example/config.json","accountReference":"demo"},{"id":"db","name":"PostgreSQL","process":"postgres","port":5432,"group":"数据服务"},{"id":"docs","name":"文档站","process":"node","port":4321,"group":"开发环境","url":"http://localhost:4321/"}]}
    """
}
@main struct WebbyApp: App {
    @State private var store = Store()
    var body: some Scene {
        WindowGroup("Webby", id: "main") { MainView(store: store).preferredColorScheme(store.demo && CommandLine.arguments.contains("--demo-dark") ? .dark : nil).frame(minWidth: 900, minHeight: 570) }
            .defaultSize(width: 1100, height: 700)
            .commands { CommandGroup(after: .newItem) { Button("选择配置…") { store.chooseConfig() }.keyboardShortcut("o") } }
        MenuBarExtra("Webby", systemImage: "network") { MenuContent(store: store) }
    }
}
struct MenuContent: View {
    var store: Store
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("Webby · 服务织网")
        Text(store.error == nil ? "\(store.services.filter(\.isListening).count) 个服务在监听" : "检测失败")
        Button("打开 Webby") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button("刷新服务") { Task { await store.refresh() } }.disabled(store.busy)
        Divider()
        Button("退出 Webby") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
struct MainView: View {
    @Bindable var store: Store
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 24) {
                HStack { WebbySpider(); VStack(alignment: .leading) { Text("Webby").font(.title2.bold()); Text("服务织网").font(.caption).foregroundStyle(.secondary) } }.padding(.top, 16)
                VStack(spacing: 6) {
                    ForEach(["全部服务", "自动发现", "配置服务"], id: \.self) { scope in
                        Button { store.scope = scope } label: { HStack { Image(systemName: scope == "全部服务" ? "square.grid.2x2" : scope == "自动发现" ? "dot.radiowaves.left.and.right" : "slider.horizontal.3"); Text(scope); Spacer() }.padding(10).background(store.scope == scope ? Color.accentColor.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain)
                    }
                }
                Spacer()
                Label("只读 · 留在本机", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
                Button("选择配置…", systemImage: "doc.badge.gearshape") { store.chooseConfig() }
            }.padding(18).navigationSplitViewColumnWidth(210)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                HStack { VStack(alignment: .leading, spacing: 6) { Text(store.scope).font(.title2.bold()); Text(store.demo ? "演示数据 · 不扫描本机" : "监听快照，不代表业务健康").font(.caption).foregroundStyle(.secondary) }; Spacer(); if store.busy { ProgressView().controlSize(.small) } }.padding(20)
                if store.demo {
                    HStack { Label("演示模式 · 虚构服务", systemImage: "theatermasks"); Spacer(); Button("查看本机服务") { store.demo = false; store.selected = nil; Task { await store.refresh() } } }.font(.caption).padding(12).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 20)
                }
                WebTrail(destination: store.scope + " · " + (store.services.first { $0.id == store.selected }?.name ?? "服务节点"), listening: store.services.first { $0.id == store.selected }?.isListening ?? false).padding(.horizontal, 24).padding(.bottom, 12)
                if let error = store.error { Text(error).foregroundStyle(.orange).padding() }
                List(selection: $store.selected) {
                    ForEach(store.filtered) { service in
                        HStack(spacing: 12) {
                            Image(systemName: service.config == nil ? "antenna.radiowaves.left.and.right" : "server.rack").foregroundStyle(.teal).frame(width: 28)
                            VStack(alignment: .leading, spacing: 6) { Text(service.name).font(.headline); Text(service.config == nil ? "自动发现 · 协议未知" : "\(service.group) · 配置项").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) { Text(service.isListening ? "监听中" : "未发现").foregroundStyle(store.selected == service.id ? Color.white : (service.isListening ? Color.green : Color.secondary)); Text(service.listeners.isEmpty ? String(service.config?.port ?? 0) : Set(service.listeners.map(\.port)).sorted().map(String.init).joined(separator: ", ")).monospacedDigit().foregroundStyle(.secondary) }.font(.caption)
                        }.padding(.vertical, 9).modifier(DiscoveryGlow()).tag(service.id)
                    }
                }.overlay { if store.filtered.isEmpty && !store.busy { ContentUnavailableView("暂无服务", systemImage: "network", description: Text("启动开发服务或选择配置后刷新。")) } }
                HStack { Circle().fill(store.error == nil ? .teal : .orange).frame(width: 6, height: 6); Text(store.updated.map { "上次成功检测 \($0.formatted(date: .omitted, time: .standard))" } ?? "尚未检测"); Spacer(); Text("\(store.filtered.count) 项") }.font(.caption2).foregroundStyle(.secondary).padding(14)
            }.navigationSplitViewColumnWidth(min: 320, ideal: 390)
        } detail: {
            if let service = store.services.first(where: { $0.id == store.selected }) { DetailView(service: service, store: store).id(service.id) }
            else { ContentUnavailableView("你的本地服务，一目了然", systemImage: "network", description: Text("选择一个服务查看端口、进程和配置。")) }
        }
        .onChange(of: store.scope) { _, _ in store.selected = store.filtered.first?.id }
        .onChange(of: store.search) { _, _ in if !store.filtered.contains(where: { $0.id == store.selected }) { store.selected = store.filtered.first?.id } }
        .searchable(text: $store.search, prompt: "搜索服务或端口")
        .toolbar { Button { Task { await store.refresh() } } label: { Label("刷新", systemImage: "arrow.clockwise") }.keyboardShortcut("r").disabled(store.busy) }
        .task { await store.refresh(); while !Task.isCancelled { try? await Task.sleep(for: .seconds(10)); if Task.isCancelled { break }; await store.refresh() } }
    }
}
struct DetailView: View {
    let service: Service
    let store: Store
    @State private var account: String?
    @State private var revealed = false
    @State private var accountError: String?
    @Environment(\.scenePhase) private var phase
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "server.rack").font(.system(size: 32)).foregroundStyle(.teal).padding(16).background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 8) { Text(service.name).font(.largeTitle.bold()); Text(service.config == nil ? "自动发现" : "手工配置覆盖 · \(service.group)").foregroundStyle(.secondary) }
                Label(service.isListening ? "已观察到 TCP 监听" : "未观察到匹配监听", systemImage: service.isListening ? "circle.inset.filled" : "circle.dashed").foregroundStyle(service.isListening ? .green : .secondary)
                if let url = service.url { Button("在浏览器打开", systemImage: "arrow.up.right.square") { NSWorkspace.shared.open(url) }.buttonStyle(.borderedProminent); Text(url.absoluteString).font(.caption).textSelection(.enabled) }
                else { Text("协议未知，配置 HTTP(S) URL 后即可打开。").font(.callout).foregroundStyle(.secondary) }
                Divider()
                field("进程", service.listeners.map { "\($0.name) · PID \($0.pid)" }.uniqued().joined(separator: "\n"))
                field("监听地址", service.listeners.map { $0.host.contains(":") ? "[\($0.host)]:\($0.port)" : "\($0.host):\($0.port)" }.uniqued().joined(separator: "\n"))
                field("工作目录", service.config?.directory ?? service.listeners.first.flatMap { store.directories[$0.pid] })
                field("服务配置位置", service.config?.configPath)
                if !store.demo { field("Webby 配置", store.configURL.path) }
                if let reference = service.config?.accountReference {
                    Divider()
                    Text("账号信息").font(.headline)
                    Text(SecretMask.display(account, revealed: revealed)).textSelection(.disabled).font(.system(.body, design: .monospaced))
                    Button(revealed ? "隐藏" : "点击查看") {
                        if revealed { clear() } else {
                            do { account = store.demo ? "demo-account (示例)" : try KeychainAccounts().read(reference: reference); revealed = true; accountError = nil }
                            catch { accountError = error.localizedDescription }
                        }
                    }
                    if let accountError { Text(accountError).font(.caption).foregroundStyle(.secondary) }
                    Text("仅按明确引用读取 Webby 钥匙串项目；30 秒后自动隐藏。").font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(28)
        }.onDisappear { clear() }.onChange(of: service.config?.accountReference) { _, _ in clear() }.onChange(of: phase) { _, value in if value != .active { clear() } }
        .task(id: revealed) { if revealed { try? await Task.sleep(for: .seconds(30)); if !Task.isCancelled { clear() } } }
    }
    func clear() { revealed = false; account = nil }
    func field(_ title: String, _ value: String?) -> some View { VStack(alignment: .leading, spacing: 7) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value.flatMap { $0.isEmpty ? nil : $0 } ?? "未知 / 未配置").font(.callout).textSelection(.enabled) } }
}
extension Array where Element: Hashable { func uniqued() -> [Element] { var seen = Set<Element>(); return filter { seen.insert($0).inserted } } }
