# Webby · 常用应用，一网相连

SwiftUI 原生 macOS 本地应用与服务入口工具。自动发现正在监听的本地应用，按应用身份归并多个进程和端口，把**管理页面、Web 应用、API 和原生应用**明确分开。端口只是诊断信息，不再充当主页的主要对象。

## 使用

macOS 14+，Swift 6；测试需要完整 Xcode。无第三方库。

```sh
./scripts/build-app.sh
open dist/Webby.app
```

默认启动实时发现，不保存演示状态。只有显式 `--demo` 进入合成演示，主窗口与菜单栏持续标注；`--demo-dark` 单独不会开启演示。退出演示先清空合成数据再扫描。应用仅 ad-hoc 签名，尚未公证，不修改 Gatekeeper。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH="$PWD/.build-webby/clang-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build-webby/module-cache" \
swift test --scratch-path .build-webby --disable-sandbox
```

`--disable-sandbox` 只影响 SwiftPM 构建沙箱，不修改系统权限。真实监听测试只创建/关闭测试自己的回环 socket；环境禁止绑定时会明确 skip，不能据此声称完成真实验收。要生成另一份应用而不替换运行中的版本，可设置 `WEBBY_APP_OUTPUT` 后运行构建脚本。

## 主页和分类

- **我的应用**：适配规则明确识别且有管理/Web/原生入口的应用，以及用户关注项。API-only 和未知监听不会挤满主页。
- **已关注**：通过星标收藏，无需创建服务记录。
- **AI / 模型、开发工具、数据服务、其他**：按应用分类。仅 API 的服务仍在所属分类可见，明确说明尚无已确认 Web 管理页。
- **已隐藏**：随时查看和恢复隐藏应用；隐藏不停止服务。
- **诊断 → 诊断候选**：折叠的未知进程/应用候选。保留自动发现，不把未知端口强行变成 URL。
- 搜索作用于当前视图；端口、PID、工作目录在详情的折叠诊断区域。

## 入口如何确认

| 应用/类型 | 入口策略 | 依据与边界 |
| --- | --- | --- |
| Alma | 原生应用；提示打开后按 ⌘, | [官方设置说明](https://alma.now/docs/settings/)及包 ID。未证明监听端口提供 Web 设置页，故不生成浏览器管理链接。 |
| ddalcu MLX Serve | Studio 应用页 `/`、Studio 设置 `/#settings`；API `/v1` 单列 | [官方 README](https://github.com/ddalcu/mlx-serve#readme)与[官方路由源码](https://github.com/ddalcu/mlx-serve/blob/main/app-web/src/lib/state/router.svelte.ts)。仅匹配进程身份、官方默认端口，且回环首页 HTML 标题通过 `MLX Serve Studio` 验证后提供 Web 入口。Studio 设置管理界面/连接，不等于修改引擎启动参数。 |
| Magpie | API `/v1`；有应用包时提供原生入口 | [官方项目](https://github.com/yetone/magpie)。不将 API 根路径作为管理页面；未确认的 Web 管理路由不生成。 |
| Docker Desktop | 原生 Dashboard | [官方文档](https://docs.docker.com/desktop/use-desktop/)与包身份。容器暴露的端口不是 Docker 管理页。 |
| Antigravity / JetBrains | 原生编辑器 | 根据本机应用包标识/可执行程序归属打开应用；不伪造设置深链接。 |
| Redis / PostgreSQL | 数据服务，无内置 Web 管理入口 | [Redis 协议](https://redis.io/docs/latest/develop/reference/protocol-spec/)、[PostgreSQL 协议](https://www.postgresql.org/docs/current/protocol.html)。管理客户端如 pgAdmin 是独立应用。 |

以上是产品适配规则，不是某台机器的服务清单。其他同名 MLX 实现、改过端口或绑定在特定网卡上的服务，不保证能推断 Web 入口。可以对已发现的应用补充入口，自动发现仍然是前提，不需逐个添加服务。

## 配置与优先级

内置规则在 [adapters.json](Sources/Webby/Resources/adapters.json)，版本 1。每个规则包含 `id/name/category`、`bundleIDs/processNames`、入口 `kind/port/path/titleMarker`、原生设置说明及来源。网页入口必须声明 HTML 标题校验标识；API 永远不自动提升成管理页。规则属于代码随应用发布，任何新增规则应有官方依据及回归测试。

用户偏好保存在 `~/Library/Application Support/Webby/preferences.local.json`，版本 1。仅在用户点击收藏、隐藏或保存入口时写入，权限 0600，原子写入。不保存自动发现清单，不记录凭据。内容是按稳定应用 ID 索引的 `favorite/hidden/category/managementURL/applicationURL/apiEndpoint`。无效文件不会被静默覆盖；修复后重启加载。界面编辑留空恢复自动识别。URL 禁止内嵌凭据或查询参数，片段仅接受明确的导航标识。

优先级：当前用户/系统排除及忽略规则 → 包身份匹配（优于进程名规则）→ 同应用聚合 → 官方规则加只读页面确认 → 用户入口/分类覆盖 → 收藏与隐藏控制可见性。打开状态不是健康判断。隐藏优先于收藏，隐藏视图可以恢复。

兼容首版 `config.json` 版本 1 和 [脱敏示例](examples/config.example.json)，仍支持忽略进程/端口、名称、工作目录、配置位置、账号引用。原 `url` 只当作 **Web 应用入口**，不擅自解释为管理页。不存在或无效配置不阻止零配置发现。旧配置中的离线条目不会伪装成正在运行的应用。

## 发现与隐私边界

- 使用系统 lsof 的结构化字段，只发现当前用户 TCP LISTEN socket；不读取进程参数或环境变量，不申请管理员权限。
- 读取可执行路径和应用包 Info.plist 元数据，以最外层 `.app` 归并子进程、多端口；CLI 使用明确适配规则。通用 Node/Python 不凭短名或端口认定具体产品，不把不同实例混成一个应用。
- 普通无监听桌面进程、其他用户、root、系统服务被排除；UDP、Unix socket、容器内部未映射端口不在范围内。过滤是保守启发式；未知身份保留诊断候选。
- 每 10 秒更新。进程退出移除快照，端口复用重新按身份识别。监听不代表业务健康，页面存在不代表 API 鉴权或模型可用。
- **网页确认仅对适配规则明确允许的回环地址执行 GET `/`**，最多读取标题所需的 16 KiB，限制超时，不跟随重定向、不带 cookie/凭据，不执行 JavaScript，也不访问修改设置的接口。不扫描随机路径或局域网。
- 不自动读取服务配置文件、账号、Keychain 列表。旧配置的账号引用仅在用户点击查看后读取 `app.webby.accounts` 下的精确项目；恒定遮罩、离开详情/失活/30 秒后隐藏。无写入凭据接口，不弹出授权交互。Swift 字符串不保证逐字节内存擦除。
- 不上传遥测、服务清单或偏好，不记录响应正文。仅用户主动打开入口时交给默认浏览器或原生应用。所有真实配置、偏好、清单和工作截图禁止提交公开仓库。

## 架构与小蜘蛛

`WebbyCore` 提供监听解析、配置校验、应用身份聚合、入口类型与偏好模型；`Webby` 提供 SwiftUI 主窗口/菜单栏、JSON 适配资源、限界只读页面确认和 Keychain 接口。测试覆盖 IPv4/IPv6、多端口、生命周期、系统过滤、零配置启动、API/管理页隔离、包子进程聚合和偏好持久化。

小蜘蛛由 SwiftUI Canvas 独立绘制。参考 Magpie 官方 [routing.css](https://github.com/yetone/magpie/blob/main/internal/gui/assets/plugins/routing/routing.css) 与 [client.js](https://github.com/yetone/magpie/blob/main/internal/gui/assets/plugins/routing/client.js) 中角色沿连接线移动的节奏，不复制喜鹊素材或代码。导航小蜘蛛不表示网络流量或业务健康；不拦截点击，支持系统 Reduce Motion 和深浅色，保留原生列表键盘导航。

[MIT License](LICENSE)。不提供停止进程、修改系统权限、开机启动或替用户改服务设置的操作。
