import Foundation
import AppKit
import UniformTypeIdentifiers
import PDFKit
import Compression

/// 书籍元数据
struct BookMetadata {
    let title: String
    let author: String?
    let coverImage: Data?
    let pageCount: Int?
}

/// LibraryManager - 管理书籍导入和元数据解析
@MainActor
final class LibraryManager {
    static let shared = LibraryManager()

    private init() {}

    // MARK: - Book Import

    /// 从 URL 导入书籍
    func importBook(from url: URL) -> BookItem? {
        // 检查文件类型
        guard let fileType = getFileType(for: url) else {
            print("Unsupported file type")
            return nil
        }
        
        // Critical for Sandbox: Access the security scoped resource BEFORE reading/bookmarking
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // 获取安全作用域书签
        guard let bookmarkData = createBookmark(for: url) else {
            print("Failed to create bookmark")
            return nil
        }

        // 解析元数据
        let metadata = parseMetadata(from: url, fileType: fileType)

        // 创建 BookItem
        let book = BookItem(
            title: metadata.title,
            author: metadata.author,
            bookmarkData: bookmarkData,
            fileType: fileType,
            coverImageData: metadata.coverImage,
            pageCount: metadata.pageCount,
            filePath: url.path
        )

        return book
    }

    // MARK: - Security Scoped Bookmarks

    private func createBookmark(for url: URL) -> Data? {
        let bookmarkOptions: NSURL.BookmarkCreationOptions = [
            .withSecurityScope,
            .securityScopeAllowOnlyReadAccess
        ]

        return try? url.bookmarkData(
            options: bookmarkOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// 解析书签数据获取 URL
    func resolveBookmark(_ bookmarkData: Data) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    /// 开始访问安全作用域资源
    func startAccessing(bookmarkData: Data) -> Bool {
        guard let url = resolveBookmark(bookmarkData) else { return false }
        return url.startAccessingSecurityScopedResource()
    }

    /// 停止访问安全作用域资源
    func stopAccessing(bookmarkData: Data) {
        guard let url = resolveBookmark(bookmarkData) else { return }
        url.stopAccessingSecurityScopedResource()
    }

    // MARK: - File Type Detection

    private func getFileType(for url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf":
            return "pdf"
        case "epub":
            return "epub"
        default:
            return nil
        }
    }

    // MARK: - Metadata Parsing

    private func parseMetadata(from url: URL, fileType: String) -> BookMetadata {
        switch fileType {
        case "pdf":
            return parsePDFMetadata(from: url)
        case "epub":
            return parseEPUBMetadata(from: url)
        default:
            return BookMetadata(title: url.lastPathComponent, author: nil, coverImage: nil, pageCount: nil)
        }
    }

    // MARK: - PDF Metadata

    private func parsePDFMetadata(from url: URL) -> BookMetadata {
        guard let pdfDocument = PDFDocument(url: url) else {
            return BookMetadata(title: url.lastPathComponent, author: nil, coverImage: nil, pageCount: nil)
        }

        // 获取标题
        var title = url.lastPathComponent
        if let pdfTitle = pdfDocument.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String, !pdfTitle.isEmpty {
            title = pdfTitle
        }

        // 获取作者
        let author = pdfDocument.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String

        // 获取页数
        let pageCount = pdfDocument.pageCount

        // 生成封面（第一页缩略图）
        let coverImage = generatePDFThumbnail(from: pdfDocument)

        return BookMetadata(title: title, author: author, coverImage: coverImage, pageCount: pageCount)
    }

    private func generatePDFThumbnail(from pdfDocument: PDFDocument) -> Data? {
        guard let page = pdfDocument.page(at: 0) else { return nil }

        // 缩略图大小
        let thumbnailSize: CGFloat = 300
        let bounds = page.bounds(for: .mediaBox)
        let pageSize = bounds.size

        // 计算缩放比例
        let scaleX = thumbnailSize / pageSize.width
        let scaleY = thumbnailSize / pageSize.height
        let scale = min(scaleX, scaleY)

        let scaledSize = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)

        // 创建图像表示
        let image = NSImage(size: scaledSize)
        image.lockFocus()

        let transform = NSAffineTransform()
        transform.scale(by: scale)
        transform.concat()

        if let context = NSGraphicsContext.current?.cgContext {
            page.draw(with: .mediaBox, to: context)
        }

        image.unlockFocus()

        // 转换为 PNG 数据
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }

    // MARK: - EPUB Metadata

