# 真实后端（安装 / 启动 / 文件操作）

启动器不是 UI 演示：启动、安装、Java 检测、日志输出都走真实系统调用与网络。
当前范围是 **macOS + 离线 / 微软正版账户**；不含模组加载器内部实现（Fabric/Quilt 由整合包安装流程负责）。

## 1. 模块

| 文件 | 职责 |
|---|---|
| `Launcher/LauncherSettings.swift` | 全部设置项，`@Observable`，自动写 UserDefaults；含版本隔离目录、下载源强类型视图、启动历史、已保存玩家名、`lastSavedAt`、玩家名校验 |
| `Launcher/Backend/JavaRuntime.swift` | 扫描 `/Library/Java/JavaVirtualMachines`、`JAVA_HOME`、Homebrew 等，真实执行 `java -version` 解析版本与厂商 |
| `Launcher/Backend/MinecraftInstallation.swift` | 本地安装目录：`versions/` 扫描（只认有客户端 jar 的版本）、libraries/assets/cache 路径 |
| `Launcher/Backend/MojangManifest.swift` | Mojang 版本清单 / 版本详情拉取（12 小时磁盘缓存）、规则求值、流式下载 + SHA1 校验；支持下载源 URL 改写 |
| `Launcher/Backend/VersionResolver.swift` | 处理 `inheritsFrom`：合并父版本的主类、客户端、依赖库、参数、资源索引 |
| `Launcher/Backend/VersionInstaller.swift` | 真实安装：版本 JSON → 客户端 jar → 依赖库 → 原生库解压 → 资源索引/资源对象 → 日志配置；安装选项、取消、完整性校验 |
| `Launcher/Backend/LaunchCommandBuilder.swift` | 组装 JVM/游戏参数、classpath、natives 目录、离线 UUID、未替换占位符与空值旗标清理 |
| `Launcher/Backend/GameLauncher.swift` | `Process` 启动游戏、逐行回调 stdout/stderr、退出码回调、停止 |
| `Launcher/Backend/LauncherEngine.swift` | `@MainActor @Observable` 编排：环境刷新、安装队列（串行 / 取消 / 进度）、启动/停止、启动历史、日志环形缓冲、旧版本清理 |
| `Launcher/LauncherRouter.swift` | 全局路由：一级页面切换、跨页分区跳转、轻提示、确认框、文本输入框、设计系统 sheet |
| `Launcher/Features/DownloadSource.swift` | 下载源枚举与 URL 改写（官方 / BMCLAPI 镜像，纯函数可测） |
| `Launcher/Features/InstanceActions.swift` | 实例真实文件操作：打开 / 在访达显示 / 复制 / 重命名 / 复制实例 / 删除到废纸篓 / 目录大小 |
| `Launcher/Features/WindowActions.swift` | 窗口动作：恢复默认尺寸、最小化、隐藏启动器 |
| `Launcher/Features/LauncherBuildInfo.swift` | 真实构建信息：版本、可执行文件构建时间、git 短提交 |
| `Launcher/Features/UpdateChecker.swift` | 真实 HTTP 检查更新（可配置更新源 JSON），版本比较与状态机 |
| `Launcher/Features/Download/ModrinthClient.swift` | Modrinth 公开 API 客户端：搜索 / 项目 / 版本 / 下载 URL（纯函数构造 + 解码） |
| `Launcher/Features/Download/ModrinthInstallPlan.swift` | 安装路径决策、路径安全、`.mrpack` 清单解析、加载器识别 |
| `Launcher/Features/Download/DownloadInstallCenter.swift` | 真实安装中心：单文件资源 / 世界 zip / 整合包（基础版本 → Fabric/Quilt → 实例 → files → overrides）/ 本地导入 / 取消 |
| `Launcher/Features/More/MoreBackupService.swift` | `ditto` 真实打包/恢复备份、列表、废纸篓删除、路径归属校验 |
| `Launcher/Features/More/MoreModLibrary.swift` | `mods/` 扫描、`.jar ↔ .jar.disabled` 真实启停、删除、排序统计 |
| `Launcher/Features/More/MoreScreenshotLibrary.swift` | `screenshots/` 扫描 + ImageIO 受限解码缩略图 |
| `Launcher/Features/More/MoreLogExporter.swift` | 日志 / 诊断文本拼装与落盘（`~/Library/Logs/BlockLauncher/`） |
| `Launcher/Features/Settings/*` | 设置分区逻辑：内存方案、JVM 参数解析、Java 探针、清理规划、三语文案、真实重启 |
| `Launcher/LauncherProduct.swift` | LauncherALL 产品枚举（Minecraft / DSH）与标题栏切换菜单文案 |
| `Launcher/Features/Settings/SettingsSectionReset.swift` | 设置页「恢复默认」按分类重置的映射（与 SettingsPage 解耦、便于测试） |
| `Launcher/Features/Auth/MicrosoftAuthModels.swift` | 正版登录端点 / 设备码 / 令牌 / Xbox / Minecraft 档案模型、错误与 `LaunchAccount` |
| `Launcher/Features/Auth/MicrosoftAuthService.swift` | 设备码流真实认证：申请验证码 → 轮询令牌 → XBL → XSTS → Minecraft 登录 → 档案 |
| `Launcher/Features/Auth/AuthTokenStore.swift` | 正版令牌存储：Keychain（失败回退 0600 JSON 文件），测试用内存实现 |
| `Launcher/Features/Auth/AccountStore.swift` | 账户中心：登录状态机、多账户、令牌刷新、启动账户解析 |
| `Launcher/Features/Auth/MicrosoftLoginSheet.swift` | 登录面板：大字验证码 / 复制 / 打开浏览器 / 倒计时 / 内联失败重试；正版头像 |
| `Launcher/Features/Auth/PremiumAccountSection.swift` | 设置页正版账户区：添加 / 切换 / 刷新 / 退出 |

