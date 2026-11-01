# LauncherUI 组件 API 契约（v1）

> 本文件是**唯一事实来源**。所有组件与画廊页必须严格按此签名实现/调用。
> 工作目录：`/Volumes/Files/Project/LauncherAll`（Swift Package，macOS 15+，SwiftUI）。
> 产品：**Minecraft 启动器**（多主题 + 毛玻璃）。
> 语言：注释与文案用中文；图标只用 SF Symbols（禁止 emoji）。

---

## 0. 铁律（违反即返工）

1. **只改自己被分配的文件**，不要动 `Package.swift`、`Sources/LauncherUI/Core/*`、`Sources/MCLauncher/*`。
2. **不要运行 `swift build`**（多人共享 `.build` 会互相踩）。语法自检用：
   `xcrun swiftc -parse -sdk $(xcrun --show-sdk-path) -target arm64-apple-macos15.0 Sources/LauncherUI/Components/你的文件.swift`
   或者 `swiftc -parse` 同参数（只解析，不检查跨文件类型）。
3. **禁止硬编码颜色/字号/间距/圆角**：颜色只能来自 `theme.colors.*`，字号只能 `.textStyle(...)`，间距 `LauncherSpace.*`，圆角 `LauncherRadius.*`，控件高度 `LauncherControl.*`。
4. **禁止 `#Preview`**（SPM 无 Xcode 预览环境，且会引入编译风险）。需要看效果由 Lead 离屏渲染截图。
5. 组件必须 **主题无关**：只依赖 `theme.colors / theme.primaryGradient / theme.isDark`，不得假设某个具体主题。
6. 动效：`LauncherMotion.*`，并尊重 `@Environment(\.accessibilityReduceMotion)`（可用 Lead 提供的 `.launcherAnimation(_:value:)` 包裹）。
7. 可点击元素的 hover 用 `.launcherHoverEffect()` 或 `.launcherPointer()`；图标按钮必须 `.accessibilityLabel(...)`。
8. 所有 public 类型/方法写中文 `///` 注释一句话说明用途。不加 `public` 的辅助类型默认 `private`。
9. 不要引入第三方依赖、不要读写文件、不要网络。
10. 文件必须**自包含**：只 import SwiftUI（需要光标才可 import AppKit），不引用其他同伴文件里没写在契约中的类型。

---

## 1. 已就绪的核心 API（Lead 已写好并编译通过）

### 1.1 主题环境
```swift
@Environment(\.launcherTheme) private var theme   // LauncherTheme
```
```swift
// LauncherTheme 可用属性
theme.id / theme.name / theme.tagline        // String
theme.isDark                                 // Bool（深色主题为 true）
theme.scheme                                 // ColorScheme
theme.primaryGradient                        // LinearGradient（accent → accentAlt）
theme.swatch                                 // [Color] 三色色板

// LauncherColors：全部语义色，均已烘焙透明度，直接使用
theme.colors.canvas
theme.colors.surface              // 玻璃填充（常规层）
theme.colors.surfaceElevated      // 更实表面（浮层/侧栏）
theme.colors.surfaceSubtle        // 内凹槽（输入框/轨道）
theme.colors.surfaceHover
theme.colors.surfaceActive
theme.colors.stroke               // 1px 细描边
theme.colors.strokeStrong         // 强调描边/选中边框
theme.colors.textPrimary / .textSecondary / .textTertiary
theme.colors.accent / .accentAlt / .onAccent / .accentSoft
theme.colors.success / .warning / .danger / .onDanger
theme.colors.focusRing / .shadow
```

### 1.2 刻度
```swift
LauncherSpace.xxs(2) .xs(4) .sm(8) .md(12) .lg(16) .xl(24) .xxl(32) .xxxl(48)
LauncherRadius.sm(8) .md(12) .lg(16) .xl(22) .xxl(28) .pill(999)
LauncherControl.small(28) .medium(34) .large(44) .icon(34)
LauncherMotion.fast(0.12) .base(0.2) .slow(0.32) .spring .smooth   // spring/smooth 是 Animation，其余是 Double
enum GlassLevel { subtle, regular, strong }
```

### 1.3 文字
```swift
// 角色：display title sectionTitle headline body bodyStrong caption micro label mono monoSmall
// 语义色：primary secondary tertiary accent onAccent success warning danger
Text("x").textStyle(.body, tone: .secondary)
LauncherLabel("分组标题")                       // 10pt 全大写 + 字距
LauncherMonoText("1.21.4", tone: .secondary)     // 等宽
```

