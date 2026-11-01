# 真实启动链路（Backend）

启动器不再只是 UI 演示：启动、安装、Java 检测、日志输出都走真实系统调用与网络。
当前范围是 **macOS + 离线账户**，不涉及微软正版登录与模组加载器内部实现。

## 1. 模块

| 文件 | 职责 |
|---|---|
| `Launcher/LauncherSettings.swift` | 全部设置项，`@Observable`，自动写 UserDefaults；含版本隔离目录计算 |
| `Backend/JavaRuntime.swift` | 扫描 `/Library/Java/JavaVirtualMachines`、`JAVA_HOME`、Homebrew 等，真实执行 `java -version` 解析版本与厂商 |
| `Backend/MinecraftInstallation.swift` | 本地安装目录：`versions/` 扫描（只认有客户端 jar 的版本）、libraries/assets/cache 路径 |
| `Backend/MojangManifest.swift` | Mojang 版本清单 / 版本详情拉取（12 小时磁盘缓存）、规则求值、流式下载 + SHA1 校验 |
| `Backend/VersionResolver.swift` | 处理 `inheritsFrom`：合并父版本的主类、客户端、依赖库、参数、资源索引 |
| `Backend/VersionInstaller.swift` | 真实安装：版本 JSON → 客户端 jar → 依赖库 → 原生库解压 → 资源索引/资源对象 → 日志配置 |
| `Backend/LaunchCommandBuilder.swift` | 组装 JVM/游戏参数、classpath、natives 目录、离线 UUID、未替换占位符清理 |
| `Backend/GameLauncher.swift` | `Process` 启动游戏、逐行回调 stdout/stderr、退出码回调、停止 |
| `Backend/LauncherEngine.swift` | `@MainActor @Observable` 编排：环境刷新、安装进度、启动/停止、日志环形缓冲 |

## 2. 启动流程

```
engine.refreshEnvironment()          // 扫描 Java + 已安装版本
        │
        ├─ VersionResolver.resolveAsync(version)   // inheritsFrom 逐级合并
        │      └─ 父版本 JSON 缺失时从 Mojang 拉取，缓存到 launcher-cache/parents/
        ├─ JavaLocator.bestRuntime(for: requiredMajor)
        ├─ LaunchCommandBuilder.build(...)         // classpath / natives / 变量替换
        └─ GameLauncher.launch(...)                 // Process + 日志流
```

- **离线账户**：用户名 + `md5("OfflinePlayer:<name>")` 生成 UUID，accessToken 为 `0`，不需要网络验证。
- **版本隔离**：开启时游戏目录直接使用 `versions/<id>`（与 PCL / HMCL 一致，`mods`、`config`、`saves` 就在该目录内，启动即加载玩家已有模组）；关闭时使用根目录。
- **缓存位置**：父版本 JSON / 资源清单 / 日志配置写入 `~/Library/Caches/BlockLauncher/minecraft/`，**不污染用户的游戏目录**。
- **安装**：只有用户主动点「安装」时才会写入 `versions/<id>/`，并下载依赖到 `libraries/`、资源到 `assets/`。

## 3. 命令行验证（不经过 UI）

```bash
swift run MCLauncher --detect-java
swift run MCLauncher --list-installed
swift run MCLauncher --launch-dry-run 1.21.11-Fabric        # 只打印最终命令，不启动
swift run MCLauncher --launch-dry-run 1.21.11-Fabric --dir ~/Library/Application\ Support/minecraft
swift run MCLauncher --install 1.21.4                       # 真实下载安装（较慢）
```

`--launch-dry-run` 输出：Java 版本、继承合并结果、依赖缺失数量、游戏目录、离线 UUID、参数条数与完整命令行。
存在缺失依赖时退出码为 `3`，可用于脚本判断。

## 4. 已知限制

- 仅离线账户；微软/Xbox 登录、正版皮肤未接入。
- 只处理 `macOS`（osx/arm64）规则；Windows/Linux 需要补规则与路径。
- 未实现模组/整合包解压安装（下载页整合包仍为展示态）。
- 资源文件数量多，首次安装耗时较长；已有文件会跳过（SHA1 校验）。
- 游戏进程退出码、日志实时性依赖游戏自身输出。

## 5. 验证

### 端到端真实启动（本机）

```bash
swift run MCLauncher --launch 26.3-Fabric --timeout 12
```

真实输出（节选）：

```
可用 Java：Java 25, Java 17
游戏已启动（pid 71456）
[main/INFO]: Loading Minecraft 26.3 with Fabric Loader 0.20.1
[main/INFO]: Loading 57 mods:
  - fabric-api 0.165.0+26.3
  …
```

启动命令包含合并后的 121 个依赖、natives 目录、`-XstartOnFirstThread`、离线 UUID 与完整游戏参数；
游戏以玩家自己的版本目录为工作区，模组正常加载。

- `swift test`：28 个用例（12 个后端用例覆盖 UUID、规则、参数替换、JSON 兼容、版本扫描、命令构建）。
- 本机真实安装（3 个实例，含 Fabric 与整合包）：
  - `1.21.11-Fabric`：继承合并 115 个依赖、缺失 0、31 个启动参数
  - `26.3-Fabric`：121 个依赖、缺失 0、35 个参数
  - 整合包：89 个依赖、缺失 18（提示先安装）
