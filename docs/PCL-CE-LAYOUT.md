# PCL-CE 界面布局蓝图（WPF 源码 → SwiftUI 重构参照）

> 对象源码：`/tmp/pcl-ce/Plain Craft Launcher 2/`（Plain Craft Launcher Community Edition，WPF / .NET）。
> 引用格式 `文件:行号`；尺寸为 WPF 设备无关像素，与 SwiftUI 的 pt 可直接对齐。只写**结构 / 顺序 / 尺寸 / 交互**。

| 关注点 | 文件 |
|---|---|
| 外壳、标题栏、导航、左右栏容器 | `FormMain.xaml`（280 行）、`FormMain.xaml.cs`（2337 行） |
| 全局样式 / 色板 / 控件模板 | `Application.xaml`（664 行） |
| 页面骨架基类 | `Controls/MyPageLeft.cs`、`Controls/MyPageRight.cs` |
| 控件（32 个） | `Controls/` |
| 一级页面 | `Pages/PageLaunch`、`PageDownload`、`PageSetup`、`PageInstance`、`PageTools`、`PageHomepage` |
| 文案 | `PCL.Core/App/Localization/Languages/zh-CN.xaml` |

---

## 1. 整体窗口结构

### 1.1 窗口基本度量

| 项 | 值 | 出处 |
|---|---|---|
| 默认 / 最小尺寸 | 850 × 500（持久化，读失败回落 910 × 570）；最小 **810 × 470** | `FormMain.xaml:13-15`、`FormMain.xaml.cs:108-120` |
| 窗口样式 | `SingleBorderWindow` + `WindowChrome`：`CaptionHeight=0`、`UseAeroCaptionButtons=False`、`ResizeBorderThickness=0`、`CornerRadius=12` | `FormMain.xaml:13-28` |
| 外层留白 | 10px 全周（`PanBack Margin=10`），内容按 `RadiusX/Y=6` 裁圆角 | `FormMain.xaml:104-107` |
| 标题栏 | **自定义**，整条 48px 自绘且内含导航 | `FormMain.xaml:119` |
| 主题色 / 主背景 | 单一强调色 `ColorBrush3 #1370f3`（标题栏底色即它）；主底 `#fbfbfb`，开启「背景多彩」时换 LCH 三段对角渐变 | `Application.xaml:36,75`、`Modules/UI/Theme/ThemeManager.cs:44-73` |
| 启动动画 | `PanRoot` 初始 `Rotate -4° / TranslateY 60`，600ms 回正 | `FormMain.xaml:30-35`、`FormMain.xaml.cs:207-219` |

### 1.2 视觉层级（`PanForm` 内 Grid 叠加，自下而上）

| Z | 元素 | 说明 | 出处 |
|---|---|---|---|
| 0 | `ImgBack`（Canvas + MediaElement） | 视频/图片背景，`UniformToFill`，静音循环 | `FormMain.xaml:113-118` |
| 1 | `PanTitle`（48px） | 标题栏 + 一级导航 | `FormMain.xaml:119-194` |
| 2 | `PanLeft` | 左栏毛玻璃底 + 4px 右投影 | `FormMain.xaml:195-213` |
| 3 | `PanMain` | 左栏页面 + 右栏页面 | `FormMain.xaml:214-230` |
| 4 | `PanHint` / `PanExtraButtons` | 左下角提示栈（底留 20）；右下角圆形快捷按钮列（`Margin 15`） | `FormMain.xaml:231-272` |
| 5 | `PanMsgBackground` + `PanMsg` | 模态层（BlurBorder 全窗覆盖） | `FormMain.xaml:273-276` |

### 1.3 标题栏（高 48）

1. **整条可拖拽**：`MouseLeftButtonDown="FormDragMove"`，`WindowChrome.IsHitTestVisibleInChrome=True`（`FormMain.xaml:120`）。
2. 背景 `AnimatedBackgroundGrid`，画刷绑 `ColorBrush3` → 满宽实色条，**不是**透明标题栏。
3. 右侧窗口按钮 28×28、`Theme=White`、垂直居中：关闭 `Margin 0,0,12,0`（`x`）、最小化 `0,0,44,0`（`minus`）、帮助 `0,0,76,0`（默认 `Collapsed`）（`:129-134`）。
4. 主层 `PanTitleMain` 三列 `1* / Auto / 1*`（`:135-140`）：左为 Logo `Path`（宽 39、白描边 2.2、`Margin 19,15.5`；备有 HMCL 版 52×15 与文字版 17px）+ CE 徽标（白色圆角 5 的 20×18 方块内嵌反色 C，`Margin 10,0,0,0`）；中为导航（见 1.4）；右为空（窗口按钮浮于 Grid 上，不占位）。

### 1.4 一级导航（顶部 4 项）

| 序号 / Tag | 文案 | 图标（lucide） |
|---|---|---|
| 0 / 0 | 启动 | `play` |
| 1 / 1 | 下载 | `download` |
| 2 / 2 | 设置 | `settings` |
| 3 / 3 | 工具 | `wrench` |

- 控件 `MyRadioButton`：`Margin 5,0`、`Padding 2,0`、`LogoScale` 0.9~1.1（`FormMain.xaml:158-181`）。
- 胶囊：`MinHeight/MaxHeight 27`、`CornerRadius 13.5`、图标槽 16×16（左边距 12）、文字 `Margin 8,0,12,0`（`MyRadioButton.xaml:1-25`）。
- 状态（`ColorType=White` 默认，`MyRadioButton.xaml.cs:284`）：选中 = 白底 + 强调色图标与文字；悬停 = 半透明白底；未选中 = 透明底 + 白字。
- 顺序与 `PageType` 枚举强绑定（`PanTitleSelect.Children[(int)page]`，`FormMain.xaml.cs:1723`），**枚举顺序不可改**；4 项均可被「功能隐藏」整项隐藏，隐藏后向左收拢（`PageSetupUI.xaml:370-483`）。

