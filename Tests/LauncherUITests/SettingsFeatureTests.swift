import XCTest
import SwiftUI
@testable import LauncherUI

/// 设置页功能测试：分区路由、三语完整度、内存方案、JVM 冲突、
/// 玩家名校验、Java 路径校验、旧版本清理与日志导出。
final class SettingsFeatureTests: XCTestCase {

    // MARK: - 分区与路由

    func testSectionRouteResolution() {
        XCTAssertEqual(SettingsSection.resolve("account"), .account)
        XCTAssertEqual(SettingsSection.resolve("java"), .java)
        XCTAssertEqual(SettingsSection.resolve("performance"), .performance)
        XCTAssertEqual(SettingsSection.resolve("update"), .update)
        XCTAssertEqual(SettingsSection.resolve("appearance"), .appearance)
        XCTAssertEqual(SettingsSection.resolve("log"), .log)
        XCTAssertEqual(SettingsSection.resolve("about"), .about)
        XCTAssertEqual(SettingsSection.resolve("launch"), .launch)
        XCTAssertNil(SettingsSection.resolve("nope"))
        XCTAssertNil(SettingsSection.resolve(nil))
        XCTAssertNil(SettingsSection.resolve(""))
    }

    func testSectionGroupsMatchSidePanelOrder() {
        XCTAssertEqual(SettingsSection.allCases.count, 8)
        XCTAssertEqual(SettingsSection.allCases.map(\.rawValue).count, Set(SettingsSection.allCases.map(\.rawValue)).count)
        for section in SettingsSection.allCases {
            XCTAssertFalse(section.systemImage.isEmpty, "\(section) 缺少图标")
        }
        XCTAssertEqual(SettingsSection.allCases.filter { $0.group == .game }, [.launch, .java, .performance])
        XCTAssertEqual(SettingsSection.allCases.filter { $0.group == .launcher }, [.update, .appearance, .account])
        XCTAssertEqual(SettingsSection.allCases.filter { $0.group == .about }, [.about, .log])
    }

    // MARK: - 本地化

    func testLocalizationTablesAreComplete() {
        for language in SettingsLanguage.allCases {
            let strings = SettingsStrings(language: language)
            XCTAssertTrue(
                strings.missingKeys().isEmpty,
                "\(language.rawValue) 缺少文案：\(strings.missingKeys().map(\.rawValue))"
            )
        }
    }

    func testLocalizationPlaceholdersStayInSync() {
        let languages = SettingsLanguage.allCases
        for key in SettingsTextKey.allCases {
            let reference = Self.specifiers(in: SettingsStrings.chineseTable[key] ?? "")
            for language in languages where language != .simplifiedChinese {
                let text = SettingsStrings.table(for: language)[key] ?? ""
                XCTAssertEqual(
                    Self.specifiers(in: text),
                    reference,
                    "\(key.rawValue) 在 \(language.rawValue) 里的占位符与中文不一致：「\(text)」"
                )
            }
        }
    }

    func testLocalizationLookupsAndFormatting() {
        XCTAssertEqual(SettingsLanguage.resolve("en"), .english)
        XCTAssertEqual(SettingsLanguage.resolve("ja"), .japanese)
        XCTAssertEqual(SettingsLanguage.resolve("zh-Hans"), .simplifiedChinese)
        XCTAssertEqual(SettingsLanguage.resolve("fr"), .simplifiedChinese)
        XCTAssertEqual(SettingsLanguage.english.nativeName, "English")
        XCTAssertEqual(SettingsLanguage.japanese.nativeName, "日本語")

        for language in SettingsLanguage.allCases {
            let strings = SettingsStrings(language: language)
            XCTAssertEqual(strings.sectionTitle(.java), strings[.sectionJava])
            XCTAssertEqual(strings.sectionSubtitle(.log), strings[.subtitleLog])
            XCTAssertEqual(strings.groupTitle(.launcher), strings[.groupLauncher])
            // 占位符格式化后不应残留 %d / %@
            let cleaned = strings.format(.cleanupToast, 2)
            XCTAssertFalse(cleaned.contains("%"))
            XCTAssertTrue(cleaned.contains("2"))
            XCTAssertFalse(strings.format(.javaPathValid, 21, "Temurin").contains("%"))
        }
    }

    func testLanguageRestartRequirement() {
        XCTAssertTrue(SettingsAppRestart.needsRestart(selected: .english, applied: .simplifiedChinese))
        XCTAssertTrue(SettingsAppRestart.needsRestart(selected: .japanese, applied: .english))
        XCTAssertFalse(SettingsAppRestart.needsRestart(selected: .english, applied: .english))
    }

    // MARK: - 内存方案

