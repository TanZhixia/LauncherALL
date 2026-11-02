# PCL-CE 布局重构说明

参考源码：`PCL2 社区版（PCL-CE）`，克隆在 `/tmp/pcl-ce`（分析用，不入库）。
原则：**布局与控件摆布向 PCL-CE 靠齐，控件实现全部使用本项目的 LauncherUI 组件**（不用 WPF 控件，也不照搬其视觉）。

## 1. PCL-CE 的整体结构（源码结论）

| 区域 | PCL-CE 做法 | 本项目对应 |
|---|---|---|
| 标题栏 | 自定义标题栏 48px：左侧 Logo、中部 4 个图标+文字导航（启动 / 下载 / 设置 / 工具）、右侧窗口按钮 | `LauncherAppShell` 顶栏 48pt：品牌 + 4 个导航胶囊（启动 / 下载 / 设置 / 更多）+ 主题/账户/设置 |
| 内容区 | 每页 = 左面板（`PanLeft`，约 252~272） + 右内容（`PanMain`） | `LauncherPageLayout(sideWidth:) { LauncherSidePanel } main: { LauncherMainPanel }` |
| 左面板 | 列表/分类：图标条目、搜索框、分组标题、底部操作按钮 | `LauncherSidePanel` + `LauncherSidePanelGroup` + `LauncherListRow` |
| 右内容 | 卡片式区块从上到下排列 | `LauncherMainPanel` + `LauncherPanelHeader` + `LauncherCard`/`GlassPanel` |
| 设置页 | 左分类三组：游戏（启动/Java/管理/联机）、启动器（个性化/语言/杂项/更新）、关于（软件信息/反馈/日志） | 设置页左分类：游戏（启动/Java/性能）、启动器（更新与语言/外观/账户）、关于（关于/日志） |
| 下载页 | 左：Minecraft / 社区资源 / 加载器 分类 + 版本列表；右：安装选项与进度 | 下载页左：Minecraft（正式/快照/远古）/ 社区资源；右：版本详情 + 安装 + 磁盘/下载源 |
| 工具页 | 左：工具分类列表；右：工具内容 | 更多页左：工具 / 快捷操作 / 关于；右：对应内容（含日志与诊断） |
| 启动页 | 左：实例列表 + 账户；右：启动按钮、状态、启动日志、快捷入口 | 启动页同构（已实现） |

## 2. 本轮新增的通用组件

| 组件 | 用途 |
|---|---|
| `LauncherPageLayout` | 页面骨架：左面板 + 右内容 + 统一内边距 |
| `LauncherSidePanel` / `LauncherSidePanelGroup` | 左列表面板：标题/计数/搜索/工具槽/底部固定区 + 分组标题 |
| `LauncherMainPanel` | 右内容容器：窗口内可滚，离屏渲染自动静态堆叠 |
| `LauncherPanelHeader` | 右内容顶部大标题 + 说明 + 右侧操作槽 |
| `LauncherSettingRow` | 设置行：标题/说明/提示 + 右侧控件 + 分隔线 |
| `LauncherHintIcon` / `.launcherTooltip` | 说明气泡 |
| `LauncherMenu` / `LauncherMenuButton` / `LauncherIconMenu` / `.launcherContextMenu` | **下拉菜单 / "…" 菜单 / 右键菜单**（图标、说明、快捷键、危险项、禁用态、分组） |
| `LauncherExpander` | 可折叠分组（高级选项） |
| `LauncherNumberField` | 数字输入（范围/步长/单位） |

详细逐文件、逐行号的分析见 [PCL-CE-LAYOUT.md](PCL-CE-LAYOUT.md)（390 行，由子代理通读 XAML/CS 生成）。

## 3. 已完成页面（全部四个一级页面，交互全部真实）

- **启动**：左 300pt 面板 = 实例列表（搜索/计数/footer：大启动按钮 + 版本下拉 + 账户）+ 实例右键菜单；右侧 = 当前实例概览 / 真实启动日志 / 快捷入口（新建实例 / 导入整合包 / 刷新）/ 最近启动记录。实例重命名、复制、校验、删除（废纸篓）均为真实文件操作。
- **下载**：左 272 = 标题 + 搜索 + 排序刷新 + Minecraft 类型筛选 + 版本列表（已装标记/右键菜单）+ 社区资源分类 + footer（刷新/队列数）；右 = 版本详情（真实 Java 要求/资源索引）/ 安装选项（资源文件 + 校验已有文件）/ 安装队列 / 磁盘占用与清理 / 下载源；社区分类 = Modrinth 真实搜索 + 详情 + 安装（含 `.mrpack` 整合包）。
- **设置**：左 236 = 三组分类（游戏 / 启动器 / 关于，Java 挂数量 badge）；右 = 分类内容卡片（`LauncherSettingRow` 排版）+ 高级折叠 + 外观「当前/默认」对比 + 常驻保存条（真实 `lastSavedAt`）。检查更新、日志导出、旧版本清理、账户切换、Java 探针、语言重启均为真实动作；账户分类额外提供微软正版登录（设备码流 + Keychain 令牌 + 多账户切换）。
- **更多**：左 272 = 工具 6 项（右键菜单/收藏置顶）+ 快捷操作 + 关于 + footer 设计系统入口；右 = 日志与诊断（真实日志、导出、诊断信息）/ 实例备份（`ditto` 真实 zip、恢复、删除）/ 模组管理（真实扫描 + 启停改名）/ 截图相册（真实缩略图）/ 社区外链 / 快捷键（只列真实注册项）/ 关于 / 快捷操作（真实目录与窗口重置）。

## 4. 说明与取舍

- PCL-CE 本身**没有**点击展开的下拉操作菜单（只有 `MyComboBox` 与右键菜单）；本项目按用户要求补了 `LauncherMenu` / `LauncherMenuButton` / `LauncherIconMenu` / `.launcherContextMenu`，并已用于设置行、列表行、页面 header。
- PCL-CE 左栏宽度由内容撑出（引擎页 300、其余 120~170）；本项目为视觉统一使用固定宽度（启动 300 / 下载 272 / 设置 236），未做可拖拽分割线。
- 视觉仍为本项目的平面双主题体系（无阴影/模糊/渐变），不复制 PCL-CE 的强调色标题栏与主题实现。

## 5. 验证口径

- `swift build` 0 error、`swift test` 121/121（全部离线，含四个页面的交互/服务层用例）。
- `--export-app-snapshots` 16 张（2 主题 × 4 页 × 2 窗口尺寸），最小窗口 1080×720 右侧首屏不纵向滚动；离屏模式下无"加载中"残留。
- 启动页实机验证：`--launch` 可加载 Fabric Loader 与玩家模组。
- 交互验收：每个可点控件都有真实效果或明确的禁用原因（见 [APP-UI.md](APP-UI.md) 第 3 节交互契约）。
