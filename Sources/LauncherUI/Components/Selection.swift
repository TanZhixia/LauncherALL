import SwiftUI

// MARK: - Toggle

/// 开关：44×26 自绘胶囊（20pt 圆点），整行（含文字）都可点击切换。
public struct LauncherToggle: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let title: String
    @Binding private var isOn: Bool
    private let subtitle: String?

    // 契约指定的胶囊尺寸
    private let capsuleWidth: CGFloat = 44
    private let capsuleHeight: CGFloat = 26
    private let knobSize: CGFloat = 20

    /// 创建开关，可带副标题说明。
    public init(_ title: String, isOn: Binding<Bool>, subtitle: String? = nil) {
        self.title = title
        self._isOn = isOn
        self.subtitle = subtitle
    }

    public var body: some View {
        Button(action: toggle) {
            HStack(spacing: LauncherSpace.md) {
                VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                    Text(title)
                        .textStyle(.body)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .textStyle(.micro, tone: .tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: LauncherSpace.sm)
                capsule
            }
            .frame(minHeight: LauncherControl.medium)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .launcherPointer()
        .accessibilityValue(Text(isOn ? "开启" : "关闭"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// 胶囊主体：开启为 accent 渐变 + 光晕，关闭为 surfaceActive。
    private var capsule: some View {
        ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(isOn ? AnyShapeStyle(theme.primaryGradient) : AnyShapeStyle(theme.colors.surfaceActive))
                .overlay {
                    // 关闭态用略强描边：surfaceActive 在浅色主题下与背景过近
                    Capsule(style: .continuous)
                        .strokeBorder(isOn ? theme.colors.stroke : theme.colors.strokeStrong, lineWidth: 1)
                }
                .shadow(
                    color: isOn ? theme.colors.accent.opacity(0.3) : Color.clear,
                    radius: 5,
                    x: 0,
                    y: 2
                )
            Circle()
                .fill(Color.white)
                .frame(width: knobSize, height: knobSize)
                .shadow(color: theme.colors.shadow.opacity(0.5), radius: 2.5, x: 0, y: 1)
                .padding(.leading, (capsuleHeight - knobSize) / 2)
                .offset(x: isOn ? capsuleWidth - capsuleHeight : 0)
        }
        .frame(width: capsuleWidth, height: capsuleHeight)
        .launcherAnimation(reduceMotion ? nil : LauncherMotion.spring, value: isOn)
    }

    /// 切换开关状态。
    private func toggle() {
        if reduceMotion {
            isOn.toggle()
        } else {
            withAnimation(LauncherMotion.spring) { isOn.toggle() }
        }
    }
}

// MARK: - Checkbox

/// 复选框：18×18 圆角方块，整行（含文字）可点击。
public struct LauncherCheckbox: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let title: String
    @Binding private var isOn: Bool

    // 契约指定的方块尺寸
    private let boxSize: CGFloat = 18
    private let boxRadius: CGFloat = 5

    /// 创建复选框。
    public init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    public var body: some View {
        Button(action: toggle) {
            HStack(spacing: LauncherSpace.sm) {
                box
                Text(title)
                    .textStyle(.body)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(minHeight: LauncherControl.medium)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .launcherPointer()
        .accessibilityValue(Text(isOn ? "已勾选" : "未勾选"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// 勾选框：选中 accent 渐变 + 勾，未选中内凹底 + 描边。
    private var box: some View {
        ZStack {
            RoundedRectangle(cornerRadius: boxRadius, style: .continuous)
                .fill(isOn ? AnyShapeStyle(theme.primaryGradient) : AnyShapeStyle(theme.colors.surfaceSubtle))
            RoundedRectangle(cornerRadius: boxRadius, style: .continuous)
                .strokeBorder(isOn ? theme.colors.accent : theme.colors.strokeStrong, lineWidth: 1)
            if isOn {
                Image(systemName: "checkmark")
                    .textStyle(.caption, tone: .onAccent)
                    .font(LauncherTextStyle.caption.font.weight(.bold))
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(width: boxSize, height: boxSize)
        .launcherAnimation(reduceMotion ? nil : LauncherMotion.spring, value: isOn)
    }

    /// 切换勾选状态。
    private func toggle() {
        if reduceMotion {
            isOn.toggle()
        } else {
            withAnimation(LauncherMotion.spring) { isOn.toggle() }
        }
    }
}

// MARK: - RadioCard

/// 单选卡片：玻璃底 + 左侧单选圆点，选中时强调描边与柔和强调底。
public struct LauncherRadioCard: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let title: String
    private let subtitle: String?
    private let systemImage: String?
    private let isSelected: Bool
    private let action: () -> Void

    /// 创建单选卡片。
    public init(
        _ title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: LauncherSpace.sm) {
                radioDot
                if let systemImage {
                    Image(systemName: systemImage)
                        .textStyle(.body, tone: isSelected ? .accent : .secondary)
                }
                VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                    Text(title)
                        .textStyle(.bodyStrong)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .textStyle(.micro, tone: .tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, LauncherSpace.md)
            .padding(.vertical, LauncherSpace.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                .fill(theme.colors.accentSoft)
                .opacity(isSelected ? 1 : 0)
        }
        .glassBackground(level: .subtle, cornerRadius: LauncherRadius.md)
        .overlay {
            RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                .strokeBorder(isSelected ? theme.colors.accent : theme.colors.stroke, lineWidth: 1)
        }
        .launcherAnimation(reduceMotion ? nil : LauncherMotion.smooth, value: isSelected)
        .launcherHoverEffect(scale: 1.004)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// 单选圆点：选中时填充强调色内点。
    private var radioDot: some View {
        ZStack {
            Circle()
                .strokeBorder(isSelected ? theme.colors.accent : theme.colors.strokeStrong, lineWidth: 1.5)
            if isSelected {
                Circle()
                    .fill(theme.colors.accent)
                    .frame(width: LauncherSpace.sm, height: LauncherSpace.sm)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .frame(width: LauncherSpace.lg, height: LauncherSpace.lg)
        .launcherAnimation(reduceMotion ? nil : LauncherMotion.spring, value: isSelected)
    }
}

// MARK: - Slider

/// 滑块：自绘轨道 + 白色拇指，支持点击定位与拖动，左侧 label / 右侧 valueText。
public struct LauncherSlider: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDragging = false

    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let label: String?
    private let valueText: String?

    // 契约指定的轨道 / 拇指尺寸
    private let trackHeight: CGFloat = 4
    private let thumbDiameter: CGFloat = 14

    /// 创建滑块，默认 0...1 区间。
    public init(
        value: Binding<Double>,
        range: ClosedRange<Double> = 0...1,
        label: String? = nil,
        valueText: String? = nil
    ) {
        self._value = value
        self.range = range
        self.label = label
        self.valueText = valueText
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.sm) {
            if label != nil || valueText != nil {
                header
            }
            track
        }
    }

    /// 顶部说明行：固定行高，保证拖动时布局不跳动。
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: LauncherSpace.sm) {
            if let label {
                Text(label)
                    .textStyle(.caption, tone: .secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: LauncherSpace.sm)
            if let valueText {
                LauncherMonoText(valueText, tone: .secondary)
            }
        }
        .frame(height: LauncherSpace.lg)
    }

    /// 轨道 + 已选段 + 拇指，整体接收拖拽手势。
    private var track: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let usable = max(width - thumbDiameter, 1)
            let ratio = ratio(for: value)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.colors.surfaceSubtle)
                    .frame(width: width, height: trackHeight)
                    .overlay {
                        Capsule()
                            .strokeBorder(theme.colors.stroke, lineWidth: 1)
                    }
                Capsule()
                    .fill(theme.primaryGradient)
                    .frame(width: thumbDiameter / 2 + usable * ratio, height: trackHeight)
                thumb
                    .offset(x: usable * ratio)
            }
            .frame(width: width, height: thumbDiameter)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !isDragging { isDragging = true }
                        updateValue(atX: drag.location.x, usable: usable)
                    }
                    .onEnded { _ in isDragging = false }
            )
        }
        .frame(height: LauncherSpace.xl)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label ?? "滑块"))
        .accessibilityValue(Text(valueText ?? fallbackValueText))
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment:
                value = min(range.upperBound, value + step)
            case .decrement:
                value = max(range.lowerBound, value - step)
            @unknown default:
                break
            }
        }
    }

    /// 白色拇指：拖动时轻微放大。
    private var thumb: some View {
        Circle()
            .fill(Color.white)
            .frame(width: thumbDiameter, height: thumbDiameter)
            .shadow(color: theme.colors.shadow.opacity(0.55), radius: 3, x: 0, y: 1)
            .scaleEffect(isDragging ? 1.1 : 1)
            .launcherAnimation(reduceMotion ? nil : .easeOut(duration: LauncherMotion.fast), value: isDragging)
    }

    /// 当前值归一化到 0...1。
    private func ratio(for current: Double) -> CGFloat {
        guard range.upperBound > range.lowerBound else { return 0 }
        let raw = (current - range.lowerBound) / (range.upperBound - range.lowerBound)
        return CGFloat(min(max(raw, 0), 1))
    }

    /// 根据手指 x 坐标更新绑定值。
    private func updateValue(atX x: CGFloat, usable: CGFloat) {
        guard range.upperBound > range.lowerBound else { return }
        let clamped = min(max(x - thumbDiameter / 2, 0), usable)
        let ratio = Double(clamped / usable)
        value = range.lowerBound + ratio * (range.upperBound - range.lowerBound)
    }

    /// 未提供 valueText 时的无障碍读数。
    private var fallbackValueText: String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(rounded)
    }
}