### 1.5 子页标题栏（同一 48px 内切换）

进入副页（实例选择/实例设置/任务管理/实时日志/资源详情/存档管理）时整层替换（`FormMain.xaml:184-193`）：

| 元素 | 规格 |
|---|---|
| 返回按钮 | 28×28、`Margin 12,0,0,0`、`Theme=White`、`arrow-left`、`LogoScale 0.87` |
| 标题 | 15px、白色、`Margin 47,1,60,0`、左对齐 |
| 过渡 | 主层左移淡出 150ms；子层右滑淡入 350ms（`EaseOutBack`） |

### 1.6 内容区如何承载页面

- `PanMain` 两列 `Auto`（左）+ `1*`（右），各一个 `Border` 宿主 `PanMainLeft` / `PanMainRight`（`FormMain.xaml:214-230`），每个宿主只放一个 `Child`。
- `PageChangeAnim()` 换 Child（`FormMain.xaml.cs:1985-2100`）：左页须继承 `MyPageLeft`，右页须继承 `MyPageRight`。
- 动画：左栏逐项右移入场（每项 +7~15ms 延迟）；右栏卡片自上而下每张 +25ms、上移 16→0，滚动条从 +10 滑入 350ms（`MyPageLeft.cs:70-120`、`MyPageRight.cs:520-575`）。
- 右栏统一带 10 状态加载机（`Empty / LoaderWait / LoaderEnter / LoaderStay / LoaderExit / ContentEnter / ContentStay / ContentExit / PageExit`，`MyPageRight.cs:8-20`），故每页自带「加载卡 → 内容」替换逻辑。

### 1.7 左右分栏宽度规则（关键）

`PanMain` 左列为 `Auto`，**没有全局固定宽度，也没有可拖拽分割线**，宽度由左页内容决定（典型 120~170）：

| 页面 | 左栏宽度 | 依据 |
|---|---|---|
| 启动 `PageLaunchLeft` | **固定 300** | `PageLaunchLeft.xaml:9` |
| 下载 / 设置 / 实例 / 工具左栏 | 内容自适应（最长标题 + 34 图标 + 35 右侧预留） | 均无 `Width`；设置页 `d:DesignWidth=152` 仅设计器预览 |
| 实例选择 / 实时日志 | `MinWidth 250`、`MaxWidth 300` | `PageSelectLeft.xaml:13`、`PageLogLeft.xaml:13` |
| 任务管理 | 200 | `PageSpeedLeft.xaml:8` |

左栏底为 `BlurBorder`（画刷 `ColorBrushTransparentBackground #d2fbfbfb`），宽度随左页实际宽度做 180ms 缓动（`FormMain.xaml.cs:2124-2160`）；左右之间**没有分割线**，仅靠右缘 4px 渐变暗影（透明度 0.04）区分（`FormMain.xaml:204-212`）。

### 1.8 全局浮层

| 浮层 | 规格 | 出处 |
|---|---|---|
| 快捷按钮列 | 右下角纵向堆叠、`Margin 15`；每颗宽 40、正圆（`CornerRadius 1000`）、强调色底、阴影 10/0.2、图标四周 `Margin 12`；成员：更新重启/回到顶部/任务管理/放弃启动/关闭游戏/游戏日志/音乐（音乐支持右键） | `FormMain.xaml:235-272`、`MyExtraButton.xaml:1-30` |
| 提示栈 | 左下角、`Margin 0,0,0,20`、`ZIndex 1` | `FormMain.xaml:231-234` |
| Toast | 圆角 8、图标 20×20、内容 `Margin 10,8,10,6`、底部 3px 进度条 | `MyToast.xaml:8-33` |

---

## 2. 通用骨架与度量（复用到所有页面）

### 2.1 右侧页面骨架

```
MyPageRight (AdornerDecorator)
└─ MyScrollViewer  Vertical=Auto, Horizontal=Disabled
   └─ StackPanel PanMain  Margin="25,25,25,10"   ← 页面左右 25 / 上 25 / 下 10
      ├─ MyCard  Margin="0,0,0,15"              ← 卡片间距 15
      └─ ...
└─ MyCard PanLoad（居中加载卡，Margin 40,0）
```

出处 `PageSetupLaunch.xaml:12-13`、`PageSetupJava.xaml:12-17`；少数页外层换 `Grid + DockPanel`（`PageSetupLog.xaml:12-30`），内边距仍 25。

### 2.2 卡片 `MyCard`

| 项 | 规格 | 出处 |
|---|---|---|
| 圆角 / 底色 | 5；`ColorBrushTransparentBackground`；无边框 | `MyCard.cs:33-44,85-107` |
| 标题 | 13px、`Bold`、`Margin 15,12,0,0`、左对齐 | `MyCard.cs:152-157` |
| 折叠三角 | 10×6，右上 `Margin 0,17,16,0`，展开 180° | `MyCard.cs:166-168` |
| 折叠态高度 | **40**（`SwapedHeight`，仅标题条） | `MyCard.cs:474` |
| 内容区惯例 | 距顶 38~40 / 左右 20~25 / 底 15（避开标题行） | 各页 `"25,40,25,15"`、`"20,38,20,18"` |
| 懒加载 | `IsSwapped=True` 首次展开才 `StackInstall`，并追加 18px 底部占位 | `MyCard.cs:196-220` |

### 2.3 列表行 `MyListItem`