## 2. 安装链路

```
engine.enqueueInstall(versionID, options)         // 串行队列，立即返回队列项
        │
        ├─ engine.cancelInstall(versionID:)        // 取消当前 / 排队项（Task 取消 → 安装器逐阶段检查）
        ├─ VersionResolver.resolveAsync(version)   // inheritsFrom 逐级合并
        │      └─ 父版本 JSON 缺失时从 Mojang 拉取，缓存到 launcher-cache/parents/
        ├─ JavaLocator.bestRuntime(for: requiredMajor)
        ├─ VersionInstaller.install(options:)      // 版本 JSON → 客户端 → 依赖库 → natives → 资源 → 日志配置
        │      ├─ includeAssets   是否下载全部资源对象
        │      ├─ verifyExisting  已存在文件是否重新校验 SHA1（关闭时信任已有文件，装得更快）
        │      └─ 下载源改写：清单 / 版本 JSON / 客户端 / 依赖库 / 资源 URL
        └─ 完成后 engine.refreshEnvironment() + （可选）旧版本清理提示
```

- **安装选项真实生效**：`InstallOptions(includeAssets:verifyExisting:)` 由下载页复选框直接传入安装器。
- **取消**：`Task` 取消 + 安装器在每个阶段 / 资源分块前 `Task.checkCancellation()`；下载流每 64 KB 检查一次。
- **完整性校验**：`engine.verifyInstalled(versionID:)` 校验客户端 jar、依赖库、资源索引、日志配置的 SHA1，返回 `InstallVerification{checked,missing,corrupt}`。
- **队列**：`InstallQueueItem` 记录 `versionID/options/state/progress`，队列驱动 `engine.phase`，下载页展示排队 / 安装 / 完成 / 失败 / 已取消。

## 3. 下载源（镜像）真实生效

`DownloadSource` 是纯函数改写的枚举，安装器与清单服务都在下载前调用 `source.rewrite(url)`：

