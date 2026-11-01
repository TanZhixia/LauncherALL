# 方块启动器 · 主界面（UI）说明

> 目标：**只做 UI**，不含版本解析、下载、Java 检测等真实逻辑。所有数据来自 `LauncherDemoData`，
> 交互用页面内 `@State` 模拟。视觉规则见 [`DESIGN-SYSTEM.md`](DESIGN-SYSTEM.md)（简约 / 平面化 / 一深一浅两套主题）。

## 1. 结构

```
LauncherAppShell（窗口壳：顶部导航栏 + 内容区）
├─ 导航栏：品牌 v0.2.0 ｜ [启动 ⌘1] [下载 ⌘2] [设置 ⌘3] [更多 ⌘4] ｜ 主题切换 ｜ 账户胶囊 ｜ 设置图标
└─ 内容区（按 tab 切换，淡入过渡）
   ├─ LaunchPage      启动：当前实例 / 快速开始 / 实例列表 / 账户·服务器·公告
   ├─ DownloadPage    下载：搜索筛选 / 版本列表 / 下载队列 / 磁盘占用
   ├─ SettingsPage    设置：启动 / Java / 性能 / 更新 / 外观 / 账户 / 关于
   └─ MorePage        更多：工具卡 / 快捷操作 / 快捷键 / 关于
```

设计器入口：`更多 → 打开设计系统` 以 sheet 打开 `LauncherShellView`（既有组件画廊）。

## 1.1 二级导航（每个一级页面内）

每个一级页面内部再放一条**竖排分区导航**，一次只显示一个分区；
目标是 **最小窗口 1080×720 下不需要纵向滚动**（内容区可用高度约 560pt）。

```swift
LauncherSectionLayout {
    LauncherSectionRail(items: sections, selection: $section, header: "设置")
} content: {
    switch section { case "java": javaSection; default: generalSection }
}
```

| 一级页面 | 分区 |
|---|---|
| 启动 | 概览 / 实例 / 账户与社区 |
| 下载 | 版本库 / 整合包 / 下载任务 |
| 设置 | 启动 / Java / 性能 / 更新 / 外观 / 账户 / 关于 |
| 更多 | 工具 / 快捷操作 / 快捷键 / 关于 |

分区内容要求：单个分区高度 ≤ 540pt（宽度约 820pt），超出就再拆一个分区，而不是让它滚动。

## 2. 可复用资产（Lead 已写好）

### 页面容器
```swift
LauncherAppPage {            // ScrollView + 最大宽度 1220 + 统一 padding，自动兼容离屏渲染
    LauncherPageHeader(title: "下载", subtitle: "安装游戏版本、加载器与整合包")   // 无 trailing 的简便构造
    ...
}
```

### 共享组件（`Sources/LauncherUI/Launcher/`）
| 名称 | 说明 |
|---|---|
| `LauncherBlockArt(seed:cornerRadius:label:)` | 方块网格封面占位（可复现，同一 seed 同一图案） |
| `LauncherInlineStat(_:value:isMono:)` | 小标签 + 数值的紧凑信息 |
| `LauncherAccountChip()` | 账户胶囊（头像 + 名字 + 在线点） |
| `LauncherTabButton(tab:isSelected:action:)` | 顶部导航项（壳内部用，页面无需调用） |
| `LauncherAppPage` | 页面骨架 |

其余全部复用设计系统：`LauncherCard` / `GlassPanel` / `LauncherSectionHeader` / `LauncherListRow` /
`LauncherButton` / `LauncherIconButton` / `LauncherChip` / `LauncherBadge` / `LauncherToggle` /
`LauncherSlider` / `LauncherStepper` / `LauncherSegmentedControl` / `LauncherDropdown` /
`LauncherTextField` / `LauncherSearchField` / `LauncherTextArea` / `LauncherProgressBar` /
`LauncherStatTile` / `LauncherKeyValueRow` / `LauncherEmptyState` / `LauncherBanner` / `LauncherDialog` /
`LauncherAvatar` / `LauncherMonoText` / `LauncherLabel` / `.textStyle(...)`。

### 演示数据（`LauncherDemoData.swift`）
```swift
LauncherDemoData.account          // LauncherAccount(name/type/lastLogin/isOnline)
LauncherDemoData.currentInstance  // LauncherInstance
LauncherDemoData.instances        // [LauncherInstance] 4 个
LauncherDemoData.versions         // [LauncherVersionItem] 6 个（kind: 正式版/快照/加载器/整合包；state: available/installing/installed）
LauncherDemoData.downloadTasks    // [LauncherDownloadTask] 3 个（progress 可选？nil = 不确定态）
LauncherDemoData.news / servers / tools / shortcuts / javaRuntimes / versionDirectory
```

## 3. 页面契约

### DownloadPage（下载）
1. 页头：`LauncherPageHeader(title: "下载", subtitle: "安装游戏版本、加载器与整合包")`，trailing 放两个 secondary 小按钮（打开文件夹 / 刷新列表）。
2. 搜索与筛选：`LauncherSearchField` + 一排 `LauncherChip`（全部 / 正式版 / 快照 / 加载器 / 整合包，可筛选列表）+ 右侧 `LauncherDropdown` 排序（按发布时间 / 版本号 / 大小）。
3. 版本列表（左，占满剩余宽度）：`LauncherCard` + `LauncherSectionHeader`（标题「版本列表」+ 数量/筛选状态）+ 逐行 `LauncherListRow`：
   - title = 版本号；subtitle = 发布日期 + note；systemImage 按 kind 区分（正式版 globe、快照 flask、加载器 wrench、整合包 shippingbox）；
   - badge = kind；accessory = 状态区：未安装 → small primary「安装」；安装中 → `LauncherProgressBar`（宽 90）+ 百分比；已安装 → secondary「已安装」。
   - 点安装：把该条 state 改成 `.installing(0)`，用 `Task` + `sleep` 每 0.6s 增加 0.15 到 1 后变 `.installed`（纯 UI 模拟）。
