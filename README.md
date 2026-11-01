# 方块启动器 · Minecraft Launcher（SwiftUI UI 实现）

一套用 **Swift 6 / SwiftUI** 写的 Minecraft 启动器：**顶部导航（启动 / 下载 / 设置 / 更多）** + 极简平面化设计系统（一深一浅两套主题）+ 30 多个控件 + XML 声明式 UI 层。
本仓库当前只做 **UI 层**（不含版本解析、资源下载、Java 检测、账户认证等启动逻辑），所有交互为 UI 级演示。

## 快速开始

```bash
# 直接运行（macOS 15+ / Xcode 26+ / Swift 6）
swift run MCLauncher

# 或用 Xcode 打开 SPM 包，跑 MCLauncher scheme
open Package.swift

# 离屏导出：启动器主界面（2 主题 × 4 导航页）
swift run MCLauncher --export-app-snapshots Snapshots/App

# 离屏导出：设计系统画廊（2 主题 × 9 页）
swift run MCLauncher --export-snapshots Snapshots
python3 tools/make_contact_sheet.py   # 需要 Pillow，生成对比图
```

主界面顶部是四个导航页（⌘1~⌘4 切换）：

| 页面 | 内容 |
|---|---|
| **启动** | 当前实例封面 / 版本与模组信息 / 启动按钮，快速开始、实例列表，右侧账户、服务器状态、公告、Java 提示 |
| **下载** | 搜索 + 类型筛选 + 排序，版本 / 加载器 / 整合包列表（安装进度模拟），下载队列、磁盘占用、下载源设置 |
| **设置** | 启动行为、Java 运行时、内存与渲染线程、更新通道与语言、外观（主题 / 边框强度 / 圆角）、账户、关于 |
| **更多** | 工具卡（日志、备份、模组、截图、社区、关于）、快捷操作、快捷键、版本信息 |

四个一级页面采用 PCL-CE 式「左面板 + 右内容」布局（布局参考 PCL2 社区版源码，控件与视觉全部用本项目 LauncherUI 实现，见 [docs/PCL-CE-REFACTOR.md](docs/PCL-CE-REFACTOR.md)）。每个一级页面内部还有一条**竖排二级导航**（启动：概览/实例/账户与社区；下载：版本库/整合包/下载任务；设置：启动/Java/性能/更新/外观/账户/关于；更多：工具/快捷操作/快捷键/关于），一次只显示一个分区——**最小窗口 1080×720 下无需纵向滚动**。

顶栏右侧可一键切换深/浅主题；「更多 → 打开设计系统」会以 sheet 打开组件画廊与主题工作台。

## 设计取向

- **简约**：中性灰阶 + 单一强调色（深色主题近白、浅色主题近黑），状态色低饱和。
- **平面化**：没有毛玻璃、没有投影、没有渐变、没有发光；层级只由「分层底色 + 1px 边框」表达。
- **两套主题**：`graphite`（深色）/ `porcelain`（浅色），只换色不换结构。
- 详见 [`docs/DESIGN-SYSTEM.md`](docs/DESIGN-SYSTEM.md)。

## 目录结构

```
Sources/
  LauncherUI/                 # 设计系统 + 组件库 + 启动器界面
    Core/                     # 令牌、主题、排版、面板、动效、页面骨架
    Components/               # 按钮 / 输入 / 选择 / 容器 / 反馈 / 导航
    Launcher/                 # ★ 启动器主界面：外壳、导航栏、共享数据与四个页面
    Gallery/                  # 组件画廊 + 主题工作台 + XML 设计器
    Shell/                    # 画廊侧栏外壳
    XML/                      # XML UI 引擎（解析 / 状态 / 动作 / 渲染）
  MCLauncher/                 # 可执行 App 入口 + 各截图导出器 + CLI 工具
docs/
  DESIGN-SYSTEM.md            # 设计系统说明（令牌 / 主题 / 规范 / 检查清单）
  APP-UI.md                   # 启动器主界面结构、页面契约与演示数据
  XML-UI.md                   # XML UI 语言完整语法
  API-CONTRACT.md             # 组件 API 契约
Snapshots/                    # 导出的主题 × 页面效果图 + 对比图（生成产物，已 gitignore）
tools/make_contact_sheet.py   # 生成主题对比图（Pillow）
```