    func testMemoryPlanDerivedFromPhysicalMemory() {
        let plan16GB = SettingsMemoryPlan(physicalMemoryBytes: 16 * 1024 * 1024 * 1024)
        XCTAssertEqual(plan16GB.totalMemoryMB, 16384)
        XCTAssertEqual(plan16GB.sliderUpperBoundMB, 12288)
        XCTAssertEqual(plan16GB.recommendedMB, 8192)
        XCTAssertEqual(plan16GB.totalMemoryText, "16 GB")
        XCTAssertEqual(plan16GB.sliderRange.upperBound, 12288)

        let plan4GB = SettingsMemoryPlan(physicalMemoryBytes: 4 * 1024 * 1024 * 1024)
        XCTAssertEqual(plan4GB.sliderUpperBoundMB, 3072)
        XCTAssertEqual(plan4GB.recommendedMB, 2048)

        let plan64GB = SettingsMemoryPlan(physicalMemoryBytes: 64 * 1024 * 1024 * 1024)
        // 64GB × 3/4 = 48GB，被硬上限 32GB 截断；推荐值仍封顶 8GB
        XCTAssertEqual(plan64GB.sliderUpperBoundMB, SettingsMemoryPlan.hardMaximumMB)
        XCTAssertEqual(plan64GB.recommendedMB, 8192)

        let planTiny = SettingsMemoryPlan(physicalMemoryBytes: 2 * 1024 * 1024 * 1024)
        XCTAssertGreaterThanOrEqual(planTiny.sliderUpperBoundMB, 2048)
        XCTAssertGreaterThanOrEqual(planTiny.recommendedMB, 2048)

        let planOdd = SettingsMemoryPlan(physicalMemoryBytes: 6_000 * 1024 * 1024)
        XCTAssertEqual(planOdd.totalMemoryText, "6000 MB")
    }

    func testMemoryPlanSnappingAndVerdict() {
        let plan = SettingsMemoryPlan(physicalMemoryBytes: 16 * 1024 * 1024 * 1024)
        XCTAssertEqual(plan.snappedMB(99), SettingsMemoryPlan.minimumMB)
        XCTAssertEqual(plan.snappedMB(4100), 4096)
        XCTAssertEqual(plan.snappedMB(4000), 3968)
        XCTAssertEqual(plan.snappedMB(999_999), plan.sliderUpperBoundMB)

        XCTAssertEqual(plan.verdict(for: 2048), .belowRecommended)
        XCTAssertEqual(plan.verdict(for: plan.recommendedMB), .optimal)
        XCTAssertEqual(plan.verdict(for: plan.recommendedMB + SettingsMemoryPlan.stepMB), .optimal)
        XCTAssertEqual(plan.verdict(for: plan.recommendedMB + SettingsMemoryPlan.stepMB * 9), .aboveRecommended)
        XCTAssertEqual(plan.verdict(for: plan.sliderUpperBoundMB + 1), .overLimit)
    }

    // MARK: - JVM 内存参数

    func testJVMMemoryArgumentParsing() {
        let arguments = [
            "-Xmx4G",
            "-Xss1M",
            "-Xms512m",
            "-Xmx2048",
            "-Xmx1g",
            "-XX:+UseG1GC"
        ]
        let parsed = SettingsJVMArguments.memoryArguments(in: arguments)
        XCTAssertEqual(parsed.count, 4)
        XCTAssertEqual(parsed[0].raw, "-Xmx4G")
        XCTAssertEqual(parsed[0].megabytes, 4096)
        XCTAssertTrue(parsed[0].isMaximum)
        XCTAssertEqual(parsed[1].raw, "-Xms512m")
        XCTAssertEqual(parsed[1].megabytes, 512)
        XCTAssertFalse(parsed[1].isMaximum)
        XCTAssertEqual(parsed[2].megabytes, 2048)
        XCTAssertEqual(parsed[3].megabytes, 1024)
        XCTAssertTrue(SettingsJVMArguments.memoryArguments(in: ["-Xss1M", "-Dfoo=bar"]).isEmpty)
    }

    func testJVMConflictDetection() {
        XCTAssertEqual(
            SettingsJVMArguments.conflictingMaximum(arguments: ["-Xmx2G"], memoryMB: 4096)?.megabytes,
            2048
        )
        XCTAssertNil(
            SettingsJVMArguments.conflictingMaximum(arguments: ["-Xmx4096M"], memoryMB: 4096)
        )
        XCTAssertNil(
            SettingsJVMArguments.conflictingMaximum(arguments: ["-Xms2G", "-XX:+UseG1GC"], memoryMB: 4096)
        )
        XCTAssertEqual(
            SettingsJVMArguments.conflictingMaximum(arguments: ["-Xms2G", "-Xmx8g"], memoryMB: 4096)?.raw,
            "-Xmx8g"
        )
    }

