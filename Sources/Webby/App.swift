import SwiftUI
import AppKit
import WebbyCore

@MainActor @Observable final class Store {
    var services: [Service] = []
    var directories: [Int: String] = [:]
    var selected: String?
    var search = ""
    var scope = "我的应用"
    var applications: [AppRecord] = []
    var preferences = AppPreferences()
    var preferencesWritable = true
    var preferencesURL: URL
    var entryEditor: AppRecord?
    var adapters: [AppAdapter] = []
    private var lastListeners: [Listener] = []
    private var lastIdentities: [Int: ProcessIdentity] = [:]
    private var verifiedPages = Set<String>()
    var error: String?
    var busy = false
    var updated: Date?
    var configuration = Configuration.empty
    var demo = false
    init(arguments: [String] = CommandLine.arguments, configURL: URL? = nil) {
        let chosenConfig = configURL ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Webby/config.json")
        preferencesURL = chosenConfig.deletingLastPathComponent().appendingPathComponent("preferences.local.json")
        let ruleBundle = Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent("Webby_Webby.bundle")) } ?? Bundle.module
        if let url = ruleBundle.url(forResource: "adapters", withExtension: "json"), let data = try? Data(contentsOf: url) { adapters = (try? AdapterCatalog.decode(data).adapters) ?? [] }
        if !arguments.dropFirst().contains("--demo"), FileManager.default.fileExists(atPath: preferencesURL.path) {
            do { preferences = try AppPreferences.decode(Data(contentsOf: preferencesURL)) }
            catch { preferencesWritable = false; self.error = "偏好文件无效，已保留原文件。修复后重新启动即可编辑偏好。" }
        }
        demo = arguments.dropFirst().contains("--demo")
        if let configURL { self.configURL = configURL }
    }
    func leaveDemo() {
        // Never leave synthetic rows visible after removing their demo label.
        services = []; directories = [:]; selected = nil; updated = nil
        configuration = .empty; applications = []; preferences = .init(); error = nil; demo = false
        if let data = try? Data(contentsOf: preferencesURL) { do { preferences = try AppPreferences.decode(data) } catch { preferencesWritable = false } }
    }
    var configURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Webby/config.json")
    var filtered: [Service] { services.filter { (scope == "全部服务" || (scope == "自动发现" ? $0.config == nil : $0.config != nil)) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.listeners.contains { String($0.port).contains(search) }) } }
    var visibleApps: [AppRecord] {
        applications.filter { app in
            let matchesScope: Bool
            switch scope {
            case "我的应用": matchesScope = app.onHome
            case "已关注": matchesScope = app.favorite && !app.hidden
            case "已隐藏": matchesScope = app.hidden
            case "诊断候选": matchesScope = !app.recognized && !app.hidden
            default: matchesScope = app.category.rawValue == scope && !app.hidden
            }
            return matchesScope && (search.isEmpty || app.name.localizedCaseInsensitiveContains(search))
        }
    }
    func rebuildApplications() {
        applications = ApplicationResolver.resolve(listeners: lastListeners, identities: lastIdentities, adapters: adapters, verifiedPages: verifiedPages, preferences: preferences, config: configuration, uid: Int(getuid()))
        if !visibleApps.contains(where: { $0.id == selected }) { selected = visibleApps.first?.id }
    }
    func updatePreference(_ id: String, _ change: (inout AppPreference) -> Void) {
        guard preferencesWritable else { error = "偏好文件不可用，为避免覆盖，请先修复文件。"; return }
        var next = preferences
        var value = next.applications[id] ?? AppPreference(); change(&value)
        do {
            try value.validate(); next.applications[id] = value
            if !demo { try next.save(to: preferencesURL) }
            preferences = next; error = nil; rebuildApplications()
        } catch { self.error = "偏好保存失败：请检查入口格式和文件权限。" }
    }
    func refresh() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        var configWarning: String? = preferencesWritable ? nil : "本机偏好文件无效；原文件已保留，偏好编辑已停用。"
        do {
            if demo {
                configuration = try Configuration.decode(Data(Self.demoConfig.utf8))
                let samples = [Listener(pid: 1201, name: "node", uid: Int(getuid()), host: "127.0.0.1", port: 3000), Listener(pid: 1202, name: "postgres", uid: Int(getuid()), host: "::1", port: 5432), Listener(pid: 1203, name: "python", uid: Int(getuid()), host: "127.0.0.1", port: 8000)]
                lastListeners = samples
                lastIdentities = [:]; verifiedPages = []
                services = ServiceMerger.merge(samples, config: configuration, currentUID: Int(getuid()))
            } else {
                var config = Configuration.empty
                if FileManager.default.fileExists(atPath: configURL.path) {
                    do { config = try Configuration.decode(Data(contentsOf: configURL)) }
                    catch { configWarning = "配置无效，已继续零配置自动发现。请检查配置格式与权限。" }
                }
                let snapshot = try await Task.detached { try LocalDiscovery.scan() }.value
                configuration = config; directories = snapshot.directories
                lastListeners = snapshot.listeners; lastIdentities = snapshot.identities
                verifiedPages = await EntryVerifier.verify(listeners: snapshot.listeners, identities: snapshot.identities, adapters: adapters)
                services = ServiceMerger.merge(snapshot.listeners, config: config, currentUID: Int(getuid()))
            }
            error = configWarning; updated = Date()
            rebuildApplications()
        } catch {
            // Do not present a stale observation as a current running state.
            services = []; applications = []; directories = [:]; selected = nil
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
        WindowGroup("Webby", id: "main") {
            ApplicationWindow(store: store)
                .preferredColorScheme(store.demo && CommandLine.arguments.contains("--demo-dark") ? .dark : nil)
                .frame(minWidth: 960, minHeight: 650)
        }.defaultSize(width: 1180, height: 760)
        .commands { CommandGroup(after: .newItem) { Button("选择兼容配置…") { store.chooseConfig() }.keyboardShortcut("o") } }
        MenuBarExtra("Webby", systemImage: "network") { MenuContent(store: store) }
    }
}
struct MenuContent: View {
    var store: Store
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(store.demo ? "Webby · 演示模式 · 虚构应用" : "Webby · 我的本地应用")
        Text("\(store.applications.filter(\.onHome).count) 个应用入口")
        Button("打开 Webby") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button("刷新应用") { Task { await store.refresh() } }.disabled(store.busy)
        Divider()
        Button("退出 Webby") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
struct ApplicationWindow: View {
    @Bindable var store: Store
    @State private var diagnosticsExpanded = false
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 22) {
                HStack { WebbySpider(); VStack(alignment: .leading) { Text("Webby").font(.title2.bold()); Text("常用应用，一网相连").font(.caption).foregroundStyle(.secondary) } }.padding(.top, 14)
                VStack(spacing: 5) {
                    nav("我的应用", "square.grid.2x2")
                    nav("已关注", "star")
                    Text("应用分类").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 16).padding(.bottom, 4)
                    ForEach(AppCategory.allCases, id: \.self) { category in nav(category.rawValue, categoryIcon(category)) }
                }
                Spacer()
                nav("已隐藏", "eye.slash")
                DisclosureGroup("诊断", isExpanded: $diagnosticsExpanded) { nav("诊断候选", "waveform.path.ecg") }.font(.caption).foregroundStyle(.secondary)
                Label("只读发现 · 偏好留在本机", systemImage: "lock.shield").font(.caption2).foregroundStyle(.secondary)
            }.padding(18).navigationSplitViewColumnWidth(220)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                HStack { VStack(alignment: .leading, spacing: 5) { Text(store.scope).font(.title2.bold()); Text("打开应用的入口，而不是猜测端口").font(.caption).foregroundStyle(.secondary) }; Spacer(); if store.busy { ProgressView().controlSize(.small) } }.padding(.horizontal, 20).padding(.top, 20)
                if store.demo {
                    HStack { Label("演示 · 虚构应用", systemImage: "theatermasks"); Spacer(); Button("查看本机应用") { store.leaveDemo(); Task { await store.refresh() } } }.font(.caption).padding(10).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 16)
                }
                WebTrail(destination: store.applications.first { $0.id == store.selected }?.name ?? store.scope, listening: store.selected != nil).padding(.horizontal, 16)
                if let error = store.error { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal, 18) }
                List(selection: $store.selected) {
                    ForEach(store.visibleApps) { app in
                        HStack(spacing: 12) {
                            Image(systemName: categoryIcon(app.category)).font(.title3).foregroundStyle(.teal).frame(width: 30)
                            VStack(alignment: .leading, spacing: 7) { Text(app.name).font(.headline); Text(app.kindLabel).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if app.favorite { Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow) }
                            Image(systemName: app.managementURL != nil ? "gearshape" : app.appPath != nil ? "macwindow" : "link").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 12).tag(app.id)
                            .contextMenu {
                                Button(app.favorite ? "取消关注" : "关注") { store.updatePreference(app.id) { $0.favorite.toggle() } }
                                Button(app.hidden ? "取消隐藏" : "隐藏") { store.updatePreference(app.id) { $0.hidden.toggle() } }
                            }
                    }
                }.overlay { if store.visibleApps.isEmpty && !store.busy { ContentUnavailableView("这里还没有应用", systemImage: "square.grid.2x2", description: Text("主页收纳已确认入口和关注项。模型/API、其他应用及未知监听可在侧栏查看。")) } }
                HStack { Text(store.updated.map { "已更新 \($0.formatted(date: .omitted, time: .standard))" } ?? "等待发现"); Spacer(); Text("\(store.visibleApps.count) 个应用") }.font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 12)
            }.navigationSplitViewColumnWidth(min: 340, ideal: 400)
        } detail: {
            if let app = store.applications.first(where: { $0.id == store.selected }) { ApplicationDetail(app: app, store: store).id(app.id) }
            else { ContentUnavailableView("让入口回到应用身边", systemImage: "app.connected.to.app.below.fill", description: Text("自动识别应用身份，再确认它提供的管理方式。")) }
        }
        .searchable(text: $store.search, prompt: "搜索当前分类的应用")
        .onChange(of: store.scope) { _, _ in store.selected = store.visibleApps.first?.id }
        .onChange(of: store.search) { _, _ in if !store.visibleApps.contains(where: { $0.id == store.selected }) { store.selected = store.visibleApps.first?.id } }
        .toolbar { Button { Task { await store.refresh() } } label: { Label("刷新应用", systemImage: "arrow.clockwise") }.keyboardShortcut("r").disabled(store.busy) }
        .sheet(item: $store.entryEditor) { app in EntryEditor(app: app, store: store) }
        .task { await store.refresh(); while !Task.isCancelled { try? await Task.sleep(for: .seconds(10)); if Task.isCancelled { break }; await store.refresh() } }
    }
    func nav(_ title: String, _ icon: String) -> some View {
        Button { store.scope = title } label: { HStack { Image(systemName: icon).frame(width: 20); Text(title); Spacer() }.padding(10).background(store.scope == title ? Color.teal.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9)) }.buttonStyle(.plain)
    }
}
func categoryIcon(_ category: AppCategory) -> String {
    switch category { case .ai: "sparkles"; case .development: "hammer"; case .data: "externaldrive"; case .other: "square.grid.2x2" }
}
struct ApplicationDetail: View {
    let app: AppRecord
    let store: Store
    @State private var account: String?
    @State private var revealed = false
    @State private var message: String?
    @Environment(\.scenePhase) private var phase
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack { Image(systemName: categoryIcon(app.category)).font(.system(size: 30)).foregroundStyle(.teal).padding(16).background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 18)); Spacer(); Button { store.updatePreference(app.id) { $0.favorite.toggle() } } label: { Image(systemName: app.favorite ? "star.fill" : "star") }.help(app.favorite ? "取消关注" : "关注") }
                VStack(alignment: .leading, spacing: 8) { Text(app.name).font(.largeTitle.bold()); Text(app.category.rawValue + " · " + app.kindLabel).foregroundStyle(.secondary) }
                Text(app.note).font(.callout).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 12) {
                    if let value = app.managementURL { entryButton("打开管理 / 设置页", value, prominent: true) }
                    if let value = app.applicationURL { entryButton("打开 Web 应用", value, prominent: app.managementURL == nil) }
                    if let path = app.appPath {
                        Button("打开原生应用", systemImage: "macwindow") { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init()) { _, error in if error != nil { Task { @MainActor in message = "应用无法打开，请确认仍已安装。" } } } }.buttonStyle(.bordered)
                    }
                    if !app.hasEntry { Label(app.apiOnly ? "仅 API，未确认 Web 管理页" : "尚无经过确认的可打开入口", systemImage: "info.circle").font(.callout).foregroundStyle(.secondary) }
                    if let hint = app.settingsHint { Text(hint).font(.caption).foregroundStyle(.secondary) }
                }
                if !app.apiEndpoints.isEmpty {
                    GroupBox("API 地址 · 不作为管理页面打开") { VStack(alignment: .leading, spacing: 8) { ForEach(app.apiEndpoints, id: \.self) { endpoint in Text(endpoint).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }; Text("规则给出的 API 地址，不代表接口健康或鉴权成功。").font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(5) }
                }
                HStack { Button("编辑入口…", systemImage: "pencil") { store.entryEditor = app }; Button(app.hidden ? "取消隐藏" : "隐藏", systemImage: app.hidden ? "eye" : "eye.slash") { store.updatePreference(app.id) { $0.hidden.toggle() } } }.font(.caption)
                Divider()
                field("识别依据", app.confidence)
                field("来源", app.source)
                DisclosureGroup("端口与进程诊断（\(app.listeners.count) 个监听）") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("监听快照不代表业务健康，端口不等于管理 URL。").font(.caption).foregroundStyle(.secondary)
                        ForEach(Array(app.listeners.enumerated()), id: \.offset) { _, row in Text("\(row.name) · PID \(row.pid)\n\(row.host):\(row.port)").font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                        field("工作目录", app.legacyConfig?.directory ?? app.listeners.first.flatMap { store.directories[$0.pid] })
                        field("服务配置位置", app.legacyConfig?.configPath)
                    }.padding(.top, 10)
                }.font(.caption)
                if let reference = app.legacyConfig?.accountReference {
                    Divider(); Text("账号信息").font(.headline)
                    Text(SecretMask.display(account, revealed: revealed)).font(.system(.body, design: .monospaced))
                    Button(revealed ? "隐藏账号" : "点击查看账号") {
                        if revealed { clear() } else { do { account = store.demo ? "demo-account (示例)" : try KeychainAccounts().read(reference: reference); revealed = true } catch { message = error.localizedDescription } }
                    }
                }
                if let message { Text(message).font(.caption).foregroundStyle(.orange) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(28)
        }.onDisappear { clear() }.onChange(of: phase) { _, value in if value != .active { clear() } }
        .onChange(of: app.legacyConfig?.accountReference) { _, _ in clear() }
        .task(id: revealed) { if revealed { try? await Task.sleep(for: .seconds(30)); if !Task.isCancelled { clear() } } }
    }
    func clear() { account = nil; revealed = false }
    @ViewBuilder func entryButton(_ title: String, _ value: String, prominent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if prominent { Button(title, systemImage: "arrow.up.right.square") { open(value) }.buttonStyle(.borderedProminent).tint(.teal) }
            else { Button(title, systemImage: "arrow.up.right.square") { open(value) }.buttonStyle(.bordered) }
            Text(value).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
    func open(_ value: String) { if let url = URL(string: value), !NSWorkspace.shared.open(url) { message = "无法打开该入口。" } }
    func field(_ title: String, _ value: String?) -> some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption2).foregroundStyle(.secondary); Text(value ?? "未知 / 未配置").font(.caption).textSelection(.enabled) } }
}
struct EntryEditor: View {
    let app: AppRecord
    let store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var management = ""
    @State private var application = ""
    @State private var api = ""
    @State private var category = AppCategory.other
    @State private var validation: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("\(app.name) · 补充入口").font(.title2.bold())
            Text("仅保存在 Webby 本机偏好，不修改应用本身。留空则继续使用自动识别。不要填写密码或令牌。").font(.caption).foregroundStyle(.secondary)
            Form { TextField("管理 / 设置页", text: $management); TextField("Web 应用地址", text: $application); TextField("API 地址", text: $api); Picker("分类", selection: $category) { ForEach(AppCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) } } }
            if let validation { Text(validation).font(.caption).foregroundStyle(.orange) }
            HStack { Button("取消") { dismiss() }; Spacer(); Button("保存") {
                var value = store.preferences.applications[app.id] ?? AppPreference()
                value.managementURL = clean(management); value.applicationURL = clean(application); value.apiEndpoint = clean(api); value.category = category
                do { try value.validate(); store.updatePreference(app.id) { $0 = value }; if store.error == nil { dismiss() } else { validation = store.error } } catch { validation = error.localizedDescription }
            }.buttonStyle(.borderedProminent) }
        }.padding(24).frame(width: 530)
        .onAppear { let value = store.preferences.applications[app.id]; management = value?.managementURL ?? ""; application = value?.applicationURL ?? ""; api = value?.apiEndpoint ?? ""; category = value?.category ?? app.category }
    }
    func clean(_ value: String) -> String? { let result = value.trimmingCharacters(in: .whitespacesAndNewlines); return result.isEmpty ? nil : result }
}