4. 右栏（宽 318）：
   - 下载队列卡：标题「下载队列」，列出 `downloadTasks`，每条 = 标题/说明 + `LauncherProgressBar` + 速度/总量 mono + 暂停/取消 icon 按钮；不确定态用 `progress: nil`。
   - 磁盘占用卡：`LauncherStatTile` 或 `LauncherKeyValueRow`（已用 14.9 GB / 可用 84.2 GB / 实例 4 个）+ secondary「清理缓存」按钮。
   - 下载源卡：`LauncherDropdown`（官方 / 镜像）+ `LauncherToggle`（自动清理旧版本）。
5. 交互用页面内 `@State`（筛选、排序、installing 状态、暂停态），不要引入真实网络逻辑。

### SettingsPage（设置）
用 `LauncherAppPage` + 若干 `LauncherCard`（每张卡一个 `LauncherSectionHeader`），顺序：
1. **启动**：游戏目录（`LauncherTextField` + secondary「浏览…」）、`LauncherToggle` 版本隔离、`LauncherToggle` 启动后最小化、`LauncherCheckbox` 启动前检查更新。
2. **Java 运行时**：三个 `LauncherRadioCard`（用 `LauncherDemoData.javaRuntimes`，选中态用 `@State selectedJava`）、路径 `LauncherMonoText`、`LauncherButton` secondary「重新检测」+ 说明文案。
3. **性能**：`LauncherSlider` 最大内存（1024–8192，valueText `"\(Int(memory)) MB"`）+ mono 建议值；`LauncherStepper` 渲染线程；`LauncherTextArea` JVM 参数（minHeight ≥ 80，helper「每行一个参数」）。
4. **更新与语言**：`LauncherSegmentedControl` 更新通道（正式版 / 快照 / 预览）、`LauncherDropdown` 语言（简体中文 / English / 日本語）。
5. **外观**：主题选择（两套主题用 `LauncherRadioCard` 或自绘色块行，选中调 `themeManager.select(...)`）、`LauncherSlider` 边框强度（绑定 `themeManager.borderStrength`，范围 0.4…1.6）、`LauncherSlider` 圆角缩放（`cornerScale`，0.6…1.4）。
6. **账户**：`LauncherAvatar` + 名称/类型 + secondary「切换账户」/“退出登录”。
7. **关于**：版本 / 构建 / 提交（mono 三行 keyvalue）+ secondary「检查更新」「打开日志」。
8. 底部操作条：`LauncherCard` 内 primary「保存设置」+ secondary「恢复默认」+ 右侧「所有修改会自动保存」mono 提示；点击保存后把提示改成「已保存于 刚刚」并短暂变 success 色（`@State saved`）。

### MorePage（更多）
`public init(onOpenGallery: @escaping () -> Void = {})` —— 必须保留这个初始化签名。
1. 页头：`LauncherPageHeader(title: "更多", subtitle: "工具、备份、日志与设计资源")`，trailing = secondary「打开设计系统」→ 调用 `onOpenGallery()`。
2. 工具网格：`LauncherDemoData.tools` 六个工具卡，`LazyVGrid` 两列；每卡 = 图标（30×30 surfaceSubtle 方块）+ 标题 + 说明 + 可选 badge + 右侧 chevron，`.launcherHoverEffect()`。
3. 快捷操作卡：三个按钮（打开 .minecraft 文件夹 / 导出日志 / 重置窗口布局）+ 一行说明。
4. 快捷键卡：`LauncherDemoData.shortcuts` 逐行 `LauncherKeyValueRow`（key = 标题，value = 按键，isMono: true）。
5. 关于卡：`LauncherMonoText` 版本 / 构建 / 提交；`LauncherButton` secondary「检查更新」；一行「基于 SwiftUI 构建 · 设计系统 v0.2」；再加一个 secondary「设计系统画廊」按钮（同样调用 onOpenGallery）。
6. 交互：点「导出日志」把 `@State exportHint` 设为「日志已导出到桌面」并用 `LauncherBadge(tone: .success)` 显示 2 秒。

## 4. 实现规则
- **只改自己的页面文件**，不要动 `LauncherAppShell`、`LauncherDemoData`、`Core/`、其他页面。
- 只做 UI：不要真实文件/网络/进程操作；交互用 `@State` 模拟。
- 颜色/字号/间距/圆角只用令牌与现有组件，禁止硬编码十六进制或 `.font(.system(size:))` 自定义字号（组件内部除外）。
- 文本输入类用 `LauncherTextArea` / `LauncherTextField`（已兼容离屏渲染），不要直接用 `TextEditor`。
- 每个 `@State` 都要真正参与渲染；不要留死按钮（没行为的按钮至少给出 hover/选中反馈或提示状态）。
- 中文注释；类型与关键区块上方 `///`。
- 自检：`swift build --scratch-path /tmp/build-<你的名字> 2>&1 | tail -20` 必须 0 error；并用
  `swift run --scratch-path /tmp/build-<你的名字> MCLauncher --export-app-snapshots /tmp/appshots-<你的名字>`
  确认四页都能渲染（Lead 会做最终视觉验收）。
