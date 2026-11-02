# 方块启动器 · 主界面与交互契约

> 目标：四页里的**每个可交互控件都接真实行为**（文件 / 网络 / 进程 / 持久化设置），不再用 `@State` 模拟。
> 视觉规则见 [`DESIGN-SYSTEM.md`](DESIGN-SYSTEM.md)，后端与安装/启动链路见 [`BACKEND.md`](BACKEND.md)。

## 1. 结构

```
LauncherAppShell（窗口壳：顶部导航栏 + 内容区 + 全局 Overlay）
├─ 导航栏：品牌 v0.2.0 ｜ [启动 ⌘1] [下载 ⌘2] [设置 ⌘3] [更多 ⌘4] ｜ 主题切换 ｜ 账户胶囊 ｜ 设置图标
└─ 内容区（按 tab 切换，淡入过渡）
   ├─ LaunchPage      启动：实例列表 / 实例概览 / 启动与日志 / 最近启动
   ├─ DownloadPage    下载：Mojang 版本 + 安装队列 + 磁盘/下载源 + Modrinth 社区资源
   ├─ SettingsPage    设置：启动 / Java / 性能 / 更新与语言 / 外观 / 账户 / 关于 / 日志与诊断
   └─ MorePage        更多：日志 / 备份 / 模组 / 截图 / 社区 / 快捷键 / 关于
```

壳层还负责：全局快捷键（⌘1–⌘4、⌘⇧D、⌘R、⌘,）、启动后最小化、启动前检查更新、`LauncherRouter` 注入与 Overlay 宿主（toast / dialog / prompt）。

设计器入口：`更多 → 设计系统画廊` 或 ⌘⇧D 以 sheet 打开 `LauncherShellView`。

## 2. 全局交互层（`LauncherRouter`）

页面通过 `@Environment(LauncherRouter.self)` 使用，任何按钮都能真正生效：

| API | 行为 |
|---|---|
| `router.go(tab, moreSection:settingsSection:)` | 切换一级页面，同时指定目标页要打开的分区 |
| `router.pendingMoreSection` / `pendingSettingsSection` / `pendingDownloadAction` / `pendingLaunchAction` | 一次性跨页动作，目标页 `onAppear`/`onChange` 消费后置 `nil` |
| `router.showToast(_:tone:)` | 底部轻提示，2.2 秒自动消失 |
| `router.showDialog(LauncherDialogRequest)` | 居中固定宽度（400pt）的确认对话框（支持危险色、取消回调），遮罩铺满窗口 |
| `router.showPrompt(LauncherPromptRequest)` | 文本输入对话框（带实时校验，非法时禁用确认） |
| `router.openGallery()` | 以 sheet 打开设计系统画廊 |
| 壳层登录 sheet | `AccountStore.isLoginSheetPresented` 驱动 `MicrosoftLoginSheet`；成功后自动关闭并 toast |

壳层快捷键：

| 快捷键 | 作用 |
|---|---|
| ⌘1 / ⌘2 / ⌘3 / ⌘4 | 启动 / 下载 / 设置 / 更多 |
| ⌘⇧D | 设计系统画廊 |
| ⌘⇧T | 切换深 / 浅主题 |
| ⌘R | 刷新 Java 与实例列表 |
| ⌘, | 设置 |
| ⌘↩ | 启动当前选中实例（启动页注册） |

## 3. 页面交互契约

### LaunchPage（启动）

| 控件 | 真实行为 |
|---|---|
| 实例行 / 版本下拉 | 选中实例（`engine.installedVersions`） |
| 启动游戏 / ⌘↩ | `engine.launch(versionID:)`：真实 Process 启动、日志实时追加 |
| 停止游戏 | `engine.stop()` 真实 terminate |
| 实例操作菜单 | 打开版本目录 / 在访达显示 / 打开 mods / 重命名实例（prompt + 改名 JSON id）/ 复制实例 / 校验文件（SHA1）/ 查看启动日志（跳更多）/ 复制启动命令 / 删除实例（确认 + 废纸篓） |
| 搜索 / 刷新 / 新建 | 过滤实例；刷新扫描；跳下载页安装 |
| 导入整合包 | 跳下载页并触发 `pendingDownloadAction = "import-modpack"` |
| 标题栏品牌下拉（LauncherALL） | 切换启动器：Minecraft 启动器 / DSH 启动器；两者共用启动/下载/设置/更多四个导航页，切换产品只换页面内容；DSH 模式隐藏 Minecraft 的账户胶囊（齿轮保留） |
| DSH 启动页 | 左侧已安装版本列表（搜索/刷新/选择/空态去下载）+ 右侧启动卡片（启动/停止/打开/复制地址、运行状态、端口、实时日志）、环境与路径卡、插件入口卡；停止进程前二次确认 |
| DSH 下载页 | 左侧「DSH 版本 / 插件市场」分类；版本页：npm 版本列表（latest/alpha 标签、发布时间、大小、安装/卸载、安装阶段日志、取消），卸载确认；插件页：搜索/分类/排序 8000+ 插件、安装/卸载（真实 `dsh plugin --profile web add/remove`）、已安装列表、加载源状态；跨页动作 `dsh-versions` / `dsh-plugins` 会被消费 |
| DSH 设置页 | 启动（端口/自动打开浏览器/默认版本）、下载与插件（npm registry、插件加载源、缓存清理）、环境与目录（Node/pnpm、DSH_HOME、版本/缓存/日志目录、磁盘占用、重新检测）、关于与危险区清理 |
| DSH 更多页 | 运行日志（token 脱敏、复制/清空/在访达显示）、数据目录（versions / DSH_HOME / cache / bin）、进程状态与打开/复制/停止、关于与快捷键 | 
| 账户胶囊 / 左栏账户行 | 显示当前账户（离线 / 正版）+ 类型徽标，点击跳设置·账户 |
| 日志卡「更多」 | 复制启动命令 / 清空日志 / 跳更多·日志 |
| 最近启动 | 真实 `LauncherRecord`（版本 / 时间 / 时长 / 退出码），持久化 |
| 实例占用 | 后台统计版本目录真实大小（离屏模式显示占位） |