| 原始域名 | 镜像目标 |
|---|---|
| `piston-meta.mojang.com` / `launchermeta.mojang.com` / `piston-data.mojang.com` | `https://bmclapi2.bangbang93.com`（保留原路径） |
| `resources.download.minecraft.net/<ab>/<hash>` | `https://bmclapi2.bangbang93.com/assets/<ab>/<hash>` |
| `libraries.minecraft.net/<maven 路径>` | `https://bmclapi2.bangbang93.com/maven/<maven 路径>` |

- 未收录的域名（Modrinth / Fabric / Quilt）不改写，避免错误重定向。
- 设置页与下载页的「下载源」共用 `settings.downloadSourceValue`，切换后下一次下载立即生效。

## 4. 启动链路

```
engine.refreshEnvironment()          // 扫描 Java + 已安装版本
        │
        ├─ VersionResolver.resolveAsync(version)   // inheritsFrom 逐级合并
        ├─ JavaLocator.bestRuntime(for: requiredMajor)
        ├─ LaunchCommandBuilder.build(...)         // classpath / natives / 变量替换 / 清理孤立旗标
        └─ GameLauncher.launch(...)                 // Process + 日志流
```

- **离线账户**：用户名 + `md5("OfflinePlayer:<name>")` 生成 UUID，accessToken 为 `0`，不需要网络验证。
- **启动历史**：每次启动写入 `LaunchRecord{versionID, startedAt, finishedAt, exitCode}`（最多保留 50 条），退出时回填退出码；启动页「最近启动」与设置页清理旧版本都读它。
- **启动后最小化**：设置开启时，进入 `.running` 后真实隐藏启动器窗口（离屏/CLI 模式跳过）。
- **版本隔离**：开启时游戏目录直接使用 `versions/<id>`（与 PCL / HMCL 一致，`mods`、`config`、`saves` 就在该目录内，启动即加载玩家已有模组）；关闭时使用根目录。
- **缓存位置**：父版本 JSON / 资源清单 / 日志配置写入 `~/Library/Caches/BlockLauncher/minecraft/`，**不污染用户的游戏目录**。
- **参数清理**：未能替换的 `${...}` 参数与"被替换为空值"的参数会连同其旗标一起丢弃（例如离线模式的 `--clientId`），避免把字面量或孤立旗标传给游戏。

## 5. 正版账户登录（微软设备码流）

与 PCL.Swift 相同的 OAuth 2.0 Device Code Flow（`consumers` 租户，无 client secret）：

```
requestDeviceCode()            POST .../oauth2/v2.0/devicecode   scope=XboxLive.signin offline_access
        ↓ 用户浏览器输入 user_code（面板显示大字 + 复制 + 倒计时）
pollDeviceToken()              POST .../oauth2/v2.0/token        grant_type=device_code
        ↓ authorization_pending 继续；slow_down 间隔 +5s；expired/denied 明确报错
completeLogin()
        ├─ POST user.auth.xboxlive.com/user/authenticate          RpsTicket = "d=<MSA token>"
        ├─ POST xsts.auth.xboxlive.com/xsts/authorize             SandboxId=RETAIL, RelyingParty=rp://api.minecraftservices.com/
        ├─ POST api.minecraftservices.com/authentication/login_with_xbox   identityToken = "XBL3.0 x=<uhs>;<xsts>"
        └─ GET  api.minecraftservices.com/minecraft/profile       Bearer <Minecraft token>
```

