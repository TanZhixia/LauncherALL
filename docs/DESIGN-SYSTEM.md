# 方块启动器 · 设计系统（Minecraft Launcher UI Kit）

> 目标：**一套 SwiftUI 令牌 + 组件库**，让 6 套主题下所有控件保持同一套层级、节奏与对比度。
> 换主题只换语义色与氛围光，**不换结构、不换组件代码**。

---

## 1. 设计方向

| 维度 | 决策 | 依据 |
|---|---|---|
| 质感 | **毛玻璃 / Glassmorphism**：backdrop blur、半透明叠加、1px 浅描边、顶部高光 | 启动器覆盖层、浮层与侧栏需要"悬浮在游戏画面/壁纸上"的层次感；blur 10–20px、填充 15–30% 白、1px 高光边 |
| 基调 | 深色为主（4 深 + 2 浅），强调色饱和、背景低饱和 | 游戏类产品 = 沉浸 + 霓虹强调（vibrant + neon + immersive） |
| 结构 | 侧栏（252pt）+ 内容区；卡片化分组；4/8 基准间距 | 启动器是"工具 + 内容"混合型：高频操作（启动）要大 CTA，低频配置要可扫读 |
| 品牌 | 方块感但克制：44pt 像素网格、圆角方块徽标、等宽数字 | 呼应 Minecraft 的方块世界，但不使用任何官方素材/字体 |

**明确不做**：拟物贴图、渐变文字、超过 2 种强调色的彩虹配色、emoji 当图标、纯装饰性动效。

---

## 2. 令牌体系（源码：`Sources/LauncherUI/Core/Tokens.swift`）

### 2.1 语义色 `theme.colors.*`
组件**禁止**出现十六进制色值，只能消费以下语义：

| 令牌 | 用途 |
|---|---|
| `canvas` | 窗口兜底底色（材质之下） |
| `surface` / `surfaceElevated` | 玻璃填充（常规层 / 浮层侧栏） |
| `surfaceSubtle` | 内凹槽：输入框、滑轨、代码块 |
| `surfaceHover` / `surfaceActive` | hover / 按下的静态等价色 |
| `stroke` / `strokeStrong` | 1px 细描边 / 强调描边（选中、hover 边框） |
| `textPrimary` / `textSecondary` / `textTertiary` | 三级文字（正文 / 次要 / 提示） |
| `accent` / `accentAlt` / `onAccent` / `accentSoft` | 主强调、渐变副色、强调底上的前景、选中软底 |
| `success` / `warning` / `danger` / `onDanger` | 状态语义 |
| `focusRing` | 键盘焦点环（2pt，永不隐藏） |
| `shadow` | 玻璃投影色（深色主题用高透明黑，浅色主题用低透明黑） |

深/浅主题由两个工厂函数统一推导（`LauncherTheme.dark/light`），**新增主题不手写 surface/stroke**，避免多主题走样。

### 2.2 玻璃层级 `GlassLevel`
| 层级 | 场景 | 着色 × | 描边 × | 投影 × |
|---|---|---|---|---|
| `subtle` | 内嵌卡片、输入组、列表行 | 0.5 | 0.6 | 0.2 |
| `regular` | 常规卡片、面板 | 1.0 | 1.0 | 1.0 |
| `strong` | 侧栏、弹窗、Toast、侧栏底 | 1.55 | 1.4 | 1.6 |

玻璃 = `Material` 底 + 主题 tint 渐变 + 双层描边（描边渐变 + 顶部白色高光）+ 主题投影。
**所有浮层必须用 `GlassPanel` / `.glassBackground(level:)`，禁止自己写材质**，否则主题切换会断层。

### 2.3 刻度
- 间距：`xxs 2 · xs 4 · sm 8 · md 12 · lg 16 · xl 24 · xxl 32 · xxxl 48`
- 圆角：`sm 8 · md 12 · lg 16 · xl 22 · xxl 28 · pill 999`
- 控件高度：`small 28 · medium 34 · large 44 · icon 34`
- 动效：`fast 0.12s · base 0.2s · slow 0.32s`；弹簧 `response 0.34 / damping 0.82`
- 全局乘数：玻璃浓度 `0.4–1.6×`、圆角 `0.6–1.4×`（主题工作台可实时调）

### 2.4 字阶（系统字体，零外部字体依赖）
| 角色 | 规格 | 用法 |
|---|---|---|
| display | 30 / Bold / Rounded / tracking -0.4 | 页面主标题 |
| title | 22 / Semibold / Rounded | 区块标题、大数字 |
| sectionTitle | 15 / Semibold | 小节标题 |
| headline | 14 / Semibold | 列表主行、按钮 large |
| body | 13 / Regular | 正文（macOS 桌面基准） |
| bodyStrong | 13 / Medium | 按钮 medium、强调正文 |
| caption | 12 / Regular | 辅助说明 |
| micro | 11 / Regular | 时间戳、次要信息 |
| label | 10 / Semibold / tracking 1.1 / 全大写 | 分组小标签 |
| mono / monoSmall | 12 / 11 等宽 | 版本号、路径、内存、服务器地址 |

> 参考游戏向字体配对（Russo One / Chakra Petch）在 macOS 上不引入外部字体，改用 Rounded + 等宽数字实现"科技感 + 可读性"，并保持系统级渲染质量。

---

