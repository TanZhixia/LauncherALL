# 方块启动器 · 设计系统（简约 · 平面化）

> 目标：**一套极简的 SwiftUI 令牌 + 组件库**，一深一浅两套主题，靠排版、留白与层级（而非颜色和特效）承载信息。
> 换主题只换色值；结构、间距、控件形态完全不变。

---

## 1. 设计原则

| 原则 | 落地方式 |
|---|---|
| **简约** | 只用中性灰阶 + 一个高对比强调色（深色主题近白 / 浅色主题近黑）；状态色只在必要处出现 |
| **平面化** | 无模糊材质、无投影、无发光、无渐变；层级只由「分层底色 + 1px 边框」表达 |
| **结构优先** | 4pt 间距体系、固定控件高度（28/34/44）、统一圆角刻度；对齐与节奏先于装饰 |
| **少色** | 每屏最多 1 个强调色 + 3 个语义色（成功/警告/危险），且语义色饱和度压低 |
| **克制动效** | 只做状态切换的短过渡（100–160ms），不做装饰性动画，尊重「减弱动效」 |
| **可扩展** | 主题 = 一组语义色；新增主题不需要改任何组件代码 |

**明确不做**：毛玻璃模糊、投影堆叠、渐变球、发光边框、彩虹多主题、emoji 图标、装饰性插画。

---

## 2. 令牌体系（`Sources/LauncherUI/Core/Tokens.swift`）

### 2.1 语义色 `theme.colors.*`
组件禁止硬编码色值，只能消费下列令牌：

| 令牌 | 用途 |
|---|---|
| `canvas` | 页面底色（最底层） |
| `surface` | 常规面板底（卡片、分组） |
| `surfaceElevated` | 浮层面板底（侧栏、弹窗、Toast） |
| `surfaceSubtle` | 内嵌凹槽（输入框、进度轨、segmented 容器） |
| `surfaceHover` / `surfaceActive` | hover / 按下与选中态 |
| `stroke` / `strokeStrong` | 1px 细描边 / 强调描边（选中、hover 边界） |
| `textPrimary` / `textSecondary` / `textTertiary` | 三级文字 |
| `accent` | **唯一强调色**：主按钮、选中、焦点环、进度 |
| `accentAlt` | 强调色次级位（平面化后与 accent 同色） |
| `onAccent` | 强调底上的前景色 |
| `accentSoft` | 选中行/标签的极淡强调底 |
| `success` / `warning` / `danger` / `onDanger` | 语义状态（低饱和） |
| `focusRing` | 键盘焦点环（2pt，永不隐藏） |

hover / active / soft 三态由基色**自动推导**（`Color.mixed(with:amount:)`），新增主题不必手写这些色值。

### 2.2 面板层级 `GlassLevel`
平面化后，层级只看底色与边框（名称保留以兼容调用方）：

| 层级 | 填充 | 描边 | 场景 |
|---|---|---|---|
| `subtle` | `surfaceSubtle` | `stroke` | 输入框、列表底、代码块 |
| `regular` | `surface` | `stroke` | 卡片、分组 |
| `strong` | `surfaceElevated` | `strokeStrong` | 侧栏、弹窗、Toast |

> 所有浮层必须用 `GlassPanel` / `.glassBackground(level:)`，禁止自绘材质/阴影。

### 2.3 刻度
- 间距：`xxs 2 · xs 4 · sm 8 · md 12 · lg 16 · xl 24 · xxl 32 · xxxl 48`
- 圆角：`sm 6 · md 10 · lg 14 · xl 18 · xxl 24 · pill 999`
- 控件高度：`small 28 · medium 34 · large 44 · icon 34`
- 动效：`fast 0.10s · base 0.16s · slow 0.24s`（easeOut / easeInOut）
- 全局乘数：边框强度 `0.4–1.6×`、圆角缩放 `0.6–1.4×`（主题工作台可实时调）

### 2.4 字阶（系统字体，零外部依赖）
| 角色 | 规格 | 用法 |
|---|---|---|
| display | 30 / Bold / Rounded / tracking -0.4 | 页面主标题 |
| title | 22 / Semibold / Rounded | 区块标题、大数字 |
| sectionTitle | 15 / Semibold | 小节标题 |
| headline | 14 / Semibold | 列表主行、按钮 large |
| body | 13 / Regular | 正文 |
| bodyStrong | 13 / Medium | 按钮 medium、强调正文 |
| caption | 12 / Regular | 辅助说明 |
| micro | 11 / Regular | 时间戳、次要信息 |
| label | 10 / Semibold / 全大写 / tracking 1.1 | 分组小标签 |
| mono / monoSmall | 12 / 11 等宽 | 版本号、内存、地址、快捷键 |