### 1.4 玻璃 / 交互
```swift
GlassPanel(level: .regular, cornerRadius: LauncherRadius.lg, padding: LauncherSpace.lg) { ... }
view.glassBackground(level: .subtle, cornerRadius: LauncherRadius.md)
view.launcherHoverEffect(scale: 1.008)      // hover 提亮+上浮+手型光标
view.launcherPointer()
view.launcherFocusRing(isFocused, cornerRadius:)
view.launcherAnimation(.easeInOut(duration: 0.2), value: someEquatable)
```

### 1.5 页面骨架（画廊页必须用）
```swift
LauncherPageScaffold(title: "按钮", subtitle: "说明文字") { ... }   // 已含 ScrollView + 页头 + 最大宽度
LauncherSection("分组名", subtitle: "可选说明") { ... }
LauncherDemoRow("标签") { 控件 }                       // 左侧 96pt 说明 + 右侧内容
LauncherDemoGrid(minWidth: 200) { ForEach... }         // 自适应网格
LauncherPageHeader(title: String, subtitle: String?, trailing: { ... })
```

### 1.6 主题管理器（只有 ThemeStudioPage 会用）
```swift
@Environment(LauncherThemeManager.self) private var themeManager
themeManager.presets            // [LauncherTheme] 6 套
themeManager.themeID            // 当前 id（String）
themeManager.select(_ id: String)
themeManager.glassIntensity     // Double 0.4...1.6，可直接绑定
themeManager.cornerScale        // Double 0.6...1.4，可直接绑定
```
> 根视图与离屏渲染都会注入，页面内可安全读取。

---

## 2. 控件契约（实现者：严格照抄签名）

### 2.1 `Components/Buttons.swift`（负责人 A）
```swift
public enum LauncherButtonVariant { case primary, secondary, ghost, danger }
public enum LauncherButtonSize { case small, medium, large }

public struct LauncherButton: View {
    public init(
        _ title: String,
        systemImage: String? = nil,
        variant: LauncherButtonVariant = .primary,
        size: LauncherButtonSize = .medium,
        isLoading: Bool = false,
        isFullWidth: Bool = false,
        isDisabled: Bool = false,
        shortcut: String? = nil,          // 右下角小提示，例如 "⌘↩"
        action: @escaping () -> Void
    )
}

public struct LauncherIconButton: View {
    public init(
        systemImage: String,
        variant: LauncherButtonVariant = .ghost,
        size: LauncherButtonSize = .medium,
        accessibilityLabel: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    )
}
```
视觉要求：
- primary：`theme.primaryGradient` 填充 + `onAccent` 文字 + 外发光（`theme.colors.accent.opacity(0.28)`，radius 12，y 6）+ 顶部高光描边。
- secondary：`theme.colors.surface` 底 + `theme.colors.stroke` 1px 边 + `textPrimary` 文字；hover 提亮为 `surfaceHover`。
- ghost：透明底 + `textSecondary` 文字，hover 出现 `surfaceHover` 底。
- danger：`theme.colors.danger` 填充 + `onDanger` 文字。
- 尺寸高度：small 28 / medium 34 / large 44；水平内边距小 10 / 中 16 / 大 22；字号 small=`.caption`、medium=`.bodyStrong`、large=`.headline`；圆角 small=`.sm`、medium=`.md`、large=`.md`。
- `isLoading` 时左侧显示 `ProgressView().controlSize(.small)` 并禁用点击；`isFullWidth` 时 `.frame(maxWidth: .infinity)`。
- 按下 `scaleEffect(0.975)`，hover 轻微提亮，全部走 `LauncherMotion`。

### 2.2 `Components/Chips.swift`（负责人 A）
```swift
public enum LauncherBadgeTone { case neutral, accent, success, warning, danger, info }

public struct LauncherChip: View {
    public init(_ title: String, isSelected: Bool = false, systemImage: String? = nil, action: @escaping () -> Void)
}

public struct LauncherBadge: View {
    public init(_ text: String, tone: LauncherBadgeTone = .neutral, systemImage: String? = nil)
}

public struct LauncherStatusDot: View {
    public init(tone: LauncherBadgeTone = .success, isPulsing: Bool = false)
}
```
- Chip：胶囊（`LauncherRadius.pill`），选中态用 `theme.colors.accentSoft` 底 + `theme.colors.accent` 1px 边 + `accent` 文字；未选中 `surface` 底 + `textSecondary`；高度 26。
- Badge：11pt、胶囊、背景 `toneColor.opacity(0.14)`、文字 toneColor；neutral 用 `surfaceHover` + `textSecondary`。
- StatusDot：6pt 圆点，`isPulsing` 时用 `repeatForever` 呼吸动画（reduceMotion 时关闭）。