    // MARK: - 玩家名

    func testPlayerNameValidationAgreesWithSettingsRules() {
        let samples = ["Steve", "a_1", "Alex_99", "", "   ", "abcdefghijklmnopq", "Steve!", "史蒂夫", "a b"]
        for sample in samples {
            let leadsResult = LauncherSettings.validatePlayerName(sample)
            let issue = SettingsPlayerName.issue(for: sample)
            XCTAssertEqual(issue == nil, leadsResult == nil, "「\(sample)」判定不一致")
        }

        XCTAssertEqual(SettingsPlayerName.issue(for: ""), .empty)
        XCTAssertEqual(SettingsPlayerName.issue(for: "   "), .empty)
        XCTAssertEqual(SettingsPlayerName.issue(for: "abcdefghijklmnopq"), .tooLong)
        XCTAssertEqual(SettingsPlayerName.issue(for: "Steve!"), .invalidCharacters)
        // 共享校验用 Unicode alphanumerics 判定，中文名在 LauncherSettings 规则下合法
        XCTAssertNil(SettingsPlayerName.issue(for: "史蒂夫"))
        XCTAssertNil(SettingsPlayerName.issue(for: "Steve_2026"))
        XCTAssertEqual(SettingsPlayerName.normalized("  Steve  "), "Steve")
        XCTAssertNil(SettingsPlayerName.normalized("  "))
        XCTAssertNil(SettingsPlayerName.normalized("Steve!"))
    }

    // MARK: - Java 路径校验

    func testJavaProbeEmptyAndMissingPath() {
        XCTAssertEqual(SettingsJavaProbe.validate(path: ""), .empty)
        XCTAssertEqual(SettingsJavaProbe.validate(path: "   "), .empty)

        let missing = "/tmp/missing-java-\(UUID().uuidString)/bin/java"
        guard case .invalid(.missing(let path)) = SettingsJavaProbe.validate(path: missing) else {
            return XCTFail("不存在的路径应报 missing")
        }
        XCTAssertEqual(path, missing)
    }

    func testJavaProbeNotExecutableFile() throws {
        let directory = try makeTemporaryDirectory()
        let file = directory.appendingPathComponent("java")
        try "not a program".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)

