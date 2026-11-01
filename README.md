# 方块启动器 · Minecraft Launcher UI Kit（SwiftUI）

一套 **Swift 6 / SwiftUI 编写的 Minecraft 启动器 UI 模板**：设计令牌 + 6 套游戏主题 + 毛玻璃组件库 + 可视化组件画廊。
本仓库当前只做 **UI 模板层**（不含下载、版本解析、Java 检测等启动逻辑），用于先把视觉与组件系统定稿。

## 快速开始

```bash
# 直接运行（macOS 15+，Xcode 26+/Swift 6）
swift run MCLauncher

# 或用 Xcode 打开 SPM 包，跑 MCLauncher scheme
open Package.swift

# 离屏导出全部主题 × 全部页面的截图（无显示器环境也可用）
swift run MCLauncher --export-snapshots Snapshots
```

启动后左侧是页面导航（主题工作台 / 按钮 / 输入 / 选择 / 容器 / 反馈 / 导航 / 实战样张），
侧栏底部 6 个圆点可即时切换主题；「主题工作台」里能调玻璃浓度与圆角缩放。

## 效果预览

`Snapshots/` 下是 **6 套主题 × 8 个页面** 的离屏渲染图（`--export-snapshots` 生成），另附交付用对比图：

| 对比图 | 内容 |
|---|---|
| `sheet-themes-demo.png` | 同一套启动器首屏在 6 套主题下的对照（核心验收图） |
| `sheet-themes-studio.png` | 主题工作台 + 跨主题一致性对照 |
| `sheet-buttons.png` / `sheet-inputs.png` / `sheet-selection.png` / `sheet-surfaces.png` | 各组控件在 6 主题下的对照 |

> 说明：截图由 `ImageRenderer` 离屏渲染，玻璃材质用主题令牌等价模拟（真实 App 里是系统 `Material` 实时采样 + 模糊，观感更通透）；输入框等 AppKit 控件在离屏模式下用同布局的静态等价物渲染。
>
> 重新生成：`swift run MCLauncher --export-snapshots Snapshots && python3 tools/make_contact_sheet.py`（需要 Pillow）。

## 目录结构

```
Sources/
  LauncherUI/                 # 设计系统 + 组件库（可复用到正式产品）
    Core/                     # 令牌、主题、排版、玻璃、动效、页面骨架
    Components/               # 按钮 / 输入 / 选择 / 容器 / 反馈 / 导航
    Gallery/                  # 组件画廊页（本模板的可视化验收页）
    Shell/                    # 侧栏外壳 + 窗口配置
  MCLauncher/                 # 可执行 App 入口 + 离屏截图导出器
docs/
  DESIGN-SYSTEM.md            # 设计系统说明（令牌 / 主题 / 规范 / 检查清单）
  API-CONTRACT.md             # 组件 API 契约（并行开发时的唯一事实来源）
Snapshots/                    # 导出的主题 × 页面效果图 + 对比图
tools/make_contact_sheet.py   # 生成主题对比图（Pillow）
```

## 加一套主题

见 `docs/DESIGN-SYSTEM.md` 第 3 节，三步：工厂方法声明 → 加入 `LauncherThemes.all` → 全站自动适配。

## 加一个组件

1. 只用 `theme.colors.*` / `.textStyle(...)` / `LauncherSpace` / `LauncherRadius` / `GlassPanel`；
2. Public init 写进 `docs/API-CONTRACT.md`；
3. 在对应 Gallery 页加一组状态展示（默认 / hover / 选中 / 禁用 / 加载）。

## 已知边界

- 未接入 Minecraft 启动逻辑（版本清单、资源下载、Java 运行时、账户认证）。
- 未使用官方字体与素材，全部为系统字体 + SF Symbols + 自绘方块图形。