### 2.3 `Components/Feedback.swift`（负责人 A）
```swift
public enum LauncherProgressTone { case accent, success, warning, danger }
public enum LauncherBannerTone { case info, success, warning, danger }

public struct LauncherProgressBar: View {
    public init(value: Double? = nil, label: String? = nil, tone: LauncherProgressTone = .accent, height: CGFloat = 6)
    // value == nil 表示不确定进度（循环光带）
}

public struct LauncherSpinner: View {
    public init(size: CGFloat = 16, tone: LauncherProgressTone = .accent)
}

public struct LauncherSkeleton: View {
    public init(width: CGFloat? = nil, height: CGFloat = 12, cornerRadius: CGFloat = LauncherRadius.sm)
}

public struct LauncherBanner: View {
    public init(title: String, message: String, tone: LauncherBannerTone = .info, actionTitle: String? = nil, onAction: (() -> Void)? = nil)
}

public struct LauncherToast: View {
    public init(title: String, message: String, tone: LauncherBannerTone = .success, onDismiss: (() -> Void)? = nil)
}
```
- 进度条：轨道 `theme.colors.surfaceSubtle`，填充 tone 色（accent 用 `theme.primaryGradient`）；高度默认 6，胶囊端；label 用 `.caption` 左侧、百分比右侧 `LauncherMonoText`。
- Spinner：环形渐变旋转（`AngularGradient`）+ `repeatForever`，reduceMotion 时降级为静态三点？**简单做法**：reduceMotion 时用静态 `ProgressView`。
- Skeleton：`theme.colors.surfaceHover` 底 + 从左到右的 shimmer 高光（`LinearGradient` 动画），reduceMotion 时静态。
- Banner：玻璃底 + 左侧 tone 色竖条 3pt + 图标（info=info.circle.fill / success=checkmark.circle.fill / warning=exclamationmark.triangle.fill / danger=xmark.octagon.fill）。
- Toast：`GlassPanel(level: .strong)` + 左侧状态图标 + 标题/正文 + 关闭按钮（xmark，`.accessibilityLabel("关闭")`）。

### 2.4 `Components/Inputs.swift`（负责人 B）
```swift
public struct LauncherTextField: View {
    public init(_ placeholder: String, text: Binding<String>, systemImage: String? = nil,
                helper: String? = nil, error: String? = nil, isDisabled: Bool = false,
                onSubmit: (() -> Void)? = nil)
}

public struct LauncherSearchField: View {
    public init(text: Binding<String>, placeholder: String = "搜索版本、整合包或服务器", onSubmit: (() -> Void)? = nil)
}

public struct LauncherSecureField: View {
    public init(_ placeholder: String, text: Binding<String>, systemImage: String? = nil)
}

public struct LauncherTextArea: View {
    public init(_ placeholder: String, text: Binding<String>, minHeight: CGFloat = 90)
}
```
- 输入框：高 34（`LauncherControl.medium`），`theme.colors.surfaceSubtle` 底 + `theme.colors.stroke` 1px 边，圆角 `LauncherRadius.md`；聚焦时边框变 `theme.colors.focusRing` + 2pt 外环（opacity 0.35）；`error` 非空时边框 `danger` 并在下方显示 error（`.micro` danger）；`helper` 在无 error 时显示（`.micro` tertiary）；`isDisabled` 降透明度 0.5。
- 用 `TextField("", text:).textFieldStyle(.plain)` + 自定义底；placeholder 用 overlay 自绘（不能用系统 placeholder 颜色）。
- SearchField：左侧放大镜，右侧有内容时显示清除按钮（xmark.circle.fill），回车触发 onSubmit。
- TextArea：`TextEditor` 去背景（`.scrollContentBackground(.hidden)`），placeholder overlay。

