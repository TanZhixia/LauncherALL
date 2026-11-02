import SwiftUI
import AppKit

// MARK: - 正版账户设置区

/// 设置页「账户」分类里的正版账户区：添加微软账户、多账户切换 / 刷新 / 退出登录。
/// 登录走 `AccountStore` 的设备码状态机，面板由壳层统一以 sheet 呈现。
struct PremiumAccountSection: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(AccountStore.self) private var accountStore
    @Environment(LauncherRouter.self) private var router
    @Environment(\.launcherSnapshotMode) private var snapshotMode

    let strings: SettingsStrings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LauncherSettingRow(
                strings[.premiumTitle],
                subtitle: strings[.premiumSubtitle]
            ) {
                LauncherButton(
                    strings[.premiumAdd],
                    systemImage: "person.badge.plus",
                    variant: .secondary,
                    size: .small,
                    isLoading: accountStore.loginState.isBusy
                ) {
                    accountStore.beginLogin()
                }
                .fixedSize()
            }

            if accountStore.microsoftAccounts.isEmpty {
                HStack(spacing: LauncherSpace.xs) {
                    Image(systemName: "info.circle")
                        .textStyle(.micro, tone: .tertiary)
                    Text(strings[.premiumEmpty])
                        .textStyle(.micro, tone: .tertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, LauncherSpace.xs)
            } else {
                ForEach(accountStore.microsoftAccounts) { record in
                    accountRow(record)
                }
            }
        }
        .onDisappear {
            // 页面切走时若仍在等待验证码，取消轮询，避免后台一直挂着
            if accountStore.loginState.isBusy {
                accountStore.cancelLogin()
            }
        }
    }

    /// 单个正版账户行：头像 / 名字 / UUID / 当前徽标 + 切换、刷新、退出。
    private func accountRow(_ record: AuthAccountRecord) -> some View {
        let isSelected = accountStore.selectedAccountID == record.id
        return HStack(spacing: LauncherSpace.sm) {
            MinecraftAvatarView(uuid: record.uuid, name: record.name, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: LauncherSpace.xs) {
                    Text(record.name)
                        .textStyle(.bodyStrong, tone: .primary)
                        .lineLimit(1)
                    LauncherBadge(strings[.premiumBadge], tone: .accent)
                    if isSelected {
                        LauncherBadge(strings[.premiumCurrent], tone: .success)
                    }
                }
                LauncherMonoText(record.uuid, tone: .tertiary, size: 9)
                    .lineLimit(1)
            }
            Spacer(minLength: LauncherSpace.sm)

            if !isSelected {
                LauncherButton(strings[.premiumSwitch], variant: .secondary, size: .small) {
                    accountStore.select(record.id)
                    router.showToast("\(strings[.premiumSwitch])：\(record.name)", tone: .info)
                }
                .fixedSize()
            }
            LauncherIconButton(
                systemImage: "arrow.clockwise",
                variant: .ghost,
                size: .small,
                accessibilityLabel: strings[.premiumRefresh]
            ) {
                refresh(record)
            }
            LauncherIconButton(
                systemImage: "rectangle.portrait.and.arrow.right",
                variant: .ghost,
                size: .small,
                accessibilityLabel: strings[.premiumLogout]
            ) {
                confirmLogout(record)
            }
        }
        .padding(.vertical, LauncherSpace.xs)
        .padding(.horizontal, LauncherSpace.xxs)
        .background {
            RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                .fill(isSelected ? theme.colors.accentSoft : .clear)
        }
    }

    private func refresh(_ record: AuthAccountRecord) {
        Task { @MainActor in
            if await accountStore.refresh(record.id) {
                router.showToast(strings[.premiumRefresh] + " ✓")
            } else if let error = accountStore.lastError {
                router.showToast(error.localizedDescription, tone: .danger)
            }
        }
    }

    private func confirmLogout(_ record: AuthAccountRecord) {
        router.showDialog(
            LauncherDialogRequest(
                title: strings[.premiumLogoutTitle],
                message: strings[.premiumLogoutMessage],
                confirmTitle: strings[.premiumLogoutConfirm],
                isDestructive: true,
                onConfirm: {
                    // 成功提示由 AccountStore.successMessage 统一交给壳层 toast，避免重复弹两次
                    accountStore.logout(record.id)
                }
            )
        )
    }
}