- **错误映射**：XSTS `XErr` 2148916233（无 Xbox 账户）/ 2148916235（地区不可用）/ 2148916238（未成年）会转成中文文案并提供帮助链接；profile 404 → 没有 Minecraft 所有权；其他错误带 HTTP 状态与描述。
- **令牌存储**：`KeychainAuthTokenStore` 把 `MinecraftAuthSession`（微软 access/refresh、Minecraft access、过期时间、档案、皮肤）存 Keychain；Keychain 不可用时回退到 `~/Library/Application Support/BlockLauncher/auth/<uuid>.json`（0600）。账户元数据（名字 / UUID / 时间）存 UserDefaults，令牌不落偏好文件。
- **刷新策略**：按 `expires_in` + 5 分钟提前量判断，Minecraft 或微软令牌临近过期时在启动前刷新，刷新结果覆盖 Keychain；刷新失败抛 `invalidRefreshToken`，启动中止并提示重新登录。
- **并发刷新**：同一账户的刷新是 single-flight 的（`AccountStore.inFlightRefreshes` 合并到同一个 Task），避免 refresh_token 轮换后并发请求互相作废；刷新完成前账户被退出登录则跳过令牌回写。
- **启动参数**：正版账户注入 `--username <profile name>`、`--uuid <32 位无连字符>`、`--accessToken <Minecraft token>`、`--userType msa`；版本 JSON 里 `${auth_xuid}` / `${xuid}` 两种占位符都会替换成 xuid；离线账户保持 `--uuid <离线 UUID>`、`--accessToken 0`、`--userType legacy`。日志与「复制启动命令」里的 accessToken 会脱敏成 `***`。
- **UI**：`AccountStore.LoginState` 显式状态机（requestingCode / waitingForUser / authenticating / failed）驱动登录面板与设置页；成功后面板自动关闭、账户加入列表并切换为当前账户。
- **命令行验证**：`swift run MCLauncher --auth-check` 会真实申请一次设备码并打印，验证端点 / 客户端 ID 可用（不轮询、不写账户）。

## 6. 实例文件操作（`InstanceActions`）

| 动作 | 实现 |
|---|---|
| 重命名实例 | 目录改名 → `<id>.json` / `<id>.jar` 改名 → 回写 JSON 的 `id` 字段（只改这一个键，保留其余字段） |
| 复制实例 | 递归复制目录 → 同样的改名与 `id` 回写 |
| 删除实例 | `FileManager.trashItem` 移到废纸篓（可恢复） |
| 目录大小 | 遍历 `totalFileAllocatedSize` 统计真实占用 |
| 打开 / 在访达显示 / 复制 | `NSWorkspace` / `NSPasteboard` |

页面层对删除 / 恢复 / 清空等危险动作统一通过 `LauncherRouter.showDialog` 二次确认。

## 7. 更新检查

- `UpdateChecker.check(feedURL:currentVersion:)` 真实 GET 用户配置的更新源 JSON：
  ```json
  { "version": "0.3.0", "url": "https://…/download", "notes": "修复了…" }
  ```
- 状态机：`noFeed`（未配置）/ `checking` / `upToDate` / `available` / `failed`；`LauncherVersion.isNewer` 做语义版本比较。
- 未配置更新源时页面明确显示"未配置更新源（本地构建）"，**不会伪造"已是最新"**。
- 「更新通道」（正式版 / 快照 / 预览）当前只记录偏好，不参与检查：界面文案明确"当前更新源不支持通道，检查结果与通道无关"。
- 「启动前检查更新」开启时，壳层启动后真实请求一次，发现新版本用轻提示告知。

## 8. 工具服务（更多页）

- **备份**：`ditto -c -k --sequesterRsrc` 打包实例的 saves / mods（含 `.disabled`）/ config / options.txt / servers.dat 到 `<游戏目录>/backups/<实例名>-<时间戳>.zip`；恢复前校验路径归属并二次确认；删除走废纸篓。
- **模组**：扫描实例 `mods/`（版本隔离时在 `versions/<id>/mods`），启用 / 禁用即真实改名，删除走废纸篓，支持搜索与自然排序。
- **截图**：扫描 `screenshots/` 的 png/jpg，ImageIO 最长边 320px 受限解码生成缩略图，预览 / 访达 / 删除 / 复制路径。
- **日志**：导出为 `~/Library/Logs/BlockLauncher/blocklauncher-<时间>.log`（含版本、启动命令、退出码、行数 header），打开日志文件夹真实创建并打开。

## 9. 命令行验证（不经过 UI）

```bash
swift run MCLauncher --detect-java
swift run MCLauncher --list-installed
swift run MCLauncher --launch-dry-run 1.21.11-Fabric        # 只打印最终命令，不启动
swift run MCLauncher --launch-dry-run 1.21.11-Fabric --dir ~/Library/Application\ Support/minecraft
swift run MCLauncher --install 1.21.4                       # 真实下载安装（较慢）
```

