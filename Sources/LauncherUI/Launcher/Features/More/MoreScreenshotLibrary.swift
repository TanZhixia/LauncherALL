import AppKit
import Foundation
import ImageIO

// MARK: - 截图条目

/// `screenshots/` 目录里的一张真实截图。
public struct MoreScreenshotItem: Identifiable, Equatable, Sendable {
    /// 图片文件路径。
    public let url: URL
    /// 文件名。
    public let fileName: String
    /// 真实字节大小。
    public let byteSize: Int64
    /// 文件修改时间。
    public let modifiedAt: Date

    public var id: URL { url }

    public init(url: URL, fileName: String, byteSize: Int64, modifiedAt: Date) {
        self.url = url
        self.fileName = fileName
        self.byteSize = byteSize
        self.modifiedAt = modifiedAt
    }

    /// 人读大小，例如 "1.2 MB"。
    public var sizeText: String {
        MoreFormatting.byteCountText(byteSize)
    }

    /// 修改日期，例如 "2026-10-28 14:20"。
    public var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: modifiedAt)
    }
}

// MARK: - 截图库

/// 截图相册：真实扫描实例 `screenshots/`，用 ImageIO 生成受限像素尺寸的缩略图（避免大图占内存）。
public enum MoreScreenshotLibrary {
    /// 截图目录名。
    public static let screenshotsFolderName = "screenshots"
    /// 支持的图片后缀。
    public static let supportedExtensions: Set<String> = ["png", "jpg", "jpeg"]

    /// 实例下的截图目录。
    public static func screenshotsDirectory(in instanceDirectory: URL) -> URL {
        instanceDirectory.appendingPathComponent(screenshotsFolderName, isDirectory: true)
    }

    /// 是否是支持的图片文件。
    public static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// 扫描真实截图列表（按修改时间倒序，最新在前）。
    public static func scan(in screenshotsDirectory: URL) -> [MoreScreenshotItem] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: screenshotsDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return entries
            .filter { isSupported($0) }
            .compactMap { url -> MoreScreenshotItem? in
                let values = try? url.resourceValues(forKeys: [
                    .fileSizeKey,
                    .totalFileAllocatedSizeKey,
                    .contentModificationDateKey,
                    .isRegularFileKey
                ])
                guard values?.isRegularFile != false else { return nil }
                let size = Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
                let modified = values?.contentModificationDate ?? .distantPast
                return MoreScreenshotItem(
                    url: url,
                    fileName: url.lastPathComponent,
                    byteSize: size,
                    modifiedAt: modified
                )
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// 截图总占用字节数。
    public static func totalSize(_ items: [MoreScreenshotItem]) -> Int64 {
        items.reduce(0) { $0 + $1.byteSize }
    }

    /// 截图总占用人读文本。
    public static func totalSizeText(_ items: [MoreScreenshotItem]) -> String {
        MoreFormatting.byteCountText(totalSize(items))
    }

    /// 生成缩略图：ImageIO 直接按目标像素尺寸解码，不把原图完整读进内存。
    /// - Parameters:
    ///   - url: 原始图片路径。
    ///   - maxPixelSize: 最长边像素上限（例如 320）。
    public static func thumbnail(for url: URL, maxPixelSize: Int = 320) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
    }

    /// 删除一张截图到废纸篓（调用方负责二次确认）。
    public static func delete(_ item: MoreScreenshotItem) throws {
        try InstanceActions.trash(item.url)
    }
}