    private func parseEPUBMetadata(from url: URL) -> BookMetadata {
        // 创建临时目录解压 EPUB
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            // 解压 EPUB（ZIP 格式）
            guard unzipEPUB(at: url, to: tempDir) else {
                return BookMetadata(title: url.lastPathComponent, author: nil, coverImage: nil, pageCount: nil)
            }

            // 解析 OPF 文件获取元数据
            let metadata = parseEPUBOPF(at: tempDir)

            // 清理临时目录
            try? FileManager.default.removeItem(at: tempDir)

            return metadata

        } catch {
            print("Error parsing EPUB: \(error)")
            return BookMetadata(title: url.lastPathComponent, author: nil, coverImage: nil, pageCount: nil)
        }
    }

    private func unzipEPUB(at sourceURL: URL, to destinationURL: URL) -> Bool {
        // 使用简单的 unzip 命令或手动解压
        // 这里使用 Foundation 的 ZIP 支持（如果可用）或调用系统工具

        // 简单实现：使用系统的 unzip 命令
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", sourceURL.path, "-d", destinationURL.path]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            print("Unzip failed: \(error)")
            return false
        }
    }

    private func parseEPUBOPF(at tempDir: URL) -> BookMetadata {
        // 查找 OPF 文件（通常在 OEBPS 或 META-INF 目录）
        let possiblePaths = [
            tempDir.appendingPathComponent("OEBPS/content.opf"),
            tempDir.appendingPathComponent("OPS/content.opf"),
            tempDir.appendingPathComponent("content.opf")
        ]

        var opfURL: URL?
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path.path) {
                opfURL = path
                break
            }
        }

        // 如果找不到，尝试从 container.xml 解析
        if opfURL == nil {
            if let containerPath = findOPFPath(from: tempDir) {
                opfURL = containerPath
            }
        }

        guard let url = opfURL,
              let opfContent = try? String(contentsOf: url),
              let (title, author) = parseOPFMetadata(opfContent) else {
            return BookMetadata(title: tempDir.lastPathComponent, author: nil, coverImage: nil, pageCount: nil)
        }

        // 尝试提取封面
        let coverImage = extractEPUBCover(from: tempDir, opfContent: opfContent)

        // 估算章节数（页数）
        let pageCount = estimateEPUBPageCount(from: opfContent)

        return BookMetadata(title: title, author: author, coverImage: coverImage, pageCount: pageCount)
    }

    private func findOPFPath(from tempDir: URL) -> URL? {
        let containerPath = tempDir.appendingPathComponent("META-INF/container.xml")
        guard let containerContent = try? String(contentsOf: containerPath) else {
            return nil
        }

        // 简单解析 XML 查找 rootfile
        if let range = containerContent.range(of: "full-path=\"([^\"]+)\"", options: .regularExpression) {
            let relativePath = String(containerContent[range]).dropFirst(10).dropLast(1)
            return tempDir.appendingPathComponent(String(relativePath))
        }

        return nil
    }

    private func parseOPFMetadata(_ content: String) -> (title: String, author: String?)? {
        // 使用正则表达式提取 dc:title 和 dc:creator
        var title: String?
        var author: String?

        // 提取标题
        if let titleRange = content.range(of: "<dc:title[^>]*>([^<]+)</dc:title>", options: .regularExpression) {
            let match = String(content[titleRange])
            title = match.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        }

        // 提取作者
        if let authorRange = content.range(of: "<dc:creator[^>]*>([^<]+)</dc:creator>", options: .regularExpression) {
            let match = String(content[authorRange])
            author = match.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        }

        if let unwrappedTitle = title {
            return (unwrappedTitle.trimmingCharacters(in: .whitespacesAndNewlines), author?.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return nil
    }

    private func extractEPUBCover(from tempDir: URL, opfContent: String) -> Data? {
        // 查找封面图片引用
        let coverPattern = "<item[^>]+id=[\"']cover[\"'][^>]+href=[\"']([^\"']+)[\"']"
        guard let range = opfContent.range(of: coverPattern, options: .regularExpression) else {
            return nil
        }

        let match = String(opfContent[range])
        guard let hrefRange = match.range(of: "href=[\"']([^\"']+)[\"']", options: .regularExpression) else {
            return nil
        }

        let href = String(match[hrefRange])
            .replacingOccurrences(of: "href=[\"']", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[\"']", with: "", options: .regularExpression)

        // 构建完整路径
        let possiblePaths = [
            tempDir.appendingPathComponent("OEBPS").appendingPathComponent(href),
            tempDir.appendingPathComponent("OPS").appendingPathComponent(href),
            tempDir.appendingPathComponent(href)
        ]

        for path in possiblePaths where FileManager.default.fileExists(atPath: path.path) {
            return try? Data(contentsOf: path)
        }

        return nil
    }

    private func estimateEPUBPageCount(from opfContent: String) -> Int {
        // 计算 spine 中的 itemref 数量作为页数估算
        let pattern = "<itemref[^>]+>"
        let matches = opfContent.libraryMatches(for: pattern)
        return max(1, matches.count)
    }
}

// MARK: - String Extension for Regex

extension String {
    func libraryMatches(for regex: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: regex) else { return [] }
        let range = NSRange(location: 0, length: self.utf16.count)
        let matches = regex.matches(in: self, range: range)
        return matches.map { String(self[Range($0.range, in: self)!]) }
    }
}
