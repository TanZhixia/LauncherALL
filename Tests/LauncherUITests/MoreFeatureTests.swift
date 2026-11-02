import XCTest
import AppKit

@testable import LauncherUI

/// 更多页真实功能测试：备份 zip 生命周期、模组扫描与启停、截图扫描与缩略图、日志导出文本。
/// 全部使用临时目录中的真实文件，不触碰用户的游戏目录。
final class MoreFeatureTests: XCTestCase {

    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    // MARK: - 临时目录

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MoreFeatureTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - 备份：命名与内容清单

    // MARK: - 格式化

    func testByteCountTextHandlesZeroBytes() {
        XCTAssertEqual(MoreFormatting.byteCountText(Int64(0)), "0 B")
        XCTAssertEqual(MoreFormatting.byteCountText(0), "0 B")
        XCTAssertFalse(MoreFormatting.byteCountText(Int64(1_048_576)).isEmpty)
    }


    func testBackupFileNameRoundTrip() {
        let fileName = MoreBackupService.makeFileName(versionID: "1.21.4", date: Date())
        XCTAssertTrue(fileName.hasPrefix("1.21.4-"))
        XCTAssertTrue(fileName.hasSuffix(".zip"))
        XCTAssertEqual(MoreBackupService.instanceName(fromFileName: fileName), "1.21.4")
    }

    func testBackupFileNameSanitizesIllegalCharacters() {
        XCTAssertEqual(MoreBackupService.sanitizedInstanceName("a/b:c"), "a-b-c")
        XCTAssertEqual(MoreBackupService.sanitizedInstanceName("   "), "instance")
        XCTAssertNil(MoreBackupService.instanceName(fromFileName: "没有时间戳.zip"))
    }

    func testBackupEntriesReflectRealFiles() throws {
        let gameDirectory = try makeTemporaryDirectory().appendingPathComponent("game")
        let instance = gameDirectory.appendingPathComponent("versions/1.21.4", isDirectory: true)
        try write("world", to: instance.appendingPathComponent("saves/world/level.dat"))
        try write("{\"fov\":0.5}", to: instance.appendingPathComponent("options.txt"))

        let entries = MoreBackupService.entries(instanceDirectory: instance)
        XCTAssertEqual(entries.count, MoreBackupService.entryTitles.count)
        XCTAssertEqual(entries.first { $0.relativePath == "saves" }?.exists, true)
        XCTAssertEqual(entries.first { $0.relativePath == "options.txt" }?.exists, true)
        XCTAssertEqual(entries.first { $0.relativePath == "mods" }?.exists, false)
    }

    // MARK: - 备份：真实打包与恢复

    func testBackupCreateListAndRestore() throws {
        let fileManager = FileManager.default
        let gameDirectory = try makeTemporaryDirectory().appendingPathComponent("game")
        let instance = gameDirectory.appendingPathComponent("versions/1.21.4", isDirectory: true)
        let saveFile = instance.appendingPathComponent("saves/a.txt")
        try write("world-data", to: saveFile)
        try write("enabled", to: instance.appendingPathComponent("mods/a.jar"))
        try write("disabled", to: instance.appendingPathComponent("mods/b.jar.disabled"))

        let backup = try MoreBackupService.createBackup(
            versionID: "1.21.4",
            instanceDirectory: instance,
            gameDirectory: gameDirectory
        )

        XCTAssertTrue(fileManager.fileExists(atPath: backup.url.path))
        XCTAssertGreaterThan(backup.byteSize, 0)
        XCTAssertTrue(MoreBackupService.isInsideBackups(backup.url, gameDirectory: gameDirectory))
        XCTAssertEqual(MoreBackupService.instanceName(fromFileName: backup.name), "1.21.4")

        let listed = MoreBackupService.list(gameDirectory: gameDirectory)
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?.name, backup.name)
        XCTAssertGreaterThan(MoreBackupService.totalSize(gameDirectory: gameDirectory), 0)

        // 暂存目录必须清理干净，不能污染 backups/
        let leftovers = try fileManager.contentsOfDirectory(atPath: MoreBackupService.backupsDirectory(gameDirectory: gameDirectory).path)
        XCTAssertFalse(leftovers.contains { $0.hasPrefix(".staging-") }, "临时暂存目录未清理：\(leftovers)")

