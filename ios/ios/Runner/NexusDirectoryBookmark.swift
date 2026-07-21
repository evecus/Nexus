import Flutter
import UIKit
import UniformTypeIdentifiers

/// "已授权目录"的原生桥接实现。
///
/// 对应 Dart 侧 `lib/bookmarks/ios_directory_bookmark.dart` 里
/// `IosDirectoryBookmark` 类的 MethodChannel(`com.nexus.mobile/directory_bookmark`)。
///
/// ## 核心机制
/// iOS 严格来说并不提供 macOS 那种"security-scoped bookmark"沙盒穿透
/// 机制(那是仅 macOS 独有的 App Sandbox 特性)；在 iOS 上，通过
/// `UIDocumentPickerViewController` 选中一个文件夹后，依然可以拿到一份
/// 常规的 `URL` bookmark 并长期持久化——只是每次真正读取该 URL 下的内容
/// 前后，仍然需要成对调用 `startAccessingSecurityScopedResource()` /
/// `stopAccessingSecurityScopedResource()`(这两个方法在 iOS 上依然有效，
/// 只是底层实现与 macOS 不同)。这是苹果官方开发者论坛确认过的正确用法，
/// 而不是"iOS 完全不支持任何持久化的文件夹访问"。
///
/// 本类把每个已授权目录的 bookmark 数据(`Data`)以"稳定 id → bookmark"
/// 的形式落盘到 App 自己的 Documents 目录下的一个 JSON 索引文件里，
/// 每次列目录/枚举文件时重新解析 bookmark 为 URL，用完即释放访问权限，
/// 不长期持有。
final class NexusDirectoryBookmark: NSObject, FlutterPlugin {

    static let channelName = "com.nexus.mobile/directory_bookmark"

    /// bookmark 索引文件路径：Documents/.nexus_directory_bookmarks.json
    /// 使用点前缀避免出现在"文件" App 里用户可见的常规文件列表中。
    private static var indexFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(".nexus_directory_bookmarks.json")
    }

    /// 索引结构：[{"id": "...", "displayName": "...", "bookmark": "<base64>"}]
    private struct Entry: Codable {
        let id: String
        let displayName: String
        let bookmarkBase64: String
    }

    private var pendingPickerResult: FlutterResult?

    static func register(with registrar: FlutterPluginRegistrar) {
        let instance = NexusDirectoryBookmark()
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "pickAndAddDirectory":
            pickAndAddDirectory(result: result)
        case "listDirectories":
            result(listDirectories())
        case "removeDirectory":
            guard let args = call.arguments as? [String: Any],
                  let id = args["id"] as? String else {
                result(FlutterError(code: "BAD_ARGS", message: "missing id", details: nil))
                return
            }
            removeDirectory(id: id)
            result(nil)
        case "listFiles":
            guard let args = call.arguments as? [String: Any],
                  let id = args["id"] as? String,
                  let extensions = args["extensions"] as? [String] else {
                result(FlutterError(code: "BAD_ARGS", message: "missing id/extensions", details: nil))
                return
            }
            result(listFiles(id: id, extensions: Set(extensions.map { $0.lowercased() })))
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - 索引读写

    private func loadIndex() -> [Entry] {
        guard let data = try? Data(contentsOf: Self.indexFileURL) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private func saveIndex(_ entries: [Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: Self.indexFileURL, options: .atomic)
    }

    // MARK: - 添加目录(弹出系统文件夹选择器)

    private func pickAndAddDirectory(result: @escaping FlutterResult) {
        guard let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first else {
            result(FlutterError(code: "NO_ROOT_VC", message: "no root view controller", details: nil))
            return
        }
        pendingPickerResult = result
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        rootVC.present(picker, animated: true)
    }

    /// 把选中的目录 URL 转换成 bookmark 并追加进索引，去重(同一物理目录
    /// 已存在时不重复添加，直接返回已有条目的显示名)。
    private func addDirectory(url: URL) -> String? {
        // 必须先取得访问权限才能创建 bookmark。
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        guard let bookmark = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return nil
        }

        var entries = loadIndex()
        let displayName = url.lastPathComponent

        // 去重：尝试解析已存在的每个 bookmark，若指向同一路径则视为重复，
        // 不重复添加。
        for existing in entries {
            guard let existingData = Data(base64Encoded: existing.bookmarkBase64) else { continue }
            var isStale = false
            if let existingURL = try? URL(
                resolvingBookmarkData: existingData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), existingURL.standardizedFileURL == url.standardizedFileURL {
                return existing.displayName
            }
        }

        let entry = Entry(
            id: UUID().uuidString,
            displayName: displayName,
            bookmarkBase64: bookmark.base64EncodedString()
        )
        entries.append(entry)
        saveIndex(entries)
        return displayName
    }

    // MARK: - 列出已授权目录

    private func listDirectories() -> [[String: Any]] {
        return loadIndex().map { entry in
            var accessible = false
            if let data = Data(base64Encoded: entry.bookmarkBase64) {
                var isStale = false
                if let url = try? URL(
                    resolvingBookmarkData: data,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ) {
                    let didAccess = url.startAccessingSecurityScopedResource()
                    accessible = FileManager.default.fileExists(atPath: url.path)
                    if didAccess { url.stopAccessingSecurityScopedResource() }
                }
            }
            return [
                "id": entry.id,
                "displayName": entry.displayName,
                "accessible": accessible,
            ]
        }
    }

    // MARK: - 移除目录

    private func removeDirectory(id: String) {
        var entries = loadIndex()
        entries.removeAll { $0.id == id }
        saveIndex(entries)
    }

    // MARK: - 枚举文件

    private func listFiles(id: String, extensions: Set<String>) -> [[String: Any]] {
        guard let entry = loadIndex().first(where: { $0.id == id }),
              let data = Data(base64Encoded: entry.bookmarkBase64) else {
            return []
        }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return []
        }

        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        guard FileManager.default.fileExists(atPath: url.path) else { return [] }

        var out: [[String: Any]] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true } // 单个文件/目录出错时继续枚举，不中断整体
        ) else {
            return []
        }

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isDirectory == true { continue }
            let ext = "." + fileURL.pathExtension.lowercased()
            guard extensions.contains(ext) else { continue }
            let size = values.fileSize ?? 0
            let modified = values.contentModificationDate.map {
                Int($0.timeIntervalSince1970 * 1000)
            } ?? 0
            out.append([
                "path": fileURL.path,
                "name": fileURL.lastPathComponent,
                "size": size,
                "modified": modified,
                "folder": fileURL.deletingLastPathComponent().path,
            ])
        }
        return out
    }
}

// MARK: - UIDocumentPickerDelegate

extension NexusDirectoryBookmark: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            pendingPickerResult?(nil)
            pendingPickerResult = nil
            return
        }
        let name = addDirectory(url: url)
        pendingPickerResult?(name)
        pendingPickerResult = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        pendingPickerResult?(nil)
        pendingPickerResult = nil
    }
}