| 项 | 规格 | 出处 |
|---|---|---|
| 高度 / 字体 | 默认 42，侧栏统一覆写 **36**；标题 14；选中 `ColorBrush3`（H<40）/`ColorBrush2`（H≥40），未选中 `ColorBrush1` | `MyListItem.xaml:5`、`MyListItem.xaml.cs:174-178,498` |
| 列结构 | 勾选条 6 / 左缩进 0 / 图标 34（H≥40 时 38）/ 标题 Auto / 余量 1* / 右预留 | `MyListItem.xaml.cs:697-699,765-771` |
| 选中指示 | 左侧 5px 竖条、圆角 2、`ColorBrush3`，选中时 `Margin -1,6,0,6` 并纵向拉伸 | `MyListItem.xaml.cs:787-800` |
| 悬停背景 | `ColorBrush7` 底 + `ColorBrush6` 1px 描边；**高>40 或开缩放动画时圆角 6，否则直角** | `MyListItem.xaml.cs:196-210` |
| 副标题 / 标签 | `Info` 12px、`Opacity 0.6`、`Margin 4,0,0,0`，第 3 行；`Tags` 11px + 圆角 3 小底，右下横排 | `MyListItem.xaml.cs:240-252,302-318` |
| 行尾按钮 | 覆盖整行（`Span 999`），每颗 25×25、右 `Margin 5`、默认 `Opacity 0`；整行悬停才淡入，右侧预留从 `MinPaddingRight`（左栏 35）扩到 `5 + 25×n` | `MyListItem.xaml.cs:60-160,430-470` |

### 2.4 设置行网格（设置页右栏的统一节奏）

| 项 | 值 | 出处 |
|---|---|---|
| 标签列 | `Auto` + `SharedSizeGroup="Name"`（整页同宽），右 `Margin 0,0,25,0` | `PageSetupLaunch.xaml:17-21` |
| 控件列 | `1*` 且 `ColumnSpan=2`，覆盖右侧 60/75 的尾部列 | 同上 |
| 行节奏 | `28`（行）+ `9`（间隔）交替，末行 `Auto` | `PageSetupLaunch.xaml:22-39` |
| 按钮行 | 高 35、`MinWidth 140`、`Padding 13,0`、横向间隔 20 | `PageSetupUI.xaml:40-52`、`PageInstanceOverall.xaml:90-108` |

### 2.5 状态组件

| 组件 | 规格 | 出处 |
|---|---|---|
| `MyLoading` | 环形；卡片内高 50 / 带文字 `Margin 20,20,20,17`；三态、失败可点击重试 | `MyLoading.xaml:1-25`、`PageDownloadClient.xaml:14-18` |
| `MyHint` 提示条 | 左 3px 竖条（`BorderThickness 3,0,0,0`）、圆角 2、`Padding 12,9`、`LineHeight 16`；主题 Red/Blue/Yellow；可选 20×20 关闭按钮 | `MyHint.xaml:1-22`、`MyHint.xaml.cs:16-130` |
| 空状态卡 | 居中 `MyCard`：19px 强调色标题 + 2px 强调色横线 + 正文（`Margin 10,15,10,5`）+ 可选 35 高按钮（`MinWidth 140`） | `PageSelectRight.xaml:20-50` |
| 加载卡 | 居中 `MyCard` + `MyLoading`，`Margin 40` | `PageSelectRight.xaml:52-58` |

### 2.6 色板（`Application.xaml:33-80`，深浅两套由主题服务换值）

| 令牌 | 值 | 语义 |
|---|---|---|
| `ColorBrush1` / `ColorBrush2` | `#343d4a` / `#0b5bcb` | 主文字 / 强调文字（深） |
| `ColorBrush3` | `#1370f3` | **唯一强调色**：标题栏、选中、主按钮 |
| `ColorBrush4`~`8` | `#4890f5` → `#eaf2fe` | 强调色梯级（悬停/浅底） |
| `ColorBrushGray1~8` | `#404040` → `#f5f5f5` | 中性文字与分割 |
| `ColorBrushHalfWhite` | `#55ffffff` | 输入框 / 按钮浅底 |
| `ColorBrushTransparentBackground` | `#d2fbfbfb` | 卡片 / 左栏底 |

---

## 3. 一级页面布局

### 3.1 启动页 `PageLaunch`（左 300 固定 / 右自适应）

**左栏**（`PageLaunchLeft.xaml:9-53`，`Width=300`，五行五列 `Auto / 20 / 1* / Auto / 10`）：

| 行 | 内容 | 规格 |
|---|---|---|
| 1（`1*`） | 账户/皮肤区 `PanLogin`（`ColumnSpan=5`、`Margin 20,0`、垂直居中） | 动态装载 `PageLoginAuth` / `PageLoginProfile` / `PageLoginMs` / `PageLoginOffline` |
| 2 | 启动按钮 + 版本名 | `BtnLaunch` **高 54**、`Margin 20,0`、`ColorType=Highlight`、`Padding 30,0,30,15`；`LabVersion` 11px、`ColorBrushGray3`、`Margin 35,0,35,10`、居中、单行省略 |
| 3 | `BtnInstance`（选择实例，`1*` 列）+ `BtnMore`（实例设置，`Auto` 列） | 均 **高 35**、`Margin 0,10,10,0` |
| 4 | 20 高占位 | — |