        // 恢复后文件内容回到备份时的状态
        try write("changed-after-backup", to: saveFile)
        try MoreBackupService.restore(backup, instanceDirectory: instance, gameDirectory: gameDirectory)
        XCTAssertEqual(try String(contentsOf: saveFile, encoding: .utf8), "world-data")
    }

    func testBackupEmptyInstanceThrows() throws {
        let gameDirectory = try makeTemporaryDirectory().appendingPathComponent("game")
        let instance = gameDirectory.appendingPathComponent("versions/empty", isDirectory: true)
        try FileManager.default.createDirectory(at: instance, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try MoreBackupService.createBackup(versionID: "empty", instanceDirectory: instance, gameDirectory: gameDirectory)
        ) { error in
            guard case MoreBackupError.emptyInstance = error else {
                return XCTFail("期望 emptyInstance，实际：\(error)")
            }
        }
    }

    func testRestoreRejectsBackupOutsideBackupsDirectory() throws {
        let gameDirectory = try makeTemporaryDirectory().appendingPathComponent("game")
        let instance = gameDirectory.appendingPathComponent("versions/1.21.4", isDirectory: true)
        try write("not-a-backup", to: instance.appendingPathComponent("evil.zip"))
        let item = MoreBackupItem(
            url: instance.appendingPathComponent("evil.zip"),
            name: "evil.zip",
            byteSize: 10,
            createdAt: Date(),
            instanceGuess: nil
        )
        XCTAssertThrowsError(
            try MoreBackupService.restore(item, instanceDirectory: instance, gameDirectory: gameDirectory)
        )
    }

    // MARK: - 模组扫描与启停

    func testModScanCountsAndNames() throws {
        let mods = try makeTemporaryDirectory().appendingPathComponent("mods")
        try write("a", to: mods.appendingPathComponent("Sodium.jar"))
        try write("b", to: mods.appendingPathComponent("Iris.jar.disabled"))
        try write("c", to: mods.appendingPathComponent("readme.txt"))

        let items = MoreModLibrary.scan(in: mods)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.displayName).sorted(), ["Iris.jar", "Sodium.jar"])
        let counts = MoreModLibrary.counts(items)
        XCTAssertEqual(counts.enabled, 1)
        XCTAssertEqual(counts.disabled, 1)
        XCTAssertEqual(MoreModLibrary.displayName(for: "Iris.jar.disabled"), "Iris.jar")
        XCTAssertEqual(MoreModLibrary.displayName(for: "Sodium.jar"), "Sodium.jar")
    }

    func testModEnableDisableRenamesFiles() throws {
        let fileManager = FileManager.default
        let mods = try makeTemporaryDirectory().appendingPathComponent("mods")
        try write("a", to: mods.appendingPathComponent("Sodium.jar.disabled"))

        let disabled = try XCTUnwrap(MoreModLibrary.scan(in: mods).first)
        XCTAssertFalse(disabled.isEnabled)

        let enabledURL = try MoreModLibrary.setEnabled(disabled, enabled: true)
        XCTAssertEqual(enabledURL.lastPathComponent, "Sodium.jar")
        XCTAssertTrue(fileManager.fileExists(atPath: enabledURL.path))
        XCTAssertFalse(fileManager.fileExists(atPath: disabled.url.path))

        let enabled = try XCTUnwrap(MoreModLibrary.scan(in: mods).first)
        XCTAssertTrue(enabled.isEnabled)
        let disabledURL = try MoreModLibrary.setEnabled(enabled, enabled: false)
        XCTAssertEqual(disabledURL.lastPathComponent, "Sodium.jar.disabled")
    }

    func testModEnableDetectsNameCollision() throws {
        let mods = try makeTemporaryDirectory().appendingPathComponent("mods")
        try write("enabled", to: mods.appendingPathComponent("Sodium.jar"))
        try write("disabled", to: mods.appendingPathComponent("Sodium.jar.disabled"))

        let disabledItem = try XCTUnwrap(
            MoreModLibrary.scan(in: mods).first { !$0.isEnabled }
        )
        XCTAssertThrowsError(try MoreModLibrary.setEnabled(disabledItem, enabled: true)) { error in
            guard case MoreModError.targetExists = error else {
                return XCTFail("期望 targetExists，实际：\(error)")
            }
        }
    }

    func testModFilterAndSort() throws {
        let mods = try makeTemporaryDirectory().appendingPathComponent("mods")
        try write("a", to: mods.appendingPathComponent("beta.jar"))
        try write("b", to: mods.appendingPathComponent("Alpha.jar"))
        try write("c", to: mods.appendingPathComponent("gamma.jar.disabled"))

        let items = MoreModLibrary.scan(in: mods)
        XCTAssertEqual(items.map(\.displayName), ["Alpha.jar", "beta.jar", "gamma.jar"])

        let descending = MoreModLibrary.sorted(items, ascending: false)
        XCTAssertEqual(descending.map(\.displayName), ["gamma.jar", "beta.jar", "Alpha.jar"])

        XCTAssertEqual(MoreModLibrary.filtered(items, query: "ALPHA").map(\.displayName), ["Alpha.jar"])
        XCTAssertEqual(MoreModLibrary.filtered(items, query: "  ").count, 3)
    }

    // MARK: - 截图扫描与缩略图

    func testScreenshotScanFiltersSupportedExtensions() throws {
        let screenshots = try makeTemporaryDirectory().appendingPathComponent("screenshots")
        try write("png", to: screenshots.appendingPathComponent("2026-11-01_18.00.00.png"))
        try write("jpg", to: screenshots.appendingPathComponent("2026-11-01_18.01.00.JPG"))
        try write("txt", to: screenshots.appendingPathComponent("notes.txt"))

        let items = MoreScreenshotLibrary.scan(in: screenshots)
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { $0.byteSize > 0 })
        XCTAssertGreaterThan(MoreScreenshotLibrary.totalSize(items), 0)
        XCTAssertFalse(MoreScreenshotLibrary.totalSizeText(items).isEmpty)
        XCTAssertTrue(MoreScreenshotLibrary.isSupported(URL(fileURLWithPath: "/tmp/a.PNG")))
        XCTAssertFalse(MoreScreenshotLibrary.isSupported(URL(fileURLWithPath: "/tmp/a.gif")))
    }

    func testScreenshotThumbnailIsDownsampled() throws {
        let directory = try makeTemporaryDirectory()
        let url = directory.appendingPathComponent("shot.png")

        let width = 800
        let height = 600
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()

        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: url)

        let thumbnail = try XCTUnwrap(MoreScreenshotLibrary.thumbnail(for: url, maxPixelSize: 160))
        XCTAssertLessThanOrEqual(max(thumbnail.size.width, thumbnail.size.height), 160)
        XCTAssertGreaterThan(thumbnail.size.width, 0)
    }

    // MARK: - 日志导出

    func testLogExportContentContainsRealHeader() {
        let buildInfo = LauncherBuildInfo(
            version: "0.2.0",
            buildDate: Date(timeIntervalSince1970: 1_800_000_000),
            commit: "abc1234"
        )
        let text = MoreLogExporter.content(
            logs: ["line-1", "line-2"],
            commandLine: "java -jar client.jar",
            exitCode: 3,
            installedVersionCount: 4,
            javaRuntimeCount: 2,
            gameDirectoryPath: "/tmp/game",
            buildInfo: buildInfo,
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        XCTAssertTrue(text.contains("v0.2.0"))
        XCTAssertTrue(text.contains("abc1234"))
        XCTAssertTrue(text.contains("启动命令：java -jar client.jar"))
        XCTAssertTrue(text.contains("退出码：3"))
        XCTAssertTrue(text.contains("已安装 4 个版本"))
        XCTAssertTrue(text.contains("游戏目录：/tmp/game"))
        XCTAssertTrue(text.contains("line-1"))
        XCTAssertTrue(text.contains("line-2"))
    }

    func testLogDiagnosticsLimitRecentLines() {
        let buildInfo = LauncherBuildInfo(version: "0.2.0", buildDate: Date(), commit: "abc")
        let logs = (0..<300).map { "line-\($0)" }
        let text = MoreLogExporter.diagnosticsText(
            logs: logs,
            commandLine: nil,
            exitCode: nil,
            installedVersionCount: 0,
            javaRuntimeCount: 0,
            gameDirectoryPath: nil,
            buildInfo: buildInfo
        )
        XCTAssertFalse(text.contains("line-0\n"))
        XCTAssertTrue(text.contains("line-299"))
        XCTAssertTrue(text.contains("（尚未启动过游戏）"))
    }

    func testLogExportWritesUniqueFiles() throws {
        let directory = try makeTemporaryDirectory()
        let buildInfo = LauncherBuildInfo(version: "0.2.0", buildDate: Date(), commit: "abc")
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        let first = try MoreLogExporter.export(
            logs: ["hello"],
            commandLine: nil,
            exitCode: nil,
            installedVersionCount: 1,
            javaRuntimeCount: 1,
            gameDirectoryPath: "/tmp/game",
            buildInfo: buildInfo,
            generatedAt: date,
            to: directory
        )
        let second = try MoreLogExporter.export(
            logs: ["hello"],
            commandLine: nil,
            exitCode: nil,
            installedVersionCount: 1,
            javaRuntimeCount: 1,
            gameDirectoryPath: "/tmp/game",
            buildInfo: buildInfo,
            generatedAt: date,
            to: directory
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: first.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.url.path))
        XCTAssertNotEqual(first.url, second.url)
        XCTAssertGreaterThan(first.byteCount, 0)
        XCTAssertTrue(first.url.lastPathComponent.hasSuffix(".log"))
        XCTAssertTrue(second.url.lastPathComponent.hasSuffix("-2.log"))

        let content = try String(contentsOf: first.url, encoding: .utf8)
        XCTAssertTrue(content.contains("hello"))
        XCTAssertGreaterThan(MoreLogExporter.totalByteCount(["a", "b"]), 2)
    }

    // MARK: - 回归：日志落点与暂存目录清理

    /// 回归（task-12 / P2-11）：默认日志落点必须固定在 ~/Library/Logs/BlockLauncher，
    /// 与设置页统一，避免两个"导出日志"写到不同位置。
    func testLogsDirectoryStaysInLibraryLogs() {
        let path = MoreLogExporter.logsDirectory().path
        XCTAssertTrue(path.hasSuffix("/Library/Logs/BlockLauncher"), "日志落点被改动：\(path)")
        XCTAssertTrue(path.hasPrefix(NSHomeDirectory()))
    }

    /// 回归：备份前会清理 1 小时前的 `.staging-*` 崩溃残骸，但保留仍在进行的暂存目录。
    func testBackupRemovesStaleStagingDirectoriesOnly() throws {
        let fileManager = FileManager.default
        let gameDirectory = try makeTemporaryDirectory().appendingPathComponent("game")
        let instance = gameDirectory.appendingPathComponent("versions/1.21.4", isDirectory: true)
        try write("world", to: instance.appendingPathComponent("saves/a.txt"))

        let backups = MoreBackupService.backupsDirectory(gameDirectory: gameDirectory)
        try fileManager.createDirectory(at: backups, withIntermediateDirectories: true)
        let stale = backups.appendingPathComponent(".staging-stale", isDirectory: true)
        let fresh = backups.appendingPathComponent(".staging-fresh", isDirectory: true)
        try fileManager.createDirectory(at: stale, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: fresh, withIntermediateDirectories: true)
        try fileManager.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-7200)],
            ofItemAtPath: stale.path
        )

        _ = try MoreBackupService.createBackup(
            versionID: "1.21.4",
            instanceDirectory: instance,
            gameDirectory: gameDirectory
        )

        XCTAssertFalse(fileManager.fileExists(atPath: stale.path), "过期暂存目录未被清理")
        XCTAssertTrue(fileManager.fileExists(atPath: fresh.path), "进行中的暂存目录被误删")
        let remaining = try fileManager.contentsOfDirectory(atPath: backups.path)
        XCTAssertFalse(remaining.contains { $0.hasPrefix(".staging-") && $0 != ".staging-fresh" })
    }
}