---

## 3. 主题（`Sources/LauncherUI/Core/Themes.swift`）

| ID | 名称 | 模式 | 页面底 | 面板底 | 强调色 |
|---|---|---|---|---|---|
| `graphite` | 石墨 | 深色 | `#0F1012` | `#17181B` | `#F2F3F5`（近白） |
| `porcelain` | 瓷白 | 浅色 | `#F5F5F6` | `#FFFFFF` | `#18181B`（近黑） |

两套主题共用完全相同的结构、间距与组件代码，只有色值不同——这是本模板的核心验收项。

### 新增主题（2 步）
```swift
// 1) 用工厂方法声明（hover / active / soft 自动推导）
public static let myTheme = LauncherTheme.dark(
    id: "my-theme", name: "主题名", tagline: "一句话气质",
    canvas: …, surface: …, surfaceElevated: …, surfaceSubtle: …,
    stroke: …, strokeStrong: …,
    textPrimary: …, textSecondary: …, textTertiary: …,
    accent: …, onAccent: …
)
// 2) 加入 LauncherThemes.all
```
侧栏圆点、主题工作台、全部组件会自动适配。

---

## 4. 组件清单（`Sources/LauncherUI/Components/`）

| 组 | 组件 |
|---|---|
| 按钮 | `LauncherButton`（4 变体 × 3 尺寸，加载/禁用/全宽/快捷键）、`LauncherIconButton` |
| 标记 | `LauncherChip`、`LauncherBadge`、`LauncherStatusDot` |
| 输入 | `LauncherTextField`、`LauncherSearchField`、`LauncherSecureField`、`LauncherTextArea` |
| 选择 | `LauncherToggle`、`LauncherCheckbox`、`LauncherRadioCard`、`LauncherSlider`、`LauncherStepper`、`LauncherSegmentedControl`、`LauncherDropdown` |
| 容器 | `LauncherCard`、`LauncherCardHeader`、`LauncherListRow`、`LauncherSectionHeader`、`LauncherEmptyState`、`LauncherAvatar`、`LauncherKeyValueRow`、`LauncherStatTile`、`LauncherDivider` |
| 反馈 | `LauncherProgressBar`、`LauncherSpinner`、`LauncherSkeleton`、`LauncherBanner`、`LauncherToast` |
| 导航 | `LauncherSidebarItem`、`LauncherSidebar`、`LauncherTabBar`、`LauncherDialog` |

---

## 4.1 XML 声明式层

除 SwiftUI 代码外，所有控件也可用 XML 描述（标签与属性一一对应），运行时解析渲染，
令牌与主题完全复用；同一份 XML 在深/浅主题下自动切换配色。详见 [`XML-UI.md`](XML-UI.md)。

## 5. 无障碍与实现规范

- **对比度**：正文 ≥ 4.5:1；三级文字也保持可读（浅色主题约 4.5:1）。
- **焦点可见**：可交互元素均有焦点环或系统焦点，禁止移除。
- **减弱动效**：动画经 `.launcherAnimation(_:value:)` 或 `accessibilityReduceMotion` 判断，关闭后仅保留状态切换。
- **热区**：最小可点击高度 28pt（桌面），列表整行可点，图标按钮 34pt。
- **语义**：图标按钮必须 `accessibilityLabel`；状态不只靠颜色（配图标/文字）。
- **数字**：版本号、内存、地址、快捷键一律等宽字体。
- **图标**：仅 SF Symbols，禁 emoji。
- **窗口**：透明标题栏 + 全尺寸内容，预留 40pt 红绿灯安全区。

### 交付前检查清单
- [x] 深/浅主题逐页截图检查（浅色无白字白底、深色无脏灰）
- [x] 平面化：全站 0 投影 / 0 模糊 / 0 渐变填充
- [x] 每屏只有 1 个强调色，语义色仅出现在状态处
- [x] 按钮 4 变体 × 3 尺寸全部对齐（28/34/44）
- [x] 输入框 focus / error / disabled 三态齐全
- [x] 进度条确定态 + 不确定态
- [x] 禁用态不依赖颜色（降透明度 + 光标不变手型）
- [x] 无 emoji 图标；图标按钮有 accessibilityLabel
- [x] reduceMotion 下无循环动画
- [x] 1120×720 到 1920×1080 窗口下无横向滚动/裁切
