import AppKit
import Foundation

// 一筆備份封存的顯示資料。
struct BackupArchive: Identifiable, Hashable {
    let url: URL
    let name: String
    let sizeText: String
    let modified: Date

    var id: String { url.path }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var modifiedText: String { Self.dateFormatter.string(from: modified) }
}

struct BackupResult {
    let archive: URL
    let fileCount: Int
    let sizeText: String
    let included: [String]
    let skipped: [String]
}

struct RestoreResult {
    let items: [String]
}

enum BackupError: LocalizedError {
    case noSources
    case tarFailed(String)
    case noArchive

    var errorDescription: String? {
        switch self {
        case .noSources:
            return "在 Adobe 資料夾下找不到任何 LR 風格檔來源。"
        case .tarFailed(let message):
            return "tar 執行失敗：\(message)"
        case .noArchive:
            return "找不到指定的備份檔。"
        }
    }
}

// 備份／還原核心邏輯。無狀態，用 FileManager + 呼叫 /usr/bin/tar 實作，
// 行為與 CLI 版 lr-presets.sh 一致。
enum BackupService {
    static let archivePrefix = "lr-presets"

    // 備份項目（相對 adobeBase）。缺的會自動略過。
    // 明確不含：CameraRaw/ModelZoo(AI 模型)、Logs、GPU cache、app 偏好 plist。
    static let items = [
        "Lightroom",
        "CameraRaw/Settings",
        "CameraRaw/Defaults",
        "CameraRaw/ImportedSettings",
        "CameraRaw/CameraProfiles",
        "CameraRaw/LensProfiles",
        "CameraRaw/Curves",
        "CameraRaw/LocalCorrections",
        "CameraRaw/LensProfileDefaults",
    ]
    static let excludes = [".DS_Store", "*.log"]

    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var adobeBase: URL { home.appendingPathComponent("Library/Application Support/Adobe") }
    static var backupDir: URL { home.appendingPathComponent("Documents/LR-Presets-Backup") }

    // MARK: - 對外操作

    static func backup() throws -> BackupResult {
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)

        var included: [String] = []
        var skipped: [String] = []
        for item in items {
            let path = adobeBase.appendingPathComponent(item).path
            if FileManager.default.fileExists(atPath: path) {
                included.append(item)
            } else {
                skipped.append(item)
            }
        }
        guard !included.isEmpty else { throw BackupError.noSources }

        let archive = backupDir.appendingPathComponent("\(archivePrefix)-\(timestamp()).tar.gz")
        var arguments = ["-czf", archive.path]
        for exclude in excludes { arguments.append("--exclude=\(exclude)") }
        arguments.append(contentsOf: ["-C", adobeBase.path])
        arguments.append(contentsOf: included)

        let result = try run("/usr/bin/tar", arguments)
        guard result.status == 0 else { throw BackupError.tarFailed(result.output) }

        let listing = try run("/usr/bin/tar", ["-tzf", archive.path])
        let fileCount = listing.output
            .split(separator: "\n")
            .filter { !$0.hasSuffix("/") }
            .count

        return BackupResult(
            archive: archive,
            fileCount: fileCount,
            sizeText: sizeText(of: archive),
            included: included,
            skipped: skipped)
    }

    static func listArchives() -> [BackupArchive] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: backupDir, includingPropertiesForKeys: keys) else { return [] }

        return entries
            .filter { $0.lastPathComponent.hasPrefix("\(archivePrefix)-") && $0.pathExtension == "gz" }
            .map { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                let modified = values?.contentModificationDate ?? .distantPast
                let size = Int64(values?.fileSize ?? 0)
                return BackupArchive(
                    url: url,
                    name: url.lastPathComponent,
                    sizeText: ByteCountFormatter.string(fromByteCount: size, countStyle: .file),
                    modified: modified)
            }
            .sorted { $0.modified > $1.modified }
    }

    static func restore(_ archive: URL) throws -> RestoreResult {
        guard FileManager.default.fileExists(atPath: archive.path) else { throw BackupError.noArchive }
        try FileManager.default.createDirectory(at: adobeBase, withIntermediateDirectories: true)

        let result = try run("/usr/bin/tar", ["-xzf", archive.path, "-C", adobeBase.path])
        guard result.status == 0 else { throw BackupError.tarFailed(result.output) }

        let listing = try run("/usr/bin/tar", ["-tzf", archive.path])
        let tops = Set(listing.output.split(separator: "\n").map { line -> String in
            let parts = line.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: true)
            if parts.count >= 2 { return "\(parts[0])/\(parts[1])" }
            return String(parts.first ?? "")
        }).sorted()
        return RestoreResult(items: tops)
    }

    static func revealBackupFolder() {
        try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([backupDir])
    }

    // MARK: - 輔助

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    private static func sizeText(of url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    @discardableResult
    private static func run(_ launchPath: String, _ arguments: [String]) throws
        -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
