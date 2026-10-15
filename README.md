# Webby · 服务织网

真正的 SwiftUI macOS 原生本地服务查看器。**零配置启动即自动发现**当前用户的 TCP 监听服务，每 10 秒刷新新增与退出，支持主窗口、菜单栏入口、搜索、配置补充和浏览器打开。MIT 开源。

## 运行

需要 macOS 14+、Swift 6 工具链。构建应用不需要第三方依赖；测试需要完整 Xcode 的 XCTest。

```sh
./scripts/build-app.sh
open dist/Webby.app
```

应用仅作本地 ad-hoc 签名，未作 Developer ID 签名或公证，不修改 Gatekeeper。也可 `swift run Webby`。安全界面演示：`open dist/Webby.app --args --demo`，该模式不会扫描本机，也不会读取钥匙串；账号值均为虚构示例。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH="$PWD/.build-webby/clang-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build-webby/module-cache" \
swift test --scratch-path .build-webby --disable-sandbox
```

`--disable-sandbox` 只关闭 SwiftPM 构建子进程沙箱，不修改系统权限。运行环境若禁止绑定回环端口，真实监听集成测试会明确 skip，不能视为通过验收。

## 自动发现及边界

使用系统 `/usr/sbin/lsof` 结构化字段输出读取当前用户 TCP LISTEN socket；不需要管理员权限、不发送网络探测、不读取环境变量或进程参数。通过 `proc_pidpath` 排除系统目录下的程序及已退出进程，另排除已知系统辅助进程。只有存在监听的进程才成为自动发现候选，不收集普通无网络桌面进程。

- IPv4/IPv6、通配地址、同一进程多端口和重复 socket 均被归并。界面显示实际进程名；无法推断产品身份时不虚构应用名称。
- TCP 监听不是业务健康；“未发现”也不等于崩溃。自动项退出后移除，配置项保留并显示未发现。端口复用后重新按进程与端口匹配，不继承其他进程的 URL。
- 不根据端口猜测 HTTP。仅用户配置的 HTTP(S) URL 提供打开按钮；未知协议明确显示未知。
- 不覆盖 UDP、Unix socket、其他用户、root 服务、容器内部未映射端口或被系统隐私限制的进程；系统服务过滤是保守启发式，并非完备分类器。可用忽略规则补充。
- 检测是快照，进程可能在读取后立即退出或重用 PID；下一次刷新纠正。工作目录读取失败时显示未知，配置路径不会被自动搜寻。
- 检测错误清空旧结果并明确提示，不把旧监听继续标为当前运行。无配置是正常情况，无需逐个添加服务。

## 配置（可选）

默认读取 `~/Library/Application Support/Webby/config.json`，不存在时仍正常自动发现。菜单“选择配置…”可选择你主动创建的文件，不保存该选择。应用不会自动创建配置。参见 [脱敏示例](examples/config.example.json)。每次刷新重新读取。

| 字段 | 含义 |
| --- | --- |
| version | 当前仅支持 1 |
| ignoredProcesses / ignoredPorts | 精确匹配的全局忽略项 |
| services[].id / name | 唯一 ID、显示名称 |
| process / port | 精确进程名与端口联合匹配，不能只凭端口认定应用 |
| group | 服务分组标签 |
| url | 显式 HTTP(S) 地址及路径；禁止内嵌账号、密码、查询串和片段 |
| directory / configPath | 用户提供的工作目录和配置位置；只展示，不读取该配置内容 |
| accountReference | Webby 专用 Keychain 账号引用，不是密码 |

优先级：当前用户与系统过滤 → 忽略规则 → 精确匹配配置覆盖 → 剩余监听自动发现。配置可覆盖展示信息，不能改变观察到的监听状态；多匹配进程会同时展示。拒绝未知版本、重复 ID、重复匹配规则、越界端口及不安全 URL。JSON 不合法时提示错误并继续零配置自动发现，不在日志回显内容。

## 账号与隐私

默认恒定长度遮罩；只有点击“查看”才按 `app.webby.accounts` 服务名及用户配置的准确引用读取单个 Keychain 项目。禁止自动遍历钥匙串、禁止写入凭据，不弹出授权交互。真实账号由用户自行在钥匙串管理；无权限则提示。隐藏、离开详情、应用失活或 30 秒后清除 UI 中的引用；Swift 字符串无法保证内存逐字节擦除。

应用不联网、不上传遥测、不保存服务清单或日志。点击“浏览器打开”会交由默认浏览器访问用户配置的地址。工作目录和服务信息只在内存及界面显示。请勿把真实配置、凭据、服务清单或工作截图放入公开仓库；`.local.json`、构建产物已忽略。仓库仅包含合成测试数据与脱敏示例。

## 架构与设计

- `WebbyCore`：纯数据解析、配置校验、过滤与合并、只读发现。无第三方依赖。
- `Webby`：SwiftUI NavigationSplitView 主窗口、MenuBarExtra 入口、异步轮询、只读 Keychain 接口。系统语义颜色自动适配深浅模式，原生键盘操作与文本选择。
- `Tests`：解析、配置优先级/校验、系统及忽略过滤、端口复用、秘密遮罩；真实 socket 集成测试验证零配置出现与消失，不打印本机服务清单。

参考对象是 [yetone/magpie](https://github.com/yetone/magpie) 的 Agents 页面及菜单栏工具定位；参考其 [公开截图](https://raw.githubusercontent.com/yetone/magpie/main/site/public/img/agents-light.png) 的细分隔线、克制状态色和留白。Webby 使用独立布局及 Apple SF Symbols，不复制 Magpie 品牌图标或素材。

首版不提供停止进程、修改系统权限、开机启动、业务健康检查或自动协议猜测。后续可在明确授权的范围扩展更精确的应用识别。

## 许可

[MIT](LICENSE)，2026 Webby contributors。

## 小蜘蛛带路

已实际阅读 Magpie 官方 [routing.css](https://github.com/yetone/magpie/blob/main/internal/gui/assets/plugins/routing/routing.css) 和 [client.js](https://github.com/yetone/magpie/blob/main/internal/gui/assets/plugins/routing/client.js)：它以喜鹊沿路径携带请求与响应，使用约 0.3–0.45 秒进出场、0.42 秒振翅，并处理减少动态效果。Webby 借鉴“角色沿连接线前进”的节奏，不复用喜鹊素材或代码。

`WebTrail` / `WebbySpider` 是独立 SwiftUI + Canvas 实现：切换筛选或服务时，小跳蛛沿丝线向服务节点移动 0.55 秒；新行轻亮 0.8 秒；未发现节点用虚线圆环表达。此线只代表导航，不冒充真实网络流量。装饰层不接收点击、不进入辅助功能树，服务列表保留原生键盘导航。系统 Reduce Motion 禁止位移与高亮动画，深浅色使用语义色。`--demo --demo-dark` 可检查深色演示，不修改系统外观。