// MARK: - 分段选项

/// 分段控件的单个选项：值 + 标题 + 可选图标。
public struct LauncherSegment<Value: Hashable>: Identifiable {
    public let id: Value
    public let title: String
    public let systemImage: String?

    /// 创建一个分段选项。
    public init(id: Value, title: String, systemImage: String? = nil) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
    }
}

// MARK: - SegmentedControl

/// 分段控件：胶囊凹槽容器，选中项用 surfaceElevated + 阴影滑动过渡。
public struct LauncherSegmentedControl<Value: Hashable>: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var indicator

    private let options: [LauncherSegment<Value>]
    @Binding private var selection: Value

    /// 创建分段控件，选项等宽排列。
    public init(options: [LauncherSegment<Value>], selection: Binding<Value>) {
        self.options = options
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: LauncherSpace.xxs) {
            ForEach(options) { option in
                segmentButton(option)
            }
        }
        .padding(LauncherSpace.xxs)
        .frame(height: LauncherControl.medium)
        .background {
            Capsule(style: .continuous)
                .fill(theme.colors.surfaceSubtle)
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(theme.colors.stroke, lineWidth: 1)
        }
    }

    /// 单个分段按钮：选中态由 matchedGeometry 承载滑块。
    private func segmentButton(_ option: LauncherSegment<Value>) -> some View {
        let selected = option.id == selection
        return Button {
            select(option.id)
        } label: {
            HStack(spacing: LauncherSpace.xs) {
                if let systemImage = option.systemImage {
                    Image(systemName: systemImage)
                        .textStyle(.caption, tone: selected ? .primary : .secondary)
                        .font(LauncherTextStyle.caption.font.weight(.medium))
                }
                Text(option.title)
                    .textStyle(.bodyStrong, tone: selected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, LauncherSpace.md)
            .frame(maxWidth: .infinity)
            .frame(height: LauncherControl.medium - LauncherSpace.xs)
            .contentShape(Capsule(style: .continuous))
            .background {
                if selected {
                    Capsule(style: .continuous)
                        .fill(theme.colors.surfaceElevated)
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(theme.colors.strokeStrong, lineWidth: 1)
                        }
                        .shadow(color: theme.colors.shadow.opacity(0.28), radius: 5, x: 0, y: 2)
                        .matchedGeometryEffect(id: "segment.indicator", in: indicator)
                }
            }
        }
        .buttonStyle(.plain)
        .launcherPointer()
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 更新选中值（滑动动画，尊重“减弱动效”）。
    private func select(_ newValue: Value) {
        guard newValue != selection else { return }
        if reduceMotion {
            selection = newValue
        } else {
            withAnimation(LauncherMotion.spring) { selection = newValue }
        }
    }
}