- 皮肤卡 `MySkin`：64×64，前景 56×56、底图 48×48，`NearestNeighbor`；右键菜单 3 项（另存为/刷新/更换披风），均带图标（`MySkin.xaml:1-30`）。
- 账户列表（`PageLoginProfile.xaml:26-36`）：`MyScrollViewer MaxHeight 300` + `ItemsControl`，行 `MyListItem Margin 8,2,10,2`、`Type=Clickable`、Title=用户名、Info=账号类型、Logo=头像，右键弹上下文菜单；下方居中 `MyCard PanButtons`（`StackPanel Margin 10,3,0,3`）放 24×24「新建账户」。
- 启动中 `PanLaunching`（`:55-158`）整块替换账户区：`MyLoading` 50 + 标题 20px（斜切 -3°）+ 副标题 13.5px + 4 高进度条（列 `69.28* / 30.72*`）+ 4 行键值（步骤/登录方式/启动进度/下载速度；标签右对齐 `Opacity 0.5`，值左对齐 `MaxWidth 160`）+ 260 宽气泡提示（1px 描边、圆角 3，顶部中段挖 72×10 缺口）+ 底部 `BtnCancel` 高 35。

**右栏**（`PageLaunchRight.xaml:6-26`）：`MyScrollViewer` → `StackPanel Margin 25,25,25,10`，三段：

1. `PanCustom` 动态主页（按「主页」设置渲染 XML，内部复用 `MyCard` 等，`PageLaunchRight.xaml.cs:484-520`）；
2. CE 提示卡：`MyCard`、`Margin 0,0,0,15`、右上 20×20 关闭键、正文 `StackPanel Margin 25,38,23,15` 两段 13.5px；
3. 启动日志卡：正文 `Margin 20,38,20,18` 多行不截断，**仅调试模式可见**（`PageLaunchRight.xaml.cs:36`）。

### 3.2 下载页 `PageDownload`

左栏（`PageDownloadLeft.xaml`，无固定宽）：`MyScrollViewer` → `StackPanel Margin 0,12,0,0`，全部 `MyListItem Type=RadioBox Height=36 MinPaddingRight=35 IsScaleAnimationEnabled=False`，行尾统一一颗 25×25 刷新按钮（ToolTip 右置）；组标题为 12px、`Opacity 0.6`、`Margin 13,10,5,4` 的 `TextBlock`：

| 组 | 项（Tag → 子页） |
|---|---|
| （首项，无标题） | Minecraft 安装 `1` |
| 社区资源 | 模组 `2`、整合包 `3`、数据包 `4`、资源包 `5`、光影包 `6`、世界 `7`、收藏夹 `8` |
| 安装包 | Minecraft `9`、OptiFine `10`、Forge `11`、NeoForge `12`、Cleanroom `13`、Fabric `14`、Legacy Fabric `18`、LabyMod `17`、LiteLoader `16` |

右栏按 Tag 切换：社区资源类（`Comp/PageComp.xaml`）顶部固定三段 —— `MySearchBox`（高 40）→ 筛选卡（`Grid Margin 7`，行 `28 / 8 / 28`，六列：来源/标签/排序/版本/Loader/右侧两颗图标按钮）→ 结果卡（`StackPanel Margin 12`）+ 分页卡；版本/加载器类（`PageDownloadClient.xaml:11-19`）为 `MyScrollViewer` → `StackPanel Margin 5` → `PanMain Margin 20,20,20,5`。

### 3.3 设置页 `PageSetup`

左栏 `PageSetupLeft.xaml:8-179`：`MyScrollViewer` → `StackPanel Margin 0,12,0,0`，4 个分组标题 + 11 个 `MyListItem`（见 4.1）；右栏按类别装载（见第 4 章）。

### 3.4 实例页 `PageInstance`

左栏 `PageInstanceLeft`：`AnimatedControl=PanItem`（逐项入场），分组「游戏本体」+「游戏资源」，项：概览 `0`、设置 `1`、修改 `10`、导出 `2`、存档 `3`、截图 `4`、模组 `5`、禁用模组 `6`、资源包 `7`、光影包 `8`、投影原理图 `9`、服务器 `11`，全部 `RadioBox`、36 高，多数带行尾初始化/刷新按钮。右栏「概览」`PageInstanceOverall.xaml:10-160`：`StackPanel Margin 25,10` 内四卡 —— 展示卡（无标题，`Grid Margin 10,7`）、信息卡（`MyLoading` + `ItemsControl`，行 = `MyListItem`(Logo + 标题 + Info 值)）、个性化卡（两个 28 高设置行）、快捷方式/管理卡（35 高按钮行，`WrapPanel Margin 0,-5,-20,7`，按钮 `Margin 0,7,20,0`）。

### 3.5 工具 / 联机 `PageTools`

左栏仅两项（`PageToolsLeft.xaml`）：分组「多人联机」→ 联机大厅 `1`；分组「小工具」→ 工具箱 `3`；行结构与下载/设置左栏一致。

### 3.6 主页（新闻流）`PageHomepageNewsView`

瀑布流 `WaterfallPanel`：`ColumnSpacing 14`、`RowSpacing 14`、`MaxItemWidth 240`、`AutoFit`、虚拟化回收（`:22-30`）；卡片 `MyCard` → `Grid Margin 12`，五行 = 封面（圆角 6、`UniformToFill`）/标题 16px/作者·时间/摘要/「查看详情」`MyTextButton`；加载态为居中 `MyCard Margin 32` + `MyLoading`。

### 3.7 副页面速查

| 副页面 | 左栏 | 右栏 |
|---|---|---|
| 实例选择 | 实例列表（250~300），42 高 `MyListItem`（图标 + 名称 + 版本副标题 + 右键菜单） | 顶部 `MySearchBox Margin 25,15,25,12` + 列表 `Margin 25,2,25,10` + 空状态/加载卡 |
| 实例设置 | 同 `PageInstanceLeft` | 12 个右栏子页 |
| 任务管理 / 实时日志 | 200 / `MinWidth 250` | 任务列表卡 / 日志正文 |
| 资源详情 / 存档管理 | 空 `MyPageLeft`（宽 0 占位）/ 存档列表 | 详情页 / 详情与数据包 |

