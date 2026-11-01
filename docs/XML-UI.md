# XML UI 工具链（LauncherXML）

用 XML 描述界面，运行时渲染成 SwiftUI。控件、主题、间距、圆角全部复用现有设计系统，
所以 XML 写出来的界面与手写 SwiftUI 在视觉上完全一致。

```
XML 源码 ──解析──▶ XMLNode 树 ──诊断──▶ 状态(.xml state) / 动作 / 数据源
                                   └──渲染──▶ SwiftUI 视图（AnyView）
```

## 1. 文件与命令

| 位置 | 说明 |
|---|---|
| `Sources/LauncherUI/XML/` | 引擎：解析器、状态、动作、渲染器、布局与基础标签 |
| `Sources/LauncherUI/XML/Components/` | 控件标签注册（`XMLControls.swift`）与容器类标签注册（`XMLSurfaces.swift`） |
| `Sources/LauncherUI/Resources/XML/*.xml` | 内置示例（资源包，运行时可加载） |
| `Samples/XML/` | 可直接用命令行渲染的设计稿 |
| `Sources/LauncherUI/Gallery/XMLDesignerPage.swift` | App 内可视化设计器 |

```bash
# 校验：打印诊断，退出码 0 = 通过
swift run MCLauncher --validate-xml Samples/XML/launcher-home.xml

# 渲染成 PNG（可用于设计评审 / CI 截图比对）
swift run MCLauncher --render-xml Samples/XML/launcher-home.xml out.png --theme porcelain --width 1200 --height 900

# 列出内置示例
swift run MCLauncher --list-xml-samples
```

App 内：左侧导航「工具 → XML 设计器」，左边源码、右边实时预览（1180pt 设计画布等比缩放），可切示例、可编辑、带诊断。

## 2. 文档结构

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ui title="示例">
  <state>
    <bool name="isLaunching" value="false"/>
    <string name="username" value="Steve"/>
    <int name="memory" value="4096"/>
    <double name="scale" value="1.0"/>
  </state>
  <actions>
    <action name="launch"/>      <!-- 仅声明，宿主需注册同名闭包 -->
  </actions>
  ...页面内容...