// MARK: - Dropdown

/// 下拉选择：按钮显示当前项，弹出系统 Menu（键盘可达），选项前带勾选标记。
public struct LauncherDropdown<Value: Hashable>: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(\.launcherSnapshotMode) private var snapshotMode

    private let options: [LauncherSegment<Value>]
    @Binding private var selection: Value
    private let placeholder: String

    /// 创建下拉选择，未匹配到选项时显示 placeholder。
    public init(
        options: [LauncherSegment<Value>],
        selection: Binding<Value>,
        placeholder: String = "请选择"
    ) {
        self.options = options
        self._selection = selection
        self.placeholder = placeholder
    }

    /// 当前选中项（可能为空）。
    private var current: LauncherSegment<Value>? {
        options.first { $0.id == selection }
    }

    public var body: some View {
        Group {
            if snapshotMode {
                // 离屏渲染：Menu 由 AppKit 背书不可绘制，用同一套静态外观替代
                menuLabel
            } else {
                menu
            }
        }
        .environment(\.colorScheme, theme.scheme)
        .launcherPointer()
    }

    /// 系统 Menu（自定义 label + borderlessButton 样式，避免系统白底按钮）。
    private var menu: some View {
        Menu {
            ForEach(options) { option in
                Button {
                    selection = option.id
                } label: {
                    if option.id == selection {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            menuLabel
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    /// 触发器外观：与输入框一致的凹槽底、1px 描边、右侧上下箭头。
    private var menuLabel: some View {
        HStack(spacing: LauncherSpace.sm) {
            if let systemImage = current?.systemImage {
                Image(systemName: systemImage)
                    .textStyle(.body, tone: .secondary)
            }
            Text(current?.title ?? placeholder)
                .textStyle(.body, tone: current == nil ? .tertiary : .primary)
                .lineLimit(1)
            Spacer(minLength: LauncherSpace.xs)
            Image(systemName: "chevron.up.chevron.down")
                .textStyle(.micro, tone: .tertiary)
        }
        .padding(.horizontal, LauncherSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: LauncherControl.medium)
        .contentShape(RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                .fill(theme.colors.surfaceSubtle)
        }
        .overlay {
            RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                .strokeBorder(theme.colors.stroke, lineWidth: 1)
        }
    }
}

// MARK: - Stepper

/// 步进器：胶囊容器内 “− 值 + ”，到达区间边界时对应按钮禁用。
public struct LauncherStepper: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding private var value: Int
    private let range: ClosedRange<Int>
    private let label: String?
    private let unit: String?

    /// 创建步进器，默认区间 1...64。
    public init(value: Binding<Int>, range: ClosedRange<Int> = 1...64, label: String? = nil, unit: String? = nil) {
        self._value = value
        self.range = range
        self.label = label
        self.unit = unit
    }

    public var body: some View {
        HStack(spacing: LauncherSpace.md) {
            if let label {
                Text(label)
                    .textStyle(.body)
                    .lineLimit(1)
            }
            Spacer(minLength: LauncherSpace.sm)
            control
        }
        .frame(minHeight: LauncherControl.medium)
    }

    /// 胶囊控件本体。
    private var control: some View {
        HStack(spacing: 0) {
            stepButton(symbol: "minus", isEnabled: value > range.lowerBound, delta: -1)
            HStack(spacing: LauncherSpace.xxs) {
                LauncherMonoText("\(value)", tone: .primary)
                if let unit {
                    Text(unit)
                        .textStyle(.micro, tone: .tertiary)
                }
            }
            .frame(minWidth: LauncherSpace.xxxl)
            stepButton(symbol: "plus", isEnabled: value < range.upperBound, delta: 1)
        }
        .padding(.horizontal, LauncherSpace.xxs)
        .frame(height: LauncherControl.small)
        .background {
            Capsule(style: .continuous)
                .fill(theme.colors.surfaceSubtle)
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(theme.colors.stroke, lineWidth: 1)
        }
    }

    /// 加/减按钮，边界外禁用并降透明度。
    private func stepButton(symbol: String, isEnabled: Bool, delta: Int) -> some View {
        Button {
            step(by: delta)
        } label: {
            Image(systemName: symbol)
                .textStyle(.caption, tone: isEnabled ? .secondary : .tertiary)
                .font(LauncherTextStyle.caption.font.weight(.semibold))
                .frame(width: LauncherControl.small, height: LauncherControl.small)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(Text(symbol == "minus" ? "减少" : "增加"))
    }

    /// 按步长修改数值，并夹在区间内。
    private func step(by delta: Int) {
        let next = min(range.upperBound, max(range.lowerBound, value + delta))
        guard next != value else { return }
        if reduceMotion {
            value = next
        } else {
            withAnimation(.easeOut(duration: LauncherMotion.fast)) { value = next }
        }
    }
}