---

## 4. 设置页分类与右栏控件清单

### 4.1 左栏类别（`PageSetupLeft.xaml`）

| 分组 | 项 | Tag | 图标 | 行尾按钮 |
|---|---|---|---|---|
| 游戏 | 启动 | 0 | `rocket` | 初始化（`rotate-ccw`） |
| 游戏 | Java | 9 | `coffee` | 刷新（`refresh-cw`） |
| 游戏 | 管理 | 2 | `book-marked` | 初始化 |
| 工具 | 联机 | 7 | `bubbles` | 初始化 |
| 启动器 | 个性化 | 1 | `palette` | 初始化 |
| 启动器 | 语言 | 11 | `earth` | 初始化 |
| 启动器 | 杂项 | 10 | `monitor-cog` | 初始化 |
| 关于 | 软件信息 | 4 | `info` | — |
| 关于 | 软件更新 | 8 | `refresh-cw` | — |
| 关于 | 反馈 | 6 | `message-circle` | 刷新 |
| 关于 | 查看日志 | 5 | `scroll-text` | — |

> 行尾按钮是「重置本页设置」而非导航；`PageSubType.SetupLink = 3` 为遗留枚举，左栏已无对应项。

### 4.2 启动 `PageSetupLaunch.xaml`（327 行，三卡 + 一条跳转按钮）

**卡 1「启动选项」**（`:14-166`）：`Grid Margin 25,40,25,15`，三列 `Auto(Name) / 1* / 60`，七组「28 高 + 9 间隔」：①实例隔离 `MyComboBox`（关闭/仅模组/非正式版/模组+非正式版/全部，项带 ToolTip）②窗口标题 可编辑 `MyComboBox`（`IsEditable`、`HintText=默认`、一条格式示例）③自定义信息 `MyTextBox` + `BlacklistValidator`（禁 `" “ ”`）④可见性 `MyComboBox` 6 项 ⑤优先级 `MyComboBox`（`SelectedValuePath=Tag`）⑥窗口大小：嵌套 `Grid` = `MyComboBox`（全屏/默认/与启动器相同/自定义/最大化）+ 两个 **60 宽**数字框 + 中间 18px ` × `（`IntValidator 1~9999`）⑦登录方式 `MyComboBox`（网页/设备码，置灰）⑧IP 协议栈 `MyComboBox`。

**卡 2「游戏内存」**（`:167-240`）：两条 `MyHint Theme=Yellow`（`Margin 0,0,0,12`）→ `MyRadioBox`「自动」（宽 110）/「自定义」→ 两条 `MySlider`（Max 49，`Margin 0,0,12,9`）→ 内存可视化条（`Grid Margin 0,11,2,0`，列 `4.7* / 2.5* / 0.7*`，条高 **4**，三段色：已用渐变 / 已分配 `ColorBrush3` 0.5 / 空闲 `ColorBrush6` 0.7，上 11px 说明、下 16px 数值）。

**卡 3「高级启动选项」**（`:241-320`，`IsSwapped CanSwap` 可折叠）：渲染器下拉 → JVM 参数（标签行内嵌 23 高重置按钮 + **高 100** 多行 `MyTextBox`）→ 游戏参数 → 启动前命令 + 17 高「等待结束」→ 7 个 **28 高** `MyCheckBox` 纵列（禁用 JLW / LegacyFix / 独显 / 用 java.exe / 禁用 LWJGL unsafe agent / 禁用崩溃分析 / 锁定内存）→ `MyHint Theme=Blue CanClose`；卡下居中 `MyExtraTextButton`「切换到实例设置页」（`Margin 0,-5,0,15`）。

### 4.3 Java `PageSetupJava.xaml:12-27`

①卡：`StackPanel Margin 8` 内一颗 `MyIconTextButton`「添加」（`circle-plus`）；②卡：`StackPanel Margin 15` 内列表（代码构建，`PageSetupJava.xaml.cs:81-180`）—— 首行「自动选择」`MyListItem RadioBox`，每个 Java 为 `MyListItem RadioBox`（Title=主版本、Info=路径/厂商、Tags=标记），行尾 **3 颗**图标按钮（`folder-open` 打开目录 / `info` 详情 / 启用开关）；③加载卡 + `MyLoading Margin 12`。

### 4.4 个性化 `PageSetupUI.xaml`（486 行，7 张卡）

| # | 卡片 | 控件清单（自上而下） |
|---|---|---|
| 1 | 基础 | 窗口不透明度 `MySlider`；「获取快照」；主题模式 `MyComboBox`（浅/深/跟随系统）；浅色与深色主题色两个 `MyComboBox`（`ItemsSource=ThemeColors`）；4 个 22 高 `MyCheckBox`（显示 Logo / 锁定窗口 / 显示小提示 / 高级材质）；高级材质子区 = 模糊半径 `MySlider` + 采样率 `MySlider` + 模糊方式 `MyComboBox`（高斯/盒式） |
| 2 | 字体 | `FontSelector` + 字号/字重相关控件 |
| 3 | 背景（标题随数量变） | 适配方式 `MyComboBox`（9 项）；不透明度 `MySlider`（Max 1000）；模糊 `MySlider`（Max 40）；2 个 `MyCheckBox`（暂停视频/彩色遮罩）；按钮行「打开文件夹 / 刷新 / 清除」 |
| 4 | 音乐（标题随曲数变） | 音量 `MySlider`（Max 1000）；5 个 22 高 `MyCheckBox`（随机/自动播放/启动播放/进游戏停止/SMTC）；按钮行同上 |
| 5 | 标题栏 | 4 个 `MyRadioBox`（无/默认/文字/图片）+ `MyCheckBox`「左对齐」+ 文本输入 +「更换/清除图片」 |
| 6 | 主页 | 4 个 `MyRadioBox`（空白/预设/本地文件/网络更新）+ 2 条 `MyHint`（蓝/黄）+「刷新 / 教程」+ 网络地址 `MyTextBox`（`MaxHeight 28`）+ 预设 `MyComboBox`（**14 项**：小提示/McNews/每日整合包/皮肤/BMCLAPI/手册/杂志/GitHub/版本摘要/今日新闻/冷知识/整合包推荐/番剧/官方动态） |
| 7 | 功能隐藏 | `Grid` 多列 22 高 `MyCheckBox` 密集排布，一行 5~6 个，分「导航项 / 工具项 / 实例项」三组，可隐藏 20+ 入口 |