### DownloadPage（下载）

| 控件 | 真实行为 |
|---|---|
| 分类 / 搜索 / 排序 | 本地过滤 Mojang 清单；社区分类走 Modrinth 真实搜索（防抖 300ms） |
| 版本行 / 详情 | 已安装版本同步读本地 JSON；未安装版本异步拉官方 JSON（显示 Java 要求、资源索引） |
| 安装 / 重新安装 | `engine.enqueueInstall(versionID:options:)` 真实下载（清单 / 客户端 / 依赖 / natives / 资源） |
| 安装选项 | `安装资源文件` → `includeAssets`；`校验已存在文件` → `verifyExisting` |
| 安装队列 | 排队 / 安装 / 完成 / 失败 / 已取消；取消当前或排队项、移除单项、清空已完成 |
| 已安装版本菜单 | 校验文件 / 打开实例目录 / 删除（确认 + 废纸篓） |
| 磁盘占用 | 后台统计 versions / libraries / assets / cache + 卷容量；「清理缓存」确认后真实删除启动器缓存 |
| 下载源 | 官方 / 镜像，写入设置并真实影响后续下载（见 BACKEND 第 3 节） |
| 社区资源 | Modrinth 六类浏览 + 详情；单文件安装到实例对应目录；世界 zip 解压到 `saves/` |
| 整合包 | `.mrpack` 安装（基础版本 → Fabric/Quilt → 实例 → 清单 → overrides）；本地导入；Forge 明确报错 |
| 导入整合包（跨页） | 消费 `pendingDownloadAction == "import-modpack"` 后打开文件选择器 |

### SettingsPage（设置）

| 分类 | 真实交互 |
|---|---|
| 启动 | 目录选择器 / 打开目录 / 版本隔离（真实目录预览）/ 最小化 / 启动前检查更新（真实生效） |
| Java | 真实扫描列表、手动路径探针（存在 / 可执行 / `java -version`）、自动 vs 手动、打开 Java 目录 |
| 性能 | 内存上限按物理内存计算、推荐值一键应用、`-Xmx` 冲突提示、JVM 参数计数、渲染线程 |
| 更新与语言 | 真实 HTTP 检查更新（可填更新源，6 种状态）、旧版本清理（真实扫描/删除，父版本依赖保护）、三语切换（仅本页即时生效，其余页面中文）+ 真实重启 |
| 外观 | 主题用分段控件直接切换（石墨 / 瓷白，点一下立即生效）/ 边框强度 / 圆角即时生效，当前 vs 默认对比 |
| 账户（正版） | 微软设备码登录面板（大字验证码 / 复制 / 打开浏览器 / 倒计时 / 内联失败重试 + 帮助链接）、多账户切换 / 刷新登录 / 退出登录；「当前账户」行的「切换」菜单可回到离线账户；分类右上徽标与副标题跟随当前账户（正版 / 离线） |
| 账户（离线） | 玩家名校验（非法不写回）、已保存玩家名切换 / 删除、离线 UUID 复制；正版账户选中时提示离线名只在离线启动生效 |
| 关于 | 真实版本 / 构建号 / 构建时间 / git 提交、检查更新、打开日志 |
| 日志与诊断 | 复制最近日志、导出日志文件、跳转更多·日志、清空需确认、显示行数与退出码 |
| 保存条 | 显示真实 `lastSavedAt`；「保存设置」落盘 CFPreferences；「恢复默认」只重置**当前分类**的设置项（对话框标题带分类名，如"恢复「外观」的默认设置？"），实例 / 账户 / 启动历史等数据保留；日志与诊断分类没有可重置项时给出提示 |