        guard case .invalid(.notExecutable(let path)) = SettingsJavaProbe.validate(path: file.path) else {
            return XCTFail("不可执行文件应报 notExecutable")
        }
        XCTAssertEqual(path, file.path)
    }

    func testJavaProbeParsesVersionOutput() throws {
        let directory = try makeTemporaryDirectory()
        let file = directory.appendingPathComponent("java")
        try "#!/bin/sh\nexit 0\n".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)

        var receivedArguments: [String] = []
        let output = """
        openjdk version "21.0.1" 2023-10-17
        OpenJDK Runtime Environment Temurin-21.0.1+12 (build 21.0.1+12)
        OpenJDK 64-Bit Server VM Temurin-21.0.1+12 (build 21.0.1+12, mixed mode)
        """
        let result = SettingsJavaProbe.validate(path: file.path) { _, arguments in
            receivedArguments = arguments
            return output
        }
        guard case .valid(let runtime) = result else {
            return XCTFail("应解析成功，实际：\(result)")
        }
        XCTAssertEqual(receivedArguments, ["-version"])
        XCTAssertEqual(runtime.majorVersion, 21)
        XCTAssertEqual(runtime.vendor, "Temurin")
        XCTAssertTrue(SettingsJavaProbe.satisfies(runtime, requiredMajor: 17))
        XCTAssertTrue(SettingsJavaProbe.satisfies(runtime, requiredMajor: 21))
        XCTAssertFalse(SettingsJavaProbe.satisfies(runtime, requiredMajor: 22))
        XCTAssertTrue(SettingsJavaProbe.satisfies(runtime, requiredMajor: nil))
    }

    func testJavaProbeFailureMessages() throws {
        let directory = try makeTemporaryDirectory()
        let file = directory.appendingPathComponent("java")
        try "#!/bin/sh\nexit 0\n".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)

        // 进程执行失败（runner 返回 nil）
        guard case .invalid(.probeFailed) = SettingsJavaProbe.validate(path: file.path, runner: { _, _ in nil }) else {
            return XCTFail("runner 返回 nil 时应报 probeFailed")
        }
        // 输出无法解析
        guard case .invalid(.probeFailed) = SettingsJavaProbe.validate(path: file.path, runner: { _, _ in "hello" }) else {
            return XCTFail("无法解析的输应报 probeFailed")
        }
    }

    // MARK: - 旧版本清理

    func testCleanupPlannerBuildsRowsFromRealData() throws {
        let directory = try makeTemporaryDirectory()
        let installation = MinecraftInstallation(root: directory)
        let versionsDirectory = installation.versionsDirectory
        try FileManager.default.createDirectory(at: versionsDirectory, withIntermediateDirectories: true)

        var versions: [InstalledVersion] = []
        for id in ["1.21.4", "b1.7.3"] {
            let directory = installation.versionDirectory(id)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let json = directory.appendingPathComponent("\(id).json")
            try "{}".write(to: json, atomically: true, encoding: .utf8)
            let jar = directory.appendingPathComponent("\(id).jar")
            try Data([0x50, 0x4B]).write(to: jar)
            versions.append(
                InstalledVersion(id: id, jsonURL: json, jarURL: jar, versionType: "release", lastModified: Date())
            )
        }

        let oldDate = Date(timeIntervalSince1970: 1_600_000_000)
        let rows = SettingsCleanupPlanner.rows(
            versions: versions,
            lastLaunch: { id in id == "1.21.4" ? oldDate : nil },
            sizeProvider: { _ in 2 * 1024 * 1024 }
        )
        XCTAssertEqual(rows.map(\.versionID), ["1.21.4", "b1.7.3"])
        XCTAssertEqual(rows[0].lastUsedAt, oldDate)
        XCTAssertNil(rows[1].lastUsedAt)
        XCTAssertTrue(rows.allSatisfy { $0.sizeBytes == 2 * 1024 * 1024 })
        XCTAssertFalse(rows[0].sizeText.isEmpty)

        let total = SettingsCleanupPlanner.totalSizeText(rows)
        XCTAssertFalse(total.isEmpty)
        XCTAssertEqual(SettingsCleanupPlanner.totalSizeText([]), ByteCountFormatter.string(fromByteCount: 0, countStyle: .file))
        XCTAssertEqual(SettingsCleanupPlanner.defaultDays, 30)
    }

    // MARK: - 日志导出

    func testLogExportContentHeaderContainsBuildCommandAndExitCode() {
        let buildInfo = LauncherBuildInfo(
            version: "9.9.9",
            buildDate: Date(timeIntervalSince1970: 0),
            commit: "abc1234"
        )
        let content = SettingsLogExporter.content(
            lines: ["line-1", "line-2"],
            buildInfo: buildInfo,
            commandLine: "java -Xmx2G -cp foo.jar",
            exitCode: 3,
            labels: .chinese,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertTrue(content.contains("v9.9.9"))
        XCTAssertTrue(content.contains("abc1234"))
        XCTAssertTrue(content.contains("java -Xmx2G -cp foo.jar"))
        XCTAssertTrue(content.contains("退出码：3"))
        XCTAssertTrue(content.contains("日志行数：2"))
        XCTAssertTrue(content.hasSuffix("line-1\nline-2"))

        let english = SettingsLogExporter.content(
            lines: ["log"],
            buildInfo: buildInfo,
            commandLine: nil,
            exitCode: nil,
            labels: SettingsLogExportLabels(
                title: "Log",
                version: "Version",
                generated: "Generated",
                command: "Command",
                exitCode: "Exit",
                lineCount: "Lines"
            )
        )
        XCTAssertTrue(english.contains("Command：—"))
        XCTAssertTrue(english.contains("Exit：—"))
    }

    func testLogExporterWritesRealFile() throws {
        let directory = try makeTemporaryDirectory()
        let buildInfo = LauncherBuildInfo(version: "0.2.0", buildDate: Date(), commit: "deadbee")
        let export = try SettingsLogExporter.export(
            lines: ["a", "b", "c"],
            buildInfo: buildInfo,
            commandLine: "java -version",
            exitCode: 0,
            labels: .chinese,
            directory: directory
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: export.url.path))
        XCTAssertEqual(export.lineCount, 3)
        let text = try String(contentsOf: export.url, encoding: .utf8)
        XCTAssertEqual(text.utf8.count, export.byteCount)
        XCTAssertTrue(text.contains("方块启动器日志"))
        XCTAssertTrue(export.url.lastPathComponent.hasPrefix("blocklauncher-log-"))
        XCTAssertTrue(export.url.lastPathComponent.hasSuffix(".log"))

        XCTAssertThrowsError(
            try SettingsLogExporter.export(
                lines: [],
                buildInfo: buildInfo,
                commandLine: nil,
                exitCode: nil,
                directory: directory
            )
        ) { error in
            guard case SettingsLogExportError.emptyLog = error else {
                return XCTFail("空日志应抛 emptyLog，实际：\(error)")
            }
        }
    }

    /// 日志落点必须与「更多 → 日志与诊断」完全一致：同一目录、同一文件名规则。
    func testLogExportLocationMatchesMorePage() {
        let directory = SettingsLogExporter.logsDirectory()
        XCTAssertEqual(directory.path, MoreLogExporter.logsDirectory().path)
        XCTAssertTrue(directory.path.hasSuffix("Library/Logs/BlockLauncher"))
        XCTAssertEqual(SettingsLogExporter.folderName, MoreLogExporter.folderName)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(SettingsLogExporter.fileName(at: date), MoreLogExporter.makeFileName(date: date))
    }

    /// 不传目录时，真实写到设置页/更多页共用的 `~/Library/Logs/BlockLauncher/`。
    func testLogExportWritesToDefaultLogsDirectory() throws {
        let buildInfo = LauncherBuildInfo(version: "0.2.0", buildDate: Date(), commit: "deadbee")
        let export = try SettingsLogExporter.export(
            lines: ["default-dir-line"],
            buildInfo: buildInfo,
            commandLine: nil,
            exitCode: 0
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: export.url)
        }
        XCTAssertTrue(export.url.path.hasPrefix(SettingsLogExporter.logsDirectory().path + "/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: export.url.path))
        let text = try String(contentsOf: export.url, encoding: .utf8)
        XCTAssertTrue(text.contains("default-dir-line"))
    }

    /// 导出会自动创建日志目录；同一时间戳重复导出追加序号，不覆盖已有文件。
    func testLogExportCreatesDirectoryAndAvoidsOverwrite() throws {
        let root = try makeTemporaryDirectory()
        let target = root.appendingPathComponent("Logs/BlockLauncher", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))

        let buildInfo = LauncherBuildInfo(version: "0.2.0", buildDate: Date(), commit: "deadbee")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try SettingsLogExporter.export(
            lines: ["line"],
            buildInfo: buildInfo,
            commandLine: nil,
            exitCode: 0,
            directory: target,
            now: now
        )
        let second = try SettingsLogExporter.export(
            lines: ["line"],
            buildInfo: buildInfo,
            commandLine: nil,
            exitCode: 0,
            directory: target,
            now: now
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.url.path))
        XCTAssertNotEqual(first.url, second.url)
        XCTAssertTrue(second.url.lastPathComponent.hasSuffix("-2.log"))
        XCTAssertTrue(FileManager.default.isWritableFile(atPath: target.path))
    }

    // MARK: - 文案真实性（QA P1 复核）

    /// 语言、更新通道、自动清理、日志落点的文案必须与真实行为一致，不能再做假承诺。
    func testHonestCopyForLanguageChannelCleanupAndLogs() {
        let forbiddenLanguageClaims: [SettingsLanguage: [String]] = [
            .simplifiedChinese: ["全界面", "全站"],
            .english: ["everywhere", "all pages"],
            .japanese: ["全体へ反映", "すべてのページ"]
        ]
        let channelMarkers: [SettingsLanguage: String] = [
            .simplifiedChinese: "无关",
            .english: "unaffected",
            .japanese: "変わりません"
        ]
        let cleanupMarkers: [SettingsLanguage: String] = [
            .simplifiedChinese: "提示",
            .english: "Hint",
            .japanese: "通知"
        ]
        for language in SettingsLanguage.allCases {
            let strings = SettingsStrings(language: language)
            let languageCopy = strings[.languageTooltip] + strings[.languageSubtitle] + strings[.languageBannerMessage]
            for forbidden in forbiddenLanguageClaims[language] ?? [] {
                XCTAssertFalse(
                    languageCopy.contains(forbidden),
                    "\(language.rawValue) 语言文案仍声称全界面生效：\(languageCopy)"
                )
            }
            XCTAssertTrue(languageCopy.contains("中文") || languageCopy.contains("Chinese") || languageCopy.contains("中国語"))
            XCTAssertTrue(strings[.channelSubtitle].contains(channelMarkers[language] ?? ""))
            XCTAssertTrue(strings[.autoCleanTitle].contains(cleanupMarkers[language] ?? ""))
            XCTAssertTrue(strings[.logExportTooltip].contains("Library/Logs/BlockLauncher"))
            XCTAssertTrue(strings.format(.savedNameRemove, "Alex").contains("Alex"))
            XCTAssertFalse(strings.format(.savedNameRemove, "Alex").contains("%"))
        }
    }

    // MARK: - 设置持久化（设置页依赖的真实存储）

    func testLanguageAndAccountPersistenceRoundTrip() {
        let suite = "launcher.settings.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("无法创建临时 UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = LauncherSettings(defaults: defaults)
        XCTAssertEqual(SettingsLanguage.resolve(settings.language), .simplifiedChinese)
        settings.language = SettingsLanguage.english.rawValue
        settings.playerName = "Alex_2026"
        settings.rememberPlayerName("Steve")
        settings.updateFeedURL = "https://example.com/feed.json"
        XCTAssertNotNil(settings.lastSavedAt)

        let reloaded = LauncherSettings(defaults: defaults)
        XCTAssertEqual(SettingsLanguage.resolve(reloaded.language), .english)
        XCTAssertEqual(reloaded.playerName, "Alex_2026")
        XCTAssertEqual(reloaded.savedPlayerNames.first, "Steve")
        XCTAssertEqual(reloaded.updateFeedURL, "https://example.com/feed.json")
    }

    func testRememberPlayerNameDeduplicatesAndCaps() {
        let suite = "launcher.settings.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("无法创建临时 UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = LauncherSettings(defaults: defaults)

        settings.savedPlayerNames = []
        for index in 0..<12 {
            settings.rememberPlayerName("Player\(index)")
        }
        settings.rememberPlayerName("Player5")
        XCTAssertEqual(settings.savedPlayerNames.count, 8)
        XCTAssertEqual(settings.savedPlayerNames.first, "Player5")
        XCTAssertEqual(Set(settings.savedPlayerNames).count, settings.savedPlayerNames.count)

        // 非法名字不会被记住
        let before = settings.savedPlayerNames
        settings.rememberPlayerName("bad name!")
        settings.rememberPlayerName("")
        XCTAssertEqual(settings.savedPlayerNames, before)
    }

    // MARK: - 按分类恢复默认（task-9）

    /// 每个分类的「恢复默认」只重置本页字段：目标分类回到默认，其它分类保持原值。
    @MainActor
    func testEachSectionResetOnlyTouchesItsOwnSettings() {
        for section in SettingsSection.allCases {
            let suite = "launcher.settings.reset.\(section.rawValue).\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: suite) else {
                return XCTFail("无法创建临时 UserDefaults")
            }
            defer { defaults.removePersistentDomain(forName: suite) }
            let settings = LauncherSettings(defaults: defaults)
            let manager = LauncherThemeManager(presets: LauncherThemes.all, defaults: defaults)
            makeAllSettingsNonDefault(settings, manager)
            let savedAtBeforeLogReset = settings.lastSavedAt

            SettingsSectionReset.apply(section, settings: settings, themeManager: manager)

            assertSection(section, isDefault: true, settings: settings, manager: manager, file: #filePath, line: #line)
            for other in SettingsSection.allCases where other != section {
                assertSection(other, isDefault: false, settings: settings, manager: manager, file: #filePath, line: #line)
            }
            if section == .log {
                XCTAssertEqual(settings.lastSavedAt, savedAtBeforeLogReset, "日志分类没有可重置项，不应产生写入")
            }
        }
    }

    /// 只有「日志与诊断」没有可重置的设置项。
    @MainActor
    func testOnlyLogSectionHasNothingToReset() {
        XCTAssertFalse(SettingsSectionReset.hasResettableSettings(.log))
        for section in SettingsSection.allCases where section != .log {
            XCTAssertTrue(SettingsSectionReset.hasResettableSettings(section), "\(section) 应该有可重置项")
        }
    }

    /// 三语「恢复本页默认」文案：标题/Toast 带入分类名、不残留占位符，message 说明只重置本页。
    func testResetSectionCopyInAllLanguages() {
        for language in SettingsLanguage.allCases {
            let strings = SettingsStrings(language: language)
            let sectionName = strings.sectionTitle(.appearance)
            let title = strings.format(.resetSectionTitle, sectionName)
            XCTAssertTrue(title.contains(sectionName), "\(language.rawValue) 标题应带分类名")
            XCTAssertFalse(title.contains("%"), "\(language.rawValue) 标题应已格式化")

            let toast = strings.format(.resetSectionToast, strings.sectionTitle(.log))
            XCTAssertFalse(toast.contains("%"), "\(language.rawValue) Toast 应已格式化")

            let message = strings[.resetSectionMessage]
            XCTAssertTrue(
                message.contains("本页") || message.contains("this page") || message.contains("このページ"),
                "\(language.rawValue) message 应说明只重置本页：\(message)"
            )
            XCTAssertTrue(
                message.contains("保留") || message.contains("kept") || message.contains("保持"),
                "\(language.rawValue) message 应说明其它数据保留：\(message)"
            )
            let noop = strings[.resetSectionNoop]
            XCTAssertTrue(
                noop.contains("没有") || noop.contains("no ") || noop.contains("ありません"),
                "\(language.rawValue) 日志分类提示应说明没有可重置项：\(noop)"
            )
        }
    }

    // MARK: - 外观主题分段控件 / 账户徽标数据（task-9）

    /// 外观主题分段控件：两套主题（石墨 / 瓷白）直接切换，选中态绑定 themeManager.themeID。
    @MainActor
    func testAppearanceThemeSegmentedOptionsSwitchDirectly() {
        let suite = "launcher.settings.theme.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("无法创建临时 UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = LauncherThemeManager(presets: LauncherThemes.all, defaults: defaults)

        // 分段控件由 presets 生成：石墨 / 瓷白两段
        XCTAssertEqual(manager.presets.map(\.id), LauncherThemes.all.map(\.id))
        XCTAssertEqual(manager.presets.map(\.id), ["graphite", "porcelain"])
        XCTAssertEqual(manager.presets.map(\.name), ["石墨", "瓷白"])
        XCTAssertEqual(manager.themeID, LauncherThemes.default.id)

        // 点第二段（瓷白）立即生效：themeID 与 isDark 同步变化
        manager.select("porcelain")
        XCTAssertEqual(manager.themeID, "porcelain")
        XCTAssertFalse(manager.theme.isDark)
        // 点回第一段（石墨）
        manager.select("graphite")
        XCTAssertEqual(manager.themeID, "graphite")
        XCTAssertTrue(manager.theme.isDark)
    }

    /// 账户分类徽标 / 副标题的数据源：正版账户 → isMicrosoft，且可切回离线账户。
    @MainActor
    func testAccountBadgeSourceSwitchesBetweenPremiumAndOffline() {
        let suite = "launcher.settings.accounts.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("无法创建临时 UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = LauncherSettings(defaults: defaults)
        settings.playerName = "Steve"
        settings.authAccounts = [
            AuthAccountRecord(
                id: "msa-test",
                kind: .microsoft,
                name: "NotchPlayer",
                uuid: "069a79f4-44e9-4726-a5be-fca90e38aaf5"
            )
        ]
        let store = AccountStore(settings: settings, tokenStore: InMemoryAuthTokenStore())

        // 默认选中离线：徽标应走「离线账户」分支
        XCTAssertEqual(store.allAccounts.count, 2)
        XCTAssertEqual(store.allAccounts.first?.id, AuthAccountRecord.offlineID)
        XCTAssertFalse(store.selectedAccount.isMicrosoft)
        XCTAssertTrue(store.offlineAccount.name == "Steve")

        // 切到正版：徽标 / 副标题走「正版」分支
        store.select("msa-test")
        XCTAssertTrue(store.selectedAccount.isMicrosoft)
        XCTAssertEqual(store.selectedAccount.name, "NotchPlayer")
        XCTAssertEqual(store.selectedAccount.uuid, "069a79f4-44e9-4726-a5be-fca90e38aaf5")

        // 正版可切回离线账户
        store.select(AuthAccountRecord.offlineID)
        XCTAssertFalse(store.selectedAccount.isMicrosoft)
        XCTAssertEqual(store.selectedAccount.kind, .offline)
    }

    /// 选中的正版账户被移除时回退到离线账户（徽标不会卡在「正版」）。
    @MainActor
    func testSelectedAccountFallsBackToOfflineWhenMissing() {
        let suite = "launcher.settings.accounts.fallback.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("无法创建临时 UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = LauncherSettings(defaults: defaults)
        settings.authAccounts = []
        settings.selectedAuthAccountID = "msa-missing"
        let store = AccountStore(settings: settings, tokenStore: InMemoryAuthTokenStore())
        XCTAssertFalse(store.selectedAccount.isMicrosoft)
        XCTAssertEqual(store.selectedAccount.id, AuthAccountRecord.offlineID)
    }

    // MARK: - 工具

    /// 把设置页所有分类的字段都改成非默认值（用于验证按分类重置的边界）。
    @MainActor
    private func makeAllSettingsNonDefault(_ settings: LauncherSettings, _ manager: LauncherThemeManager) {
        settings.gameDirectory = "/tmp/settings-reset-test-game"
        settings.versionIsolation = false
        settings.minimizeAfterLaunch = false
        settings.checkUpdatesOnStart = false
        settings.javaAutoDetect = false
        settings.javaRuntimePath = "/tmp/settings-reset-test/java"
        settings.maxMemoryMB = 6144
        settings.renderThreads = 6
        settings.jvmArguments = "-Xmx2G"
        settings.updateChannel = "snapshot"
        settings.downloadSource = "mirror"
        settings.autoCleanOldVersions = true
        settings.language = "en"
        settings.playerName = "AlexReset"
        settings.savedPlayerNames = ["AlexReset"]
        settings.selectedAuthAccountID = "msa-test"
        settings.updateFeedURL = "https://example.com/feed.json"
        manager.select("porcelain")
        manager.borderStrength = 1.3
        manager.cornerScale = 0.8
    }

    /// 断言某个分类当前是默认值（isDefault=true）或仍为非默认值（isDefault=false）。
    @MainActor
    private func assertSection(
        _ section: SettingsSection,
        isDefault: Bool,
        settings: LauncherSettings,
        manager: LauncherThemeManager,
        file: StaticString,
        line: UInt
    ) {
        switch section {
        case .launch:
            XCTAssertEqual(
                settings.gameDirectory,
                isDefault ? LauncherSettings.defaultGameDirectory : "/tmp/settings-reset-test-game",
                "游戏目录", file: file, line: line
            )
            XCTAssertEqual(settings.versionIsolation, isDefault, "版本隔离", file: file, line: line)
            XCTAssertEqual(settings.minimizeAfterLaunch, isDefault, "启动后最小化", file: file, line: line)
            XCTAssertEqual(settings.checkUpdatesOnStart, isDefault, "启动前检查更新", file: file, line: line)
        case .java:
            XCTAssertEqual(settings.javaAutoDetect, isDefault, "自动选择 Java", file: file, line: line)
            XCTAssertEqual(
                settings.javaRuntimePath,
                isDefault ? "" : "/tmp/settings-reset-test/java",
                "Java 路径", file: file, line: line
            )
        case .performance:
            XCTAssertEqual(settings.maxMemoryMB, isDefault ? 4096 : 6144, "最大内存", file: file, line: line)
            XCTAssertEqual(settings.renderThreads, isDefault ? 4 : 6, "渲染线程", file: file, line: line)
            XCTAssertEqual(
                settings.jvmArguments,
                isDefault ? "" : "-Xmx2G",
                "JVM 参数", file: file, line: line
            )
        case .update:
            XCTAssertEqual(
                settings.updateChannel,
                isDefault ? "release" : "snapshot",
                "更新通道", file: file, line: line
            )
            XCTAssertEqual(
                settings.downloadSource,
                isDefault ? "official" : "mirror",
                "下载源", file: file, line: line
            )
            XCTAssertEqual(settings.autoCleanOldVersions, !isDefault, "自动清理开关", file: file, line: line)
            XCTAssertEqual(
                settings.language,
                isDefault ? "zh-Hans" : "en",
                "界面语言", file: file, line: line
            )
        case .appearance:
            XCTAssertEqual(
                manager.themeID,
                isDefault ? LauncherThemes.default.id : "porcelain",
                "主题", file: file, line: line
            )
            XCTAssertEqual(manager.borderStrength, isDefault ? 1.0 : 1.3, accuracy: 0.001, "边框强度", file: file, line: line)
            XCTAssertEqual(manager.cornerScale, isDefault ? 1.0 : 0.8, accuracy: 0.001, "圆角缩放", file: file, line: line)
        case .account:
            XCTAssertEqual(
                settings.playerName,
                isDefault ? "Steve" : "AlexReset",
                "玩家名", file: file, line: line
            )
            XCTAssertEqual(
                settings.savedPlayerNames,
                isDefault ? ["Steve"] : ["AlexReset"],
                "保存的玩家名", file: file, line: line
            )
            XCTAssertEqual(
                settings.selectedAuthAccountID,
                isDefault ? AuthAccountRecord.offlineID : "msa-test",
                "选中账户", file: file, line: line
            )
        case .about:
            XCTAssertEqual(
                settings.updateFeedURL,
                isDefault ? "" : "https://example.com/feed.json",
                "更新源", file: file, line: line
            )
        case .log:
            // 日志与诊断没有可重置项：不做断言（由 hasResettableSettings 测试覆盖）。
            break
        }
    }

    // MARK: - 工具

    /// 建一个临时目录，测试结束自动清理。
    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("settings-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    /// 提取文案里的格式化占位符序列（%d / %@ / %s …），用于三语一致性校验。
    private static func specifiers(in text: String) -> [String] {
        let characters = Array(text)
        var result: [String] = []
        var index = 0
        while index < characters.count {
            if characters[index] == "%" {
                var cursor = index + 1
                while cursor < characters.count, characters[cursor] != "d",
                      characters[cursor] != "@", characters[cursor] != "s",
                      characters[cursor] != "f", characters[cursor] != "%" {
                    cursor += 1
                }
                if cursor >= characters.count { break }
                let symbol = String(characters[cursor])
                if symbol == "%" {
                    index = cursor + 1
                    continue
                }
                result.append(symbol)
                index = cursor + 1
            } else {
                index += 1
            }
        }
        return result
    }
}