### 4.5 其余类别速查

| 类别 | 右栏卡片 | 备注 |
|---|---|---|
| 管理 | 游戏资源获取行为 / 社区资源获取行为 / 辅助功能 | 版本隔离、下载源优先级、Mod 命名风格 |
| 联机 / 语言 / 杂项 | 联机设置 +「网络测试」卡（`:93`）/ 单卡「语言」（`:22`）/ 系统 + 网络 + 调试选项（`:11,78,148`） | 调试卡默认折叠 |
| 软件信息 | 关于 / 原作者 / 社区版 / 特别鸣谢（7 个）/ 贡献者 / 版权声明（`:22-354`） | 大量 `MyListItem` + 外链按钮 |
| 软件更新 | 更新渠道行（`28/7/28` 网格，三列 `Auto/*/75`）+ 其他选项卡（`:135`） | — |
| 反馈 | 提交反馈卡 + 10 张状态卡（处理中/等待处理/等待/暂停/在即/已完成/已拒绝/已忽略/重复）（`:16-132`） | 状态卡为可折叠列表 |
| 查看日志 | 卡「日志操作」（`WrapPanel ItemHeight 35`，导出/导出全部/打开目录/清理历史，末颗 `ColorType=Red`）+ 卡「所有日志」（`StackPanel Margin 20,36,18,18`） | `:12-31` |

---

## 5. 下载页细节

### 5.1 版本列表行（`DownloadUi/MinecraftMenu.cs:18-90`）

| 属性 | 值 |
|---|---|
| 控件 / 图标 | `MyListItem` 高 42、`Type=Clickable`；图标为**方块贴图**：正式版 `Grass.png`、快照 `CommandBlock.png`、特殊 `GoldBlock.png`、其他 `CobbleStone.png` |
| 标题 / 副标题 | 格式化版本号（下划线转空格）；副标题为「发布日期 ‖ 原始版本号」（12px、0.6 透明） |
| 标签 | UVMC 来源追加 `Tags` |
| 悬停 | 右侧浮出 2 颗 25×25 图标按钮（另存为 `save` / 更新日志），ToolTip 居中偏下 30 |

### 5.2 版本卡的分组与折叠

首页一张「最新版本」卡（正式版 + 快照各带 lore 说明）；其余每类一张卡，标题 = `分类名 (数量)`、`Margin 0,0,0,15`、`IsSwapped=True` **默认折叠成 40 高**，首次展开才生成行；卡内容 `StackPanel Margin 20,40,18,0` + 尾部 18 占位（`PageDownloadInstall.xaml.cs:1030-1110`）。

### 5.3 安装流程右栏（`PageDownloadInstall.xaml`）

`Grid` 双层：`PanMinecraft`（版本列表）↔ `PanSelect`（安装选项，横向滑入 40px）。`PanSelect` 自上而下：①头部条 `MyCard Height=62 UseAnimation=False`（26×26 返回按钮 `Margin 13,0,0,0`、32 高版本图标 `Margin 52`、可编辑框 `Margin 93,0,16,0` `MinHeight 30` 15px）②若干 `MyHint` 兼容性提示（`Margin 0,10,0,0`）③加载器选择卡 ×N：`MyCard Height=40`（展开后自适应），标题 = 加载器名，右侧 18 高状态行（图标 + 版本号）与 30×30 清除按钮，`IsSwapped` 展开版本列表 ④底部常驻 `MyExtraTextButton`「开始下载」居中贴底 ⑤加载态：居中 `MyCard` + 一组 `MyLoading`。内边距 `PanInnerMargin = 25,10,25,40`（列表态）/ `25,10,25,25`（选择态）（`PageDownloadInstall.xaml.cs:162,280`）。

### 5.4 搜索结果与分页（`Comp/PageComp.xaml:114-148`）

结果行 `MyCompItem`：高 64，列 `7 / 50 / 8 / Auto / 1* / Auto`，行 `1* / 20 / 18 / 16 / 1.1*`；图标 50×50 圆角 6；标题 14 + 原名 12（0.4 透明）；简介 12 灰单行省略 + 悬浮完整提示。分页卡：居中 `MyCard` 内 `StackPanel Height=23 Margin 10,7` —— 首页 « / 上一页 ‹ / 页码（15px 强调色，`Margin 8,0,13,0`）/ 下一页 ›（右 Margin 30 预留总页数）。

---

## 6. 控件清单

### 6.1 控件一览（`Controls/`）