### 2.5 `Components/Selection.swift`（负责人 B）
```swift
public struct LauncherToggle: View {
    public init(_ title: String, isOn: Binding<Bool>, subtitle: String? = nil)
}

public struct LauncherCheckbox: View {
    public init(_ title: String, isOn: Binding<Bool>)
}

public struct LauncherRadioCard: View {
    public init(_ title: String, subtitle: String? = nil, systemImage: String? = nil,
                isSelected: Bool, action: @escaping () -> Void)
}

public struct LauncherSlider: View {
    public init(value: Binding<Double>, range: ClosedRange<Double> = 0...1,
                label: String? = nil, valueText: String? = nil)
}

public struct LauncherSegment<Value: Hashable>: Identifiable {
    public let id: Value
    public let title: String
    public let systemImage: String?
    public init(id: Value, title: String, systemImage: String? = nil)
}

public struct LauncherSegmentedControl<Value: Hashable>: View {
    public init(options: [LauncherSegment<Value>], selection: Binding<Value>)
}

public struct LauncherDropdown<Value: Hashable>: View {
    public init(options: [LauncherSegment<Value>], selection: Binding<Value>, placeholder: String = "请选择")
}

public struct LauncherStepper: View {
    public init(value: Binding<Int>, range: ClosedRange<Int> = 1...64, label: String? = nil, unit: String? = nil)
}
```
- Toggle：自绘胶囊 44×26（on=`theme.colors.accent` + 白色圆点右移；off=`surfaceActive` 圆点左移），`.animation(.spring) `；右侧文字 + 可选 subtitle（.micro tertiary）。
- Checkbox：18×18 圆角 5，选中 = accent 底 + 白色 checkmark，未选中 = surfaceSubtle + stroke。
- RadioCard：玻璃卡（`.glassBackground(level: .subtle)`）+ 左侧圆形单选点 + title/subtitle，选中时边框 `accent`、底加 `accentSoft`。
- Slider：自绘 track 4pt + 14pt 白色拇指 + 左侧 label、右侧 valueText（`.mono`）；用 `DragGesture` 计算比例（`GeometryReader`），不要用系统 Slider。
- SegmentedControl：胶囊容器 `surfaceSubtle` 内衬，选中项用 `surfaceElevated` + 阴影滑动（matchedGeometryEffect 可选，不强制）。
- Dropdown：按钮显示当前项 + chevron；点击弹 `Menu`（系统 Menu 便于键盘可达），选项带 checkmark。
- Stepper：`- 值 +` 的胶囊控件，数值 `.mono`，到达边界禁用。

### 2.6 `Components/Surfaces.swift`（负责人 C）
```swift
public struct LauncherCard<Content: View>: View {
    public init(level: GlassLevel = .regular, padding: CGFloat = LauncherSpace.lg, @ViewBuilder content: @escaping () -> Content)
}

public struct LauncherCardHeader: View {
    public init(title: String, subtitle: String? = nil, systemImage: String? = nil, accessory: AnyView? = nil)
}

public struct LauncherListRow: View {
    public init(title: String, subtitle: String? = nil, systemImage: String? = nil, badge: String? = nil,
                accessory: AnyView? = nil, isSelected: Bool = false, action: (() -> Void)? = nil)
}

public struct LauncherSectionHeader: View {
    public init(title: String, subtitle: String? = nil, accessory: AnyView? = nil)
}

public struct LauncherEmptyState: View {
    public init(systemImage: String, title: String, message: String, actionTitle: String? = nil, onAction: (() -> Void)? = nil)
}

public struct LauncherAvatar: View {
    public init(name: String, systemImage: String? = nil, size: CGFloat = 32, isOnline: Bool = false)
}

public struct LauncherKeyValueRow: View {
    public init(key: String, value: String, isMono: Bool = true)
}

public struct LauncherStatTile: View {
    public init(value: String, label: String, systemImage: String? = nil)
}

public struct LauncherDivider: View {
    public init()
}
```
- Card = GlassPanel 包装 + 可选内容；ListRow：44 高、hover 出现 `surfaceHover`、圆角 `md`、选中态左侧 3pt accent 竖条 + `accentSoft` 底；systemImage 放在 28×28 的 `surfaceSubtle` 圆角方块里；badge 用 `LauncherBadge`（C 可直接调用 A 的类型）。
- SectionHeader：标题 `.sectionTitle` + 可选 subtitle `.micro` + 右侧 accessory。
- EmptyState：居中 48pt 图标（accent，opacity 0.7）+ 标题 + 说明 + 可选按钮。
- Avatar：圆形渐变底（`theme.primaryGradient` 低饱和或 surfaceElevated）+ 名字首字母（中文取第一个字）；右下角在线小绿点。
- KeyValueRow：左 `.caption` secondary、右 `.mono`/`.bodyStrong` primary。
- StatTile：数值 `.title` + 标签 `.micro` tertiary，玻璃卡。