## 效果预览（启动器主界面）

`Snapshots/App/` 下是 2 套主题 × 4 个导航页的离屏渲染图（1440×900 与最小窗口 1080×720 两套）；`Snapshots/sheet-app.png` 是四页对照图，`Snapshots/sheet-app-min.png` 是最小窗口免滚动验收图。

## 效果预览（设计系统）

`Snapshots/` 下是 **2 套主题 × 8 个页面** 的离屏渲染图，另附交付用对比图：

| 对比图 | 内容 |
|---|---|
| `sheet-themes-demo.png` | 同一套启动器首屏在深色 / 浅色主题下的对照（核心验收图） |
| `sheet-themes-studio.png` | 主题工作台 + 跨主题一致性对照 |
| `sheet-buttons.png` / `sheet-inputs.png` / `sheet-selection.png` / `sheet-surfaces.png` / `sheet-feedback.png` | 各组控件在深浅主题下的对照 |
| `sheet-xml.png` | 三份 XML 示例（启动器首屏 / 控件总览 / 设置页）在深浅主题下渲染 + `Snapshots/XML/` 单图 |
| `graphite-xml.png` / `porcelain-xml.png` | XML 设计器页面（左侧源码 / 右侧实时预览） |

> 说明：截图由 `ImageRenderer` 离屏渲染。平面化后面板是真纯色，与真机一致；仅 AppKit 背书的控件（输入框、下拉菜单）在离屏模式下用同布局静态等价物渲染（`launcherSnapshotMode` 环境开关）。

## XML UI 工具链

除了手写 SwiftUI，项目还提供一套 **XML → SwiftUI** 的声明式 UI 层：把控件封装成 XML 标签，运行时解析渲染，主题/间距/圆角完全复用同一套令牌。

```bash
# 1) 校验 XML（打印诊断，退出码 0 = 通过）
swift run MCLauncher --validate-xml Samples/XML/smoke.xml

# 2) 渲染成 PNG（设计评审 / CI 截图）
swift run MCLauncher --render-xml Samples/XML/smoke.xml out.png --theme porcelain --width 1200 --height 900

# 3) 导出全部内置示例 × 主题
swift run MCLauncher --export-xml-snapshots Snapshots/XML
```

App 内在「工具 → XML 设计器」里可以左边改 XML、右边实时预览（含诊断）。

能力概览：
- 布局：`vstack / hstack / zstack / scroll / grid / spacer / divider / panel / card / section / page / if / foreach`
- 基础：`text / label / mono / icon`
- 控件：`button / iconbutton / chip / badge / statusdot / textfield / searchfield / securefield / textarea / toggle / checkbox / radiocard / slider / stepper / segmented / dropdown`
- 容器与导航：`listrow / sectionheader / empty / avatar / keyvalue / stattip / progress / spinner / skeleton / banner / toast / sidebaritem / tabs / dialog`
- 状态与绑定：`<state>` 声明变量，`bind="name"` 双向绑定，`{state.x}` / `{item.y}` 插值，`onTap="动作名"` 或内置 `set:` / `toggle:` / `inc:` 简写。

完整语法与属性表见 [`docs/XML-UI.md`](docs/XML-UI.md)。

## 加一套主题

见 [`docs/DESIGN-SYSTEM.md`](docs/DESIGN-SYSTEM.md) 第 3 节：工厂方法声明 → 加入 `LauncherThemes.all` → 全站自动适配。

## 加一个组件

1. 只用 `theme.colors.*` / `.textStyle(...)` / `LauncherSpace` / `LauncherRadius` / `GlassPanel`，禁止投影、模糊、渐变；
2. Public init 写进 `docs/API-CONTRACT.md`；
3. 在对应 Gallery 页加一组状态展示（默认 / 选中 / 禁用 / 加载 / 错误）。

## 已知边界

- 未接入 Minecraft 启动逻辑（版本清单、资源下载、Java 运行时、账户认证）。
- 未使用官方字体与素材，全部为系统字体 + SF Symbols + 自绘方块图形。