| 控件 | 类型 | 关键尺寸 / 形态 | 用途 |
|---|---|---|---|
| `MyButton` | 按钮 | 圆角 3、1px `ColorBrush1` 描边、底 `#55ffffff`、13px；`ColorType` = Normal/Highlight/Red | 主/次按钮 |
| `MyIconButton` / `MyIconTextButton` / `MyTextButton` | 图标按钮 / 图标+文字 / 纯文字 | 图标按钮默认 25~28，`Theme` = White/Black/Custom；文字版无底 | 行尾、卡片角、标题栏 |
| `MyExtraButton` / `MyExtraTextButton` | 圆形浮动 / 胶囊主按钮 | 40 正圆、强调色、阴影 10/0.2；胶囊高 52、圆角 = 高 ×0.4、`Margin 20` | 右下快捷列 / 「开始下载」 |
| `MyListItem` | 列表行 | 高 42/36，见 2.3 | 左栏、版本行、设置子项 |
| `MyCard` | 卡片 | 圆角 5、折叠 40 | 内容分组 |
| `MyComboBox`（+`MyComboBoxItem`） | **下拉菜单** | 圆角 3、1px 描边、13px、`MaxDropDownHeight 160`、项 `Padding 6,4` | 单选设置 |
| `MyMenuItem` + `ContextMenu` | **右键菜单** | 项高 26、图标 12×15、菜单圆角 3 | 右键菜单 |
| `MyCheckBox` | 复选框 | 方框 18×18 圆角 3、描边 1.1、对勾 12×12、文字 13px 左距 26、`MinHeight 20`、含 indeterminate | 布尔设置 |
| `MyRadioBox` / `MyRadioButton` | 单选框 / 导航胶囊 | 圆 18×18、文字左距 26；导航 27 高、圆角 13.5、图标 16 | 互斥设置 / 顶部导航 |
| `MySlider` | 滑杆 | 高 16、轨道 4、填充 2、滑块 10×10 圆 | 数值设置 |
| `MyTextBox` | 输入框 | `ValidateRules`（整数/黑名单/正则）、错误行 21、可多行 | 所有输入 |
| `MySearchBox` | 搜索框 | 高 40、放大镜 14 左距 14、清除 24×24 右距 10、文字 `Padding 32,0,40,0`、可选 60 宽「搜索」 | 搜索 |
| `MyHint` / `MyLoading` | 提示条 / 加载环 | 左竖条 3、圆角 2、`Padding 12,9`、Red/Blue/Yellow；加载环高 50、三态可点击重试 | 警告与加载 |
| `MyCollapseBar` / `MyToast` | 折叠栏 / 通知 | 头高 30、14 bold、三角 10×6 右距 12、内容缩进 6；Toast 圆角 8、图标 20 | 轻量折叠 / 全局通知 |
| `MyMsg*`（Text/Markdown/Input/Select/AuthServer/Login） | 模态框 | `MinWidth 400`、圆角 7、阴影 20/0.8、内边距 22；标题 23px 强调 + 2px 下划线；正文 15px；按钮右下 | 对话框 |
| `MySkin` / `MyImage` / `MyScrollViewer` / `MyVirtualizingElement` | 头像 / 图片 / 滚动（条宽 8）/ 虚拟化 | 皮肤 64×64 | 基础 |

### 6.2 「菜单 / 弹出」类控件详解（重构重点）

| 控件 | 触发 | 视觉 | 交互细节 |
|---|---|---|---|
| **`MyComboBox`** | 点击整行 | 圆角 3 描边盒，右侧 21.5 内边距放箭头；面板白底 + 圆角 3 + 1px 描边，`Placement=Bottom`、`VerticalOffset -1.5`、`Fade` 动画、最大高 160、**面板宽 = 触发器宽**（`DropDownWidthSync`）、无项时高 26 | 悬停底 `ColorBrush7`、字 `ColorBrush4`；打开/按下字变强调色；可编辑模式内嵌 `MyTextBox`（`Margin 1.5,0,21.5,0`）并支持逐项删除（`ComboBoxItemTemplateWithDelete` = 13px `MyListItem` + 20×20 `x`）；支持键盘上下选（`Application.xaml:420-520`、`MyComboBox.cs:85-214`） |
| **`ContextMenu` + `MyMenuItem`** | 右键（皮肤、实例行、收藏项等） | 圆角 3、白底、1px `ColorBrush1` 描边、`Margin 0,0,4,4`、阴影 0.4/4/2；整体透明度随窗口不透明度 | 项高 **26**、图标 12×15 左距 8、文字右留 40；悬停底 `ColorBrush6` + 字 `ColorBrush2`（100ms），离开 200ms 回退；**快捷键列已在模板中注释掉**（`Application.xaml:648-651`），当前不显示；无子菜单、无分组标题 |
| **「点击展开的下拉操作菜单」** | — | — | PCL-CE **没有**该控件：需要菜单时一律用 `ContextMenu` 或下拉框，行尾用图标按钮代替——这是与常见设计系统最大的差异 |
| ToolTip / `MyCard` 折叠 / `MyHint` 关闭 | 悬停 / 点标题 / 点 `x` | `ColorBrushToolTip #e5ffffff`；卡片右 10×6 三角展开 180°；提示条右侧 20×20 关闭 | 各处用 `ToolTipService.Placement`（Left/Right/Center）+`VerticalOffset` 精调；折叠高度动画 150ms 且首次展开才构建子项；Hint 关闭写入 `States.Hint.*` 持久化 |

---

## 7. 映射到 SwiftUI 设计系统

### 7.1 控件 / 布局映射