### 2.7 `Components/Navigation.swift`（负责人 C）
```swift
public struct LauncherNavItem: Identifiable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let badge: String?
    public init(id: String, title: String, systemImage: String, badge: String? = nil)
}

public struct LauncherSidebarItem: View {
    public init(_ item: LauncherNavItem, isSelected: Bool, action: @escaping () -> Void)
}

public struct LauncherSidebar: View {
    public init(items: [LauncherNavItem], selection: Binding<String>,
                header: AnyView? = nil, footer: AnyView? = nil)
}

public struct LauncherTabBar: View {
    public struct Tab: Identifiable { public let id: String; public let title: String; public let systemImage: String? }
    public init(tab: [LauncherTabBar.Tab], selection: Binding<String>)   // 注意参数名是 tab
}
```
> 若 `tab:` 参数名在实现时更自然，可以改成 `tabs:`，**但必须同时在本文件末尾“实现偏差”里记录并通知 Lead**。默认请用 `tabs:`，Lead 会按 `tabs:` 调用 → **最终定稿：`public init(tabs: [Tab], selection: Binding<String>)`**。
```swift
public struct LauncherDialog: View {
    public enum Tone { case primary, danger }
    public init(title: String, message: String, primaryTitle: String, secondaryTitle: String? = nil,
                tone: Tone = .primary, onPrimary: @escaping () -> Void, onSecondary: (() -> Void)? = nil)
}
```
- Sidebar 项：高 34、圆角 `md`、选中 = `accentSoft` 底 + accent 图标/文字 + 左侧 3pt 高亮条；hover = `surfaceHover`；badge 右侧胶囊数字。
- Sidebar 容器：`theme.colors.surfaceElevated` 玻璃底 + 右侧 1px `stroke` 分割；分组间距 `lg`。
- TabBar：一行胶囊 tab，选中下划线/填充（用 `accentSoft` + accent 文字）。
- Dialog：`.strong` 玻璃浮层卡片（宽 380），标题/正文/主次按钮；danger 时主按钮用 danger 色。

---

## 3. 画廊页面契约（负责人 D / E）

每个页面文件只包含：`public struct XxxPage: View { public init() {} public var body: some View }`，
必须使用 `LauncherPageScaffold`，**只用契约中列出的组件**，示例数据就地写在文件内（不要跨文件引用）。

页面清单与必展内容：
| 文件 | 结构体 | 必展内容 |
|---|---|---|
| `Gallery/ButtonsPage.swift` | `ButtonsPage` | 4 变体 × 3 尺寸矩阵；带图标/加载/禁用/全宽/快捷键；icon button 三种尺寸；Chip 组（3 个一组，含选中态）；Badge 6 种 tone；StatusDot 三种 |
| `Gallery/InputsPage.swift` | `InputsPage` | 普通/带图标/带 helper/错误态/禁用；搜索框（含已输入内容）；密码框；多行文本；一组真实感表单（版本文件夹路径 + 内存分配步进器 + 复选框） |
| `Gallery/SelectionPage.swift` | `SelectionPage` | Toggle 组合（含 subtitle）；Checkbox 组；RadioCard 三选一（Java 运行时选择）；Slider（玻璃浓度/视距 two examples）；SegmentedControl；Dropdown；Stepper |
| `Gallery/SurfacesPage.swift` | `SurfacesPage` | 三层玻璃卡对比；ListRow（普通/选中/带 badge/带 accessory）；SectionHeader；EmptyState；Avatar（在线/离线）；KeyValueRow 组；StatTile 三连；Divider |
| `Gallery/FeedbackPage.swift` | `FeedbackPage` | 进度条 4 tone（含不确定）；Spinner 3 尺寸；Skeleton 卡片占位布局；Banner 4 tone；Toast 成功/警告两条 |
| `Gallery/NavigationPage.swift` | `NavigationPage` | Sidebar 完整示意（用 `LauncherSidebar` 绑定本地 @State）；TabBar；LauncherDialog 示意；组合成一个“设置页”分栏缩略 |
| `Gallery/LauncherDemoPage.swift` | `LauncherDemoPage` | **Minecraft 启动器实战样张**：版本选择 + 启动大按钮 + 账户/实例列表 + 下载进度 + 新闻卡片，用玻璃卡组合成一个真实启动器首屏（下方再放一段“已安装实例”列表） |

页面内部布局建议（保证一致性）：
- 页面级间距 `LauncherSpace.xl`，区块内 `LauncherSpace.md`。
- 组件并排用 `HStack(spacing: LauncherSpace.md)` + `Spacer()` 或 `LauncherDemoGrid`。
- 需要 @State 的交互示例（Toggle、Slider、Segmented 等）用页面内 `@State` 变量。

---

## 4. 交付与回报

实现完成后，给 Lead 发一条消息，包含：
1. 已创建文件清单。
2. 与契约的**任何偏差**（签名/命名/行为）——没有写“无”。
3. 你无法验证但担心的点（例如某 API 在 macOS 15 的可用性）。

Lead 负责统一编译、修复与截图验收。**不要**自行修改他人文件或 Core。