## 3. 主题清单（源码：`Sources/LauncherUI/Core/Themes.swift`）

| ID | 名称 | 模式 | 强调色 | 氛围 |
|---|---|---|---|---|
| `overworld` | 翡翠原野 | 深色 | `#34D399` 翡翠绿 | 草方块 + 晨雾，蓝绿双氛围光 |
| `nether` | 下界熔岩 | 深色 | `#F97316` 熔岩橙 | 岩浆与荧石，橙红双光 |
| `end` | 末地虚空 | 深色 | `#A78BFA` 末地紫 | 紫颂 + 星尘 |
| `sculk` | 深暗之域 | 深色 | `#22D3EE` 幽匿青 | 监守者蓝绿冷光 |
| `aurora` | 极光晨曦 | 浅色 | `#2563EB` 极光蓝 | 雪原晨光（浅色玻璃） |
| `cherry` | 樱花原野 | 浅色 | `#DB2777` 樱花粉 | 粉色花瓣（浅色玻璃） |

每套主题固定产出：3 色色板（`swatch`，用于侧栏快速切换圆点与主题卡预览）、背景渐变（3 段）、双氛围光、像素网格透明度、暗角强度、玻璃材质等级。

### 新增主题只需 3 步
```swift
// 1) 在 Themes.swift 里用工厂方法声明（自动继承一致的 surface/stroke/阴影）
public static let myTheme = LauncherTheme.dark(
    id: "my-theme", name: "主题名", tagline: "一句话气质",
    backdrop: [深, 中, 浅], glowPrimary: 主光, glowSecondary: 副光,
    accent: 强调色, accentAlt: 次强调, onAccent: 强调底文字,
    textPrimary: 主文字, textSecondary: 次文字, textTertiary: 三级文字
)
// 2) 加入 LauncherThemes.all
// 3) 完成 —— 侧栏、工作台、所有组件自动适配
```

---

## 4. 组件清单（源码：`Sources/LauncherUI/Components/`）

| 组 | 组件 | 说明 |
|---|---|---|
| 按钮 | `LauncherButton` | 4 变体（primary/secondary/ghost/danger）× 3 尺寸，加载/禁用/全宽/快捷键提示 |
| | `LauncherIconButton` | 纯图标按钮（必须有 accessibilityLabel） |
| 标记 | `LauncherChip` / `LauncherBadge` / `LauncherStatusDot` | 过滤 chip、状态徽章、在线点 |
| 输入 | `LauncherTextField` / `LauncherSearchField` / `LauncherSecureField` / `LauncherTextArea` | 聚焦环、错误态、helper、禁用 |
| 选择 | `LauncherToggle` / `LauncherCheckbox` / `LauncherRadioCard` | 自绘，全主题一致 |
| | `LauncherSlider` / `LauncherStepper` / `LauncherSegmentedControl` / `LauncherDropdown` | 拖动、步进、分段、菜单 |
| 容器 | `LauncherCard` / `LauncherCardHeader` / `LauncherListRow` / `LauncherSectionHeader` | 玻璃分层与列表选中态 |
| | `LauncherAvatar` / `LauncherKeyValueRow` / `LauncherStatTile` / `LauncherDivider` | 头像、键值、统计、分割 |
| | `LauncherEmptyState` | 空状态 |
| 反馈 | `LauncherProgressBar` / `LauncherSpinner` / `LauncherSkeleton` / `LauncherBanner` / `LauncherToast` | 进度（含不确定态）、加载、骨架屏、横幅、Toast |
| 导航 | `LauncherSidebarItem` / `LauncherSidebar` / `LauncherTabBar` / `LauncherDialog` | 侧栏项、侧栏容器、Tab、对话框 |

---

## 5. 无障碍与实现规范

- **对比度**：正文文字与底 ≥ 4.5:1（每套主题的 `textPrimary/Secondary/Tertiary` 均已按此挑选；浅色主题的强调色底一律配 `onAccent`）。
- **焦点可见**：所有可交互元素都有 `.launcherFocusRing` 或系统焦点；禁止移除焦点环。
- **减弱动效**：所有动画经 `.launcherAnimation(_:value:)` 或 `accessibilityReduceMotion` 判断，关掉后仅保留状态切换（无位移/无循环动画）。
- **热区**：最小可点击高度 28pt（桌面端），文本行整行可点；图标按钮 34pt。
- **语义**：图标按钮必须 `accessibilityLabel`；状态不能只靠颜色（配图标或文字）。
- **数字**：版本号、内存、地址、体积一律等宽字体，避免跳动。
- **图标**：只用 SF Symbols，禁止 emoji。
- **窗口**：透明标题栏 + 全尺寸内容，预留 40pt 红绿灯安全区。

### 交付前检查清单
- [x] 6 套主题下逐个控件截图检查（浅色主题无白字白底）
- [x] 玻璃三层叠放能分辨层级且不脏
- [x] 按钮 4 变体 × 3 尺寸全部对齐（高度 = 28/34/44）
- [x] 输入框 focus / error / disabled 三态齐全
- [x] 进度条确定态 + 不确定态
- [x] 禁用态不依赖颜色（降透明度 + 光标不变手型）
- [x] 无 emoji 图标；图标按钮有 accessibilityLabel
- [x] reduceMotion 下无循环动画
- [x] 1200×760 到 1920×1080 窗口下不出现横向滚动/裁切