`--launch-dry-run` 输出：Java 版本、继承合并结果、依赖缺失数量、游戏目录、离线 UUID、参数条数与完整命令行。
存在缺失依赖时退出码为 `3`，可用于脚本判断。

## 10. 测试覆盖

`swift test` 共 **215 个用例**（全部离线）：

- `LauncherBackendTests`（12）：规则求值、离线 UUID、参数替换与清理、版本 JSON 兼容、版本扫描、命令构建。
- `SharedInteractionsTests`（20）：镜像 URL 改写、版本比较、实例重命名/复制/删除（真实临时目录）、启动历史持久化与"已停止"状态、玩家名校验、空值旗标清理、更新源解析、安装取消判定（`CancellationError` / `URLError.cancelled`）、父版本依赖保护与清理候选判龄。
- `DownloadFeatureTests`（35）：Modrinth URL / 解码 / 安装路径决策 / `.mrpack` 解析与缺下载地址 / zip-slip 条目校验 / loader 兼容判断 / 离线安装流程（URLProtocol stub）。
- `SettingsFeatureTests`（30）：内存方案、JVM 冲突、Java 探针、清理规划、日志导出（与更多页同一落点）、三语文案完整性与文案真实性。
- `MoreFeatureTests`（18）：真实 ditto 备份/恢复、模组启停、截图缩略图、日志导出。
- `AuthFeatureTests`（21）：设备码 / 令牌 / XBL / XSTS / Minecraft 登录请求构造与响应解码、XSTS 错误码、会话刷新窗口、启动身份、账户状态机（成功 / 失败 / 取消 / 退出 / 刷新）、正版启动参数与令牌脱敏。
- `XMLUITests`（16）：XML 引擎。
- `ProductSwitcherTests`（4）：LauncherALL 产品切换（Minecraft / DSH）、跨产品切页、DSH 启动页两主题离屏渲染。

## 11. DSH 启动器（Web UI 版本 + 插件市场）

LauncherALL 的第二个启动器管理官方 `@deepseek-ai/dsh` 的 **Web UI 版本**（与桌面端/ TUI 共用同一个 npm 包，`bin: lib/bin.js`）：

| 模块 | 职责 |
| --- | --- |
| `Features/DSH/DSHModels.swift` | 版本 / 插件 / 目录状态 / 安装状态 / 进程状态 / 错误，以及完整 semver 比较（含 prerelease） |
| `Features/DSH/DSHPaths.swift` | launcher 数据目录、版本目录、共享 DSH_HOME（凭据软链）、Node/pnpm/npm 定位与 pnpm shim |
| `Features/DSH/DSHRegistryClient.swift` | npm registry 版本目录（`@deepseek-ai%2fdsh`，40 个版本）与 dshmarket 插件加载源（`plugins.json`，8000+ 条） |
| `Features/DSH/DSHVersionStore.swift` | 已安装版本扫描 / 安装 / 卸载 / 选择 / 磁盘缓存 |
| `Features/DSH/DSHProcessController.swift` | 启动 / 停止 `dsh --profile web --no-open --port …`，解析带 token 的启动 URL，日志落盘与脱敏 |
| `Features/DSH/DSHPluginStore.swift` | 插件目录搜索 / 分类 / 排序 / 安装 / 卸载（转发 `dsh plugin --profile web add/remove`） |
| `Launcher/Pages/DSH/*` | 四个 DSH 页面（启动 / 下载 / 设置 / 更多），与 Minecraft 页面同构 |