| PCL-CE | 目标组件 | 说明 |
|---|---|---|
| 窗口外壳 + 48px 标题栏 | `LauncherChrome` / `LauncherAppShell` | 保留 40pt 红绿灯安全区；PCL 是实色强调条，**不要照搬** |
| 顶部导航 `MyRadioButton ×4` | `LauncherTabBar` / `LauncherSegmentedControl` | PCL 嵌在标题栏内；我们 4 Tab（启动/下载/设置/更多）在侧栏，二选一需明确 |
| `PanMain` 左右分栏 | `LauncherPageLayout(sideWidth:)` | 我们默认 252；PCL 启动页 300、其余 120~170 → 建议「启动页 300 / 其余 220」 |
| 左栏行 `MyListItem` | `LauncherListRow` / `LauncherSidebarItem` | 需图标 16、副标题、右侧 hover 按钮、左侧 5px 选中条、36 行高 |
| `MyCard` + 标题 + 折叠 | `LauncherCard` + `LauncherCardHeader` + `LauncherExpander` | PCL 是「整卡折叠成标题条」，我们缺该形态 |
| `MyButton` / `MyIconButton` | `LauncherButton` / `LauncherIconButton` | 35 → medium 34、54 → large 44（可保留 52 胶囊）；图标按钮 25/28 ↔ 28/34 |
| `MyExtraButton` / `MyExtraTextButton` | 缺 `LauncherFloatingActionButton` / `LauncherButton(.large, fullWidth)` | 右下圆形按钮栈 / 高 52 胶囊贴底主按钮 |
| `MyComboBox` + Item | `LauncherDropdown` / `LauncherMenuItem` | 需「弹层与触发器等宽」；PCL 下拉项无图标 |
| `ContextMenu` + `MyMenuItem` | `LauncherMenu`（`LauncherMenuGroup`） | PCL 是右键、无分组、无快捷键；我们点击弹出、有分组与快捷键 → **需补 contextMenu 适配** |
| `MyCheckBox` / `MyRadioBox` / `MySlider` | `LauncherCheckbox` / `LauncherRadioCard` / `LauncherSlider` | PCL 方框 18、行高 20~28（比 44 紧凑）；滑杆高 16、滑块 10，热区需放大到 28 |
| `MyTextBox` + `ValidateRules` / `MySearchBox` | `LauncherTextField`（helper/error）/ `LauncherSearchField` | 需把「整数范围 / 黑名单」做成 validator；搜索框高 40 + 清除 + 可选搜索按钮 |
| `MyHint` / `MyLoading` | `LauncherBanner` / `LauncherSpinner` + `LauncherSkeleton` | PCL 提示条是「左 3px 竖条 + 圆角 2」；加载需保留「失败可点击重试」 |
| `MyCollapseBar` / `MyToast` / `MyMsg*` / `MySkin` | `LauncherExpander` / `LauncherToast` / `LauncherDialog` / `LauncherAvatar` | 均已存在；头像需 64/56/48 三档 + 右键菜单 |
| 内存可视化条 / 新闻瀑布流 / 分页卡 | 缺：`LauncherSegmentedBar` / `LauncherWaterfallGrid` / `LauncherPager` | 三段比例条 / 自适应列宽虚拟化 / 首页-上一页-页码-下一页 |
| 空状态卡 / 设置行 | `LauncherEmptyState` / `LauncherSettingRow` | 需「19px 强调标题 + 2px 下划线」紧凑版；行高建议参数化（28/34） |

### 7.2 设计系统目前缺少的控件

1. **右键上下文菜单**：`LauncherMenu` 只能点击展开；需 `.launcherContextMenu(groups:)`，复用 `LauncherMenuItem`，支持「无分组、纯文字项、行高 26」紧凑形态。
2. **卡片级折叠**：`LauncherExpander` 是列表内折叠；缺「整卡折叠成 40 高标题条 + 高度过渡 + 首次展开懒加载」的 `LauncherCollapsibleCard`。
3. **行尾 hover 操作组**：列表/侧栏行需要「悬停才出现的 1~3 个 25pt 图标按钮」，并自动扩展右侧预留宽度。
4. **浮层操作按钮栈**：右下角圆形按钮列（带进度环、可右键）。
5. **分页器** `LauncherPager`。
6. **多段比例条** `LauncherSegmentedBar`：4pt 高三段色用量可视化。
7. **瀑布流网格** `LauncherWaterfallGrid`：卡片上限宽 240、间距 14、虚拟化。
8. **紧凑下拉项 + 带校验数字输入**：`LauncherMenuItem` 需 `compact` 变体；`LauncherNumberField` 需 `validator`（现有实现无范围校验）。

### 7.3 移植时必须注意的差异

| 项 | PCL-CE | 我们的设计系统 |
|---|---|---|
| 标题栏 | 48pt 实色强调条，导航嵌在其中 | 透明标题栏 + 红绿灯安全区 → **保留我们的** |
| 投影 / 模糊 | 左栏 4pt 投影、卡片/Toast 阴影、满屏毛玻璃 | 平面化：0 投影 / 0 模糊 → 左栏改 `1px stroke` + `surfaceElevated` |
| 圆角 / 控件高 | 卡片 5、按钮 3、菜单 3、Toast 8、对话框 7；高 28/35/42/52/54 | 圆角刻度 6/10/14/18/24/pill（用 6、10）；高 28/34/44（+52 胶囊） |
| 行高 / 间距 | 侧栏 36、列表 42、资源 64；页面 25、卡片间 15、设置行 28+9 | 行高需三档；间距 4pt 体系 24/16/28+8 |
| 分栏 | 左列 Auto、无分割线 | 固定 `sideWidth` + 16 间距 → 改为「固定宽 + 1px 分割线」 |
| 字号 | 11/12/12.5/13/13.5/14/15/16/19/20/23 | 10/11/12/13/14/15/22/30 |