</ui>
```

- 根元素必须是 `<ui>`，可带 `title`。
- `<state>` 只允许 `string / bool / int / double` 四种类型，必须带 `name` 与 `value`。
- `<actions>` 里的声明用于文档与校验提示；实际动作由宿主 `XMLActionRegistry` 注册。

## 3. 通用属性（所有元素可用）

| 属性 | 说明 |
|---|---|
| `if` | 条件渲染：`if="{state.showAdvanced}"`、`if="{item.installed}"`、`if="false"` |
| `padding` | 元素四周留白，支持数字或间距令牌 |
| `width` / `height` | 固定尺寸（数字）。`<progress>` / `<skeleton>` 的 width/height 由标签自身消费，通用层不会再套一层 frame |
| `max-width` / `min-height` | 尺寸约束 |
| `opacity` | 0–1 |

**间距令牌**：`xxs(2) xs(4) sm(8) md(12) lg(16) xl(24) xxl(32) xxxl(48)`
**圆角令牌**：`sm(6) md(10) lg(14) xl(18) xxl(24) pill`
**间距/圆角属性可写令牌名，也可写数字**，例如 `spacing="lg"`、`radius="pill"`。

## 4. 表达式与绑定

| 写法 | 说明 |
|---|---|
| `{state.name}` | 读取状态变量 |
| `{item.field}` | 读取当前 `<foreach>` 条目字段 |
| `{别名.field}` | `foreach as="inst"` 时用 `{inst.title}` |
| `{name}` | 省略 `state.` 的简写 |

- 任意字符串属性与文本内容都支持插值。
- 表单控件通过 `bind="stateName"` 双向绑定。
- 事件用 `onTap`：
  - `onTap="launch"`：调用宿主注册的动作
  - `onTap="set:channel=beta"`：设置状态
  - `onTap="toggle:showAdvanced"`：切换布尔
  - `onTap="inc:progress=25"` / `"dec:progress=25"`：整数增减

## 5. 布局标签

| 标签 | 属性 | 说明 |
|---|---|---|
| `<vstack>` | `spacing` `align="leading\|center\|trailing"` `full-width` | 纵向堆叠 |
| `<hstack>` | `spacing` `align="top\|center\|bottom"` | 横向堆叠 |
| `<zstack>` | — | 叠放 |
| `<scroll>` | `spacing` `align` | 可滚动区域 |
| `<grid>` | `columns` `spacing` | 等宽栅格；内部可直接放 `<foreach>`，每个条目占一格 |
| `<spacer>` | `min-length` | 弹性空白 |
| `<divider>` | `full-width` | 1px 分割线 |
| `<panel>` | `level="subtle\|regular\|strong"` `radius` `spacing` | 面板（玻璃层级已平面化） |
| `<card>` | `level` `radius` `spacing` | 卡片 |
| `<section>` | `title` `subtitle` `spacing` | 带小标题的区块 |
| `<page>` | `title` `subtitle` `spacing` | 整页骨架（含滚动与最大宽度） |
| `<if>` | `test` | 条件块 |
| `<foreach>` | `in`（数据源名） `as`（条目别名） `spacing` `item-spacing` `layout="vstack\|hstack"` | 列表渲染 |

## 6. 基础标签

| 标签 | 属性 | 示例 |
|---|---|---|
| `<text>` | `style` `tone` `content` `line-limit`，或直接写文本内容 | `<text style="title">1.21.4</text>` |
| `<label>` | `tone` | `<label>当前实例</label>` |
| `<mono>` | `tone` `size` | `<mono content="4096 MB" />` |
| `<icon>` | `name`（SF Symbol） `size` `tone` `label` | `<icon name="play.fill" tone="accent" />` |

`style`：`display title sectionTitle headline body bodyStrong caption micro label mono monoSmall`
`tone`：`primary secondary tertiary accent onAccent success warning danger`

## 7. 控件标签

| 标签 | 属性 |
|---|---|
| `<button>` | `title` `icon` `variant="primary\|secondary\|ghost\|danger"` `size="small\|medium\|large"` `loading` `disabled` `full-width` `shortcut` `onTap` |
| `<iconbutton>` | `icon` `variant` `size` `label` `onTap` |
| `<chip>` | `title` `selected` `icon` `onTap` |
| `<badge>` | `text` `tone="neutral\|accent\|success\|warning\|danger\|info"` `icon` |
| `<statusdot>` | `tone` `pulsing` |
| `<textfield>` | `placeholder` `bind` `icon` `helper` `error` `disabled` `onSubmit` |
| `<searchfield>` | `bind` `placeholder` `onSubmit` |
| `<securefield>` | `placeholder` `bind` `icon` |
| `<textarea>` | `placeholder` `bind` `min-height` |
| `<toggle>` | `title` `bind` `subtitle` |
| `<checkbox>` | `title` `bind` |
| `<radiocard>` | `title` `subtitle` `icon` `selected` `onTap` |
| `<slider>` | `bind` `min` `max` `label` `value-text` |
| `<stepper>` | `bind` `min` `max` `label` `unit` |
| `<segmented>` | `bind` + 子标签 `<option value="..." title="..." icon="..."/>` |
| `<dropdown>` | `bind` `placeholder` + 子标签 `<option .../>` |

## 8. 容器 / 反馈 / 导航标签

| 标签 | 属性 |
|---|---|
| `<listrow>` | `title` `subtitle` `icon` `badge` `selected` `onTap` |
| `<sectionheader>` | `title` `subtitle` |
| `<empty>` | `icon` `title` `message` `action-title` `onTap` |
| `<avatar>` | `name` `icon` `size` `online` |
| `<keyvalue>` | `key` `value` `mono="true\|false"` |
| `<stattile>` | `value` `label` `icon` |
| `<progress>` | `value`（省略 = 不确定态） `max` `label` `tone` `height` |
| `<spinner>` | `size` `tone` |
| `<skeleton>` | `width` `height` `radius` |
| `<banner>` | `title` `message` `tone` `action-title` `onTap` |
| `<toast>` | `title` `message` `tone` `onClose` |
| `<sidebaritem>` | `title` `icon` `badge` `selected` `onTap` |
| `<tabs>` | `bind` + 子标签 `<option .../>` |
| `<dialog>` | `title` `message` `primary`（主按钮文案） `secondary` `tone="primary\|danger"` `onPrimary` `onSecondary` |

## 9. 完整示例

```xml
<ui title="启动器首屏">
  <state>
    <bool name="isLaunching" value="false"/>
    <string name="launchStatus" value="就绪"/>
  </state>
  <vstack spacing="lg" padding="xl">
    <section title="当前实例">
      <hstack spacing="md">
        <text style="title">1.21.4 · Fabric 0.16.9</text>
        <badge text="Fabric" tone="neutral"/>
        <spacer/>
        <button title="开始游戏" icon="play.fill" size="large"
                loading="{state.isLaunching}" onTap="launch"/>
      </hstack>
      <mono content="{state.launchStatus}" />
    </section>
    <section title="已安装实例">
      <vstack spacing="xs">
        <foreach in="instances" as="inst">
          <listrow title="{inst.title}" subtitle="{inst.subtitle}" badge="{inst.tag}" />
        </foreach>
      </vstack>
    </section>
  </vstack>
</ui>
```

## 10. 扩展标签

```swift
@MainActor
func registerMyElements(in registry: XMLElementRegistry) {
    registry.register("mytag") { node, ctx in
        let title = node.required("title", ctx)                 // 必填，缺失会进诊断
        let onTap = node.tapHandler(ctx)                        // 支持 onTap 全套写法
        return AnyView(
            LauncherButton(title, variant: .secondary) { onTap?() }
        )
    }
}
```
然后在 `registerXxxElements(in:)` 里调用，并确认 `XMLElementRegistry.makeDefault()` 已包含该注册函数。

## 11. 常见诊断

| 诊断 | 原因 |
|---|---|
| `根元素必须是 <ui>` | 根标签写错 |
| `未知元素 <xxx>` | 标签名拼错 / 未注册 |
| `缺少必填属性 title` | 该标签需要该属性 |
| `数据源 "xxx" 不存在` | `<foreach in>` 的名字不在 `XMLDataSources` 里 |
| `动作 "xxx" 未注册` | `onTap` 的动作没有在宿主注册 |