- **下载源**：`https://registry.npmjs.org/@deepseek-ai/dsh`，包名斜杠编码为 `%2f`（不能二次编码）；可安装全部历史版本，安装到 `~/Library/Application Support/BlockLauncher/DSH/versions/<version>/node_modules`（每个版本约 850 MB）。
- **安装**：在版本目录里用 pnpm（系统优先，否则 DSH 桌面端自带 pnpm 的 shim，最后 npm）执行 `add @deepseek-ai/dsh@<version>`；完成后校验 `node_modules/@deepseek-ai/dsh/lib/bin.js` 并写入 `launcher-install.json`（安装时间 / 大小）。取消安装会终止子进程并清理半成品目录。
- **Node**：优先登录 shell 里的标准 Node（nvm/Homebrew），其次 DSH 桌面端自带运行时；GUI 进程 PATH 很窄，因此会通过登录 shell 与已知路径探测，子进程 PATH 会补齐 node / pnpm / npm 目录。
- **启动**：`node …/bin.js --profile web --no-open --port <port>`（端口 0 交给 dsh 自动分配）；`DSH_HOME` 固定为 launcher 的共享 home（`~/Library/Application Support/BlockLauncher/DSH/home`），首次启动把 `~/.dsh/.credentials.yaml`、`.anonymous-user-id`、`settings.yaml` 软链进来复用登录 / API Key，避免 Web UI 要求重新输入密钥。解析 stdout 的 `dsh web: <url>` 得到带一次性 token 的地址；日志里 token 会脱敏成 `token=***`，日志文件 0600。
- **插件市场**：加载源默认 `https://awesome-dsh-plugin.com/plugins.json`（dshmarket 自身使用的数据源）——字段 `name/owner/url/page/category/description{en,zh}/npm/version/stars/capabilities/install`；安装标识优先 `npm`，否则取 `install` 命令 `add` 后的 spec。安装 / 卸载真实执行 `dsh plugin --profile web add|remove <spec>`，并读取 `$DSH_HOME/profiles/web/package.json` 判定已安装。
- **CLI**：`swift run MCLauncher --dsh-check` 检查 Node/pnpm 环境、打印已安装版本、拉取 npm 版本数，并真实启动一次 Web UI 后停止（不打开浏览器）。
- **测试**：`DSHBackendTests`（17）+ `DSHDownloadUITests`（14）+ `DSHLaunchUITests`（12）+ `DSHSettingsUITests`（16）覆盖 semver、版本目录 URL / 解码、插件加载源与 install spec、目录布局、安装扫描/卸载、已安装插件、端口、命令执行、pnpm shim、共享 DSH_HOME、token 脱敏。

## 12. 已知限制

- 正版登录只支持个人微软账户（consumers 租户）；未接入企业租户、401 自动重放与多设备管理。
- 正版皮肤 / 披风管理未实现；头像展示使用 crafatar 兜底，不影响启动身份。
- 默认客户端 ID 复用 PCL.Swift 的公开注册，正式发布建议自建 Azure 应用（public client + device code）。
- 只处理 `macOS`（osx/arm64）规则；Windows/Linux 需要补规则与路径。
- 整合包只支持 Fabric / Quilt / 原版；Forge / NeoForge 会明确报错；加载器元数据与依赖库直连 Fabric/Quilt 官方域，不走镜像。
- 镜像只覆盖 Mojang 域名；Modrinth / Fabric / Quilt 直连。
- 资源文件数量多，首次安装耗时较长；已有文件默认跳过（SHA1 校验）。
- 游戏进程退出码、日志实时性依赖游戏自身输出。
- 模组只做文件级启用 / 禁用 / 删除，不做依赖解析、更新检测与冲突分析。
- 语言切换只覆盖「设置」页（258 键 × zh-Hans/en/ja），其余页面仍为中文，界面会如实说明。
- 更新通道目前仅记录偏好，检查更新只读取更新源地址。
- DSH 启动器只管理 `@deepseek-ai/dsh` 的 Web UI 版本；插件安装依赖 pnpm（无系统 pnpm 时用 DSH 桌面端自带 pnpm 生成 shim）；Web UI 在浏览器打开，不内嵌。
- DSH 的 `DSH_HOME` 由 launcher 管理（所有版本共享，凭据从 `~/.dsh` 软链复用）；插件 / 会话与系统 DSH 的 web profile 分开，卸载版本只删该版本 node_modules 与日志。
