import SwiftUI
import AppKit

// MARK: - 正版登录面板

/// 微软设备码登录面板：大字验证码 + 复制 / 打开浏览器 + 倒计时 + 步骤提示 +
/// 内联失败态（重试 / 帮助链接），成功后自动关闭并切换账户。
public struct MicrosoftLoginSheet: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(AccountStore.self) private var accountStore

    @State private var copied = false
    @State private var copyTask: Task<Void, Never>?

    public init() {}

    public var body: some View {
        let state = accountStore.loginState
        LauncherCard(level: .strong, padding: LauncherSpace.lg) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                header
                stepIndicator(state: state)
                Divider().overlay(theme.colors.stroke)
                content(state: state)
                footer(state: state)
            }
            .frame(width: 460, alignment: .leading)
        }
        .interactiveDismissDisabled(state.isBusy)
        .onDisappear {
            copyTask?.cancel()
            if accountStore.loginState.isBusy {
                accountStore.cancelLogin()
            }
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: LauncherSpace.sm) {
            Image(systemName: "person.badge.key.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.colors.accent)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                        .fill(theme.colors.accentSoft)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text("添加正版账户")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.colors.textPrimary)
                Text("通过微软账户验证，登录后启动游戏将使用正版身份")
                    .textStyle(.micro, tone: .tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            LauncherIconButton(
                systemImage: "xmark",
                variant: .ghost,
                size: .small,
                accessibilityLabel: "取消登录"
            ) {
                accountStore.cancelLogin()
            }
        }
    }

    // MARK: 步骤指示

    private func stepIndicator(state: AccountStore.LoginState) -> some View {
        let steps = ["打开网页", "输入验证码", "完成授权"]
        let current = state.step
        return HStack(spacing: LauncherSpace.sm) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, title in
                let number = index + 1
                let isActive = number <= current
                HStack(spacing: LauncherSpace.xxs) {
                    Text("\(number)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(isActive ? theme.colors.onAccent : theme.colors.textTertiary)
                        .frame(width: 16, height: 16)
                        .background {
                            Circle().fill(isActive ? theme.colors.accent : theme.colors.surfaceSubtle)
                        }
                    Text(title)
                        .textStyle(.micro, tone: isActive ? .primary : .tertiary)
                }
                if index < steps.count - 1 {
                    Rectangle()
                        .fill(theme.colors.stroke)
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: 内容

    @ViewBuilder
    private func content(state: AccountStore.LoginState) -> some View {
        switch state {
        case .requestingCode:
            statusRow(spinner: true, text: "正在向微软申请验证码…")
        case .waitingForUser(let code):
            codeContent(code)
        case .authenticating:
            statusRow(spinner: true, text: "授权成功，正在完成 Xbox / Minecraft 登录…")
        case .failed(let error):
            failureContent(error)
        case .idle:
            statusRow(spinner: false, text: "准备登录…")
        }
    }

    /// 验证码大字 + 复制 / 打开浏览器 + 倒计时。
    private func codeContent(_ code: MicrosoftDeviceCode) -> some View {
        VStack(alignment: .leading, spacing: LauncherSpace.sm) {
            HStack(spacing: LauncherSpace.xs) {
                Image(systemName: "1.circle.fill")
                    .foregroundStyle(theme.colors.accent)
                    .font(.system(size: 12, weight: .semibold))
                Text("在浏览器中打开")
                    .textStyle(.caption, tone: .secondary)
                LauncherMonoText(code.verificationURI, tone: .secondary, size: 11)
                    .lineLimit(1)
                Spacer(minLength: 0)
                LauncherButton("打开浏览器", systemImage: "safari", variant: .secondary, size: .small) {
                    NSWorkspace.shared.open(code.verificationURL)
                }
                .fixedSize()
            }

            VStack(spacing: LauncherSpace.xs) {
                Text(code.userCode)
                    .font(.system(size: 38, weight: .semibold, design: .monospaced))
                    .tracking(4)
                    .foregroundStyle(theme.colors.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LauncherSpace.sm)
                    .background {
                        RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                            .fill(theme.colors.surfaceSubtle)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                            .strokeBorder(theme.colors.stroke, lineWidth: 1)
                    }

                HStack(spacing: LauncherSpace.sm) {
                    LauncherButton(
                        copied ? "已复制 ✓" : "复制验证码",
                        systemImage: copied ? "checkmark" : "doc.on.doc",
                        variant: .primary,
                        size: .small
                    ) {
                        copy(code.userCode)
                    }
                    Spacer(minLength: 0)
                    countdown(code: code)
                }
            }

            Text("输入上方验证码并完成微软授权后，这里会自动继续；请勿关闭此窗口。")
                .textStyle(.micro, tone: .tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 验证码剩余时间倒计时。
    private func countdown(code: MicrosoftDeviceCode) -> some View {
        let expiresAt = code.expiresAt()
        return TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(expiresAt.timeIntervalSince(context.date)))
            HStack(spacing: LauncherSpace.xxs) {
                LauncherStatusDot(tone: remaining > 60 ? .neutral : .warning)
                LauncherMonoText(
                    remaining > 0 ? String(format: "剩余 %02d:%02d", remaining / 60, remaining % 60) : "已过期",
                    tone: remaining > 60 ? .tertiary : .warning,
                    size: 10
                )
            }
        }
    }

    /// 失败态：内联原因 + 帮助链接 + 重试。
    private func failureContent(_ error: MicrosoftAuthError) -> some View {
        VStack(alignment: .leading, spacing: LauncherSpace.sm) {
            HStack(spacing: LauncherSpace.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(theme.colors.danger)
                    .font(.system(size: 13, weight: .semibold))
                Text("登录失败")
                    .textStyle(.bodyStrong, tone: .primary)
            }
            Text(error.localizedDescription)
                .textStyle(.caption, tone: .secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let helpURL = error.helpURL {
                LauncherButton("查看帮助", systemImage: "arrow.up.right.square", variant: .secondary, size: .small) {
                    NSWorkspace.shared.open(helpURL)
                }
                .fixedSize()
            }
        }
        .padding(LauncherSpace.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                .fill(theme.colors.surfaceSubtle)
        }
        .overlay(alignment: .leading) {
            Capsule()
                .fill(theme.colors.danger)
                .frame(width: 3)
                .padding(.vertical, LauncherSpace.xs)
        }
    }

    private func statusRow(spinner: Bool, text: String) -> some View {
        HStack(spacing: LauncherSpace.sm) {
            if spinner {
                LauncherSpinner(size: 14)
            }
            Text(text)
                .textStyle(.caption, tone: .secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, LauncherSpace.xs)
    }

    // MARK: 底部操作

    @ViewBuilder
    private func footer(state: AccountStore.LoginState) -> some View {
        HStack(spacing: LauncherSpace.sm) {
            if case .failed = state {
                LauncherButton("重试", systemImage: "arrow.clockwise", variant: .primary, size: .small) {
                    accountStore.retryLogin()
                }
                .fixedSize()
            }
            Spacer(minLength: 0)
            LauncherButton("取消", variant: .ghost, size: .small) {
                accountStore.cancelLogin()
            }
            .fixedSize()
        }
    }

    // MARK: 动作

    private func copy(_ code: String) {
        InstanceActions.copy(code)
        copied = true
        copyTask?.cancel()
        copyTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled { copied = false }
        }
    }
}

// MARK: - 正版头像

/// 正版玩家头像：异步加载官方皮肤站头像（crafatar 作为展示兜底），失败回退到首字母头像。
/// 离屏快照模式不发起网络请求。
public struct MinecraftAvatarView: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(\.launcherSnapshotMode) private var snapshotMode

    private let uuid: String
    private let name: String
    private let size: CGFloat

    @State private var image: NSImage?

    public init(uuid: String, name: String, size: CGFloat = 28) {
        self.uuid = uuid
        self.name = name
        self.size = size
    }

    public var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fill)
            } else {
                LauncherAvatar(name: name, systemImage: "person.fill", size: size, isOnline: true)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(theme.colors.stroke, lineWidth: 1)
        }
        .task(id: uuid) { await load() }
    }

    private func load() async {
        guard !snapshotMode else { return }
        if let cached = MinecraftAvatarCache.shared.image(for: uuid) {
            image = cached
            return
        }
        let compact = uuid.replacingOccurrences(of: "-", with: "").lowercased()
        guard let url = URL(string: "https://crafatar.com/avatars/\(compact)?size=64&overlay") else { return }
        guard let data = try? await URLSession.shared.data(from: url).0,
              let loaded = NSImage(data: data) else { return }
        MinecraftAvatarCache.shared.store(loaded, for: uuid)
        image = loaded
    }
}

/// 头像内存缓存（所有账户行共享，避免每行重复下载）。
@MainActor
final class MinecraftAvatarCache {
    static let shared = MinecraftAvatarCache()
    private let cache = NSCache<NSString, NSImage>()

    func image(for uuid: String) -> NSImage? {
        cache.object(forKey: uuid as NSString)
    }

    func store(_ image: NSImage, for uuid: String) {
        cache.setObject(image, forKey: uuid as NSString)
    }
}
