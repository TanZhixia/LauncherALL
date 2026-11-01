# 方块启动器 · Minecraft Launcher UI Kit（SwiftUI）

一套用 **Swift 6 / SwiftUI** 写的 Minecraft 启动器 **UI 模板**：极简平面化设计令牌 + 一深一浅两套主题 + 30 多个控件 + 可视化组件画廊。
本仓库当前只做 **UI 层**（不含版本解析、资源下载、Java 检测、账户认证等启动逻辑），用于先把视觉与组件系统定稿。

## 快速开始

```bash
# 直接运行（macOS 15+ / Xcode 26+ / Swift 6）
swift run MCLauncher

# 或用 Xcode 打开 SPM 包，跑 MCLauncher scheme
open Package.swift

# 离屏导出深/浅两套主题 × 8 个页面的截图（无显示器环境也可用）
swift run MCLauncher --export-snapshots Snapshots
python3 tools/make_contact_sheet.py   # 需要 Pillow，生成对比图
```

启动后左侧是页面导航（主题工作台 / 按钮 / 输入 / 选择 / 容器 / 反馈 / 导航 / 实战样张）；
侧栏底部两个圆点可即时切换深/浅主题；「主题工作台」里能调边框强度与圆角缩放。

## 设计取向

- **简约**：中性灰阶 + 单一强调色（深色主题近白、浅色主题近黑），状态色低饱和。
- **平面化**：没有毛玻璃、没有投影、没有渐变、没有发光；层级只由「分层底色 + 1px 边框」表达。
- **两套主题**：`graphite`（深色）/ `porcelain`（浅色），只换色不换结构。
- 详见 [`docs/DESIGN-SYSTEM.md`](docs/DESIGN-SYSTEM.md)。

## 目录结构

```
Sources/
  LauncherUI/                 # 设计系统 + 组件库（可复用到正式产品）
    Core/                     # 令牌、主题、排版、面板、动效、页面骨架
    Components/               # 按钮 / 输入 / 选择 / 容器 / 反馈 / 导航
    Gallery/                  # 组件画廊页（本模板的可视化验收页）
    Shell/                    # 侧栏外壳 + 窗口配置
  MCLauncher/                 # 可执行 App 入口 + 离屏截图导出器
docs/
  DESIGN-SYSTEM.md            # 设计系统说明（令牌 / 主题 / 规范 / 检查清单）
  API-CONTRACT.md             # 组件 API 契约（并行开发时的唯一事实来源）
Snapshots/                    # 导出的主题 × 页面效果图 + 对比图（生成产物，已 gitignore）
tools/make_contact_sheet.py   # 生成主题对比图（Pillow）
```

## 效果预览

`Snapshots/` 下是 **2 套主题 × 8 个页面** 的离屏渲染图，另附交付用对比图：

| 对比图 | 内容 |
|---|---|
| `sheet-themes-demo.png` | 同一套启动器首屏在深色 / 浅色主题下的对照（核心验收图） |
| `sheet-themes-studio.png` | 主题工作台 + 跨主题一致性对照 |
| `sheet-buttons.png` / `sheet-inputs.png` / `sheet-selection.png` / `sheet-surfaces.png` / `sheet-feedback.png` | 各组控件在深浅主题下的对照 |

> 说明：截图由 `ImageRenderer` 离屏渲染。平面化后面板是真纯色，与真机一致；仅 AppKit 背书的控件（输入框、下拉菜单）在离屏模式下用同布局静态等价物渲染（`launcherSnapshotMode` 环境开关）。

## 加一套主题

见 [`docs/DESIGN-SYSTEM.md`](docs/DESIGN-SYSTEM.md) 第 3 节：工厂方法声明 → 加入 `LauncherThemes.all` → 全站自动适配。

## 加一个组件

1. 只用 `theme.colors.*` / `.textStyle(...)` / `LauncherSpace` / `LauncherRadius` / `GlassPanel`，禁止投影、模糊、渐变；
2. Public init 写进 `docs/API-CONTRACT.md`；
3. 在对应 Gallery 页加一组状态展示（默认 / 选中 / 禁用 / 加载 / 错误）。

## 已知边界

- 未接入 Minecraft 启动逻辑（版本清单、资源下载、Java 运行时、账户认证）。
- 未使用官方字体与素材，全部为系统字体 + SF Symbols + 自绘方块图形。