### MorePage（更多）

| 分区 | 真实交互 |
|---|---|
| 日志与诊断 | 真实日志控制台（自动滚动）/ 复制全部 / 复制最近 100 行 / 复制诊断信息 / 清空确认 / 导出日志文件并在访达显示 |
| 实例备份 | `ditto` 真实打包到 `backups/`；列表（名字 / 大小 / 日期）；恢复（确认）/ 删除（废纸篓）/ 显示 / 复制路径 |
| 模组管理 | 实例选择 + 真实扫描 `mods/`；启用 / 禁用即改名；删除（确认 + 废纸篓）；搜索 / 排序 / 统计 |
| 截图相册 | 真实扫描 + 受限解码缩略图；预览 / 访达 / 删除（确认）/ 复制路径 |
| 社区与资源 | Modrinth / CurseForge / Minecraft 官网外链（真实打开、复制链接） |
| 快捷键 | 只列真实注册的快捷键，标注作用范围 |
| 关于 | 真实构建信息、已安装版本数 / Java 数、检查更新、设计系统画廊 |
| 快捷操作 | 打开游戏目录 / 实例 / versions / backups / mods / screenshots / 日志 / 缓存目录；导出日志；重置窗口布局（真实 NSWindow） |
| 工具收藏 | `@AppStorage` 持久化，收藏置顶 + 星标 + 计数 |

## 4. 实现规则（新增交互时请遵守）

- **不要留死按钮**：每个可点控件的 action 必须产生真实效果（文件 / 网络 / 进程 / 设置写入 / 导航 / 通过 router 提示）。确实不可用时必须 `isDisabled` 并在 `subtitle`/`tooltip` 写明原因。
- **危险操作**：删除、恢复、清空、恢复默认一律 `router.showDialog` 二次确认；删除文件走 `InstanceActions.trash`（废纸篓）。
- **状态机**：加载态、错误态、空态都要有；失败必须给出原因与重试入口，不能假成功、不能假 sleep。
- **离屏快照兼容**：`@Environment(\.launcherSnapshotMode)` 为 true 时不得启动异步读盘 / 网络 / 图片解码，用确定性静态值；磁盘统计等允许一次性同步统计。
- **跨页跳转**：通过 `router.go(..., moreSection:/settingsSection:)` 或 `pendingXxxAction`，目标页消费后置 `nil`。
- **视觉**：只用 `theme.colors.*` / `LauncherSpace` / `LauncherRadius` / `LauncherTextStyle` 与现有组件；禁止硬编码色值、投影、模糊、渐变。
- **最小窗口**：1080×720 下四个页面首屏不出现纵向滚动；分区内容超限就折叠（`LauncherExpander`）或拆分区，而不是整页长滚动。
- **可测试**：网络与文件逻辑拆到 `Features/<Area>/` 下的纯逻辑 / 服务层，用 `URLProtocol` stub 或真实临时目录写单测。

## 5. 可复用资产

| 名称 | 说明 |
|---|---|
| `LauncherPageLayout(sideWidth:)` | 页面骨架：左面板 + 右内容 |
| `LauncherSidePanel` / `LauncherSidePanelGroup` | 左列表面板：标题/计数/搜索/工具槽/底部固定区 + 分组标题 |
| `LauncherMainPanel` / `LauncherPanelHeader` | 右内容容器与页头 |
| `LauncherCard` / `GlassPanel` | 平面面板 |
| `LauncherBlockArt(seed:cornerRadius:label:)` | 方块网格封面占位（可复现） |
| `LauncherInlineStat` / `LauncherMonoText` / `LauncherKeyValueRow` | 紧凑信息 |
| `LauncherButton` / `LauncherIconButton` / `LauncherMenuButton` / `LauncherIconMenu` / `.launcherContextMenu` | 按钮与菜单 |
| `LauncherTextField` / `LauncherSearchField` / `LauncherTextArea` / `LauncherNumberField` / `LauncherSlider` / `LauncherToggle` / `LauncherCheckbox` / `LauncherDropdown` / `LauncherSegmentedControl` | 输入与选择 |
| `LauncherListRow` / `LauncherSectionHeader` / `LauncherSettingRow` / `LauncherEmptyState` / `LauncherBanner` / `LauncherProgressBar` / `LauncherAvatar` / `LauncherChip` / `LauncherBadge` | 展示与反馈 |
| `LauncherRouter` / `LauncherOverlayHost` | 全局交互层（见第 2 节） |

`LauncherDemoData` 已删除：启动器四个页面全部使用真实状态，设计系统画廊的示例数据由各画廊页面就地声明。
