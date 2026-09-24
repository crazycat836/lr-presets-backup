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
    case noSources(String)
    case tarFailed(String)
    case noArchive
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSources(let group):
            return "「\(group)」找不到任何備份來源項目。"
        case .tarFailed(let message):
            return "tar 執行失敗：\(message)"
        case .noArchive:
            return "找不到指定的備份檔。"
        case .commandFailed(let message):
            return message
        }
    }
}

// tar.gz 快照備份／還原核心邏輯。無狀態，用 FileManager + 呼叫 /usr/bin/tar 實作。
enum BackupService {
    // MARK: - 對外操作

    static func backup(group: ArchiveGroup, to snapshotsDir: URL) throws -> BackupResult {
        try FileManager.default.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)

        var included: [String] = []
        var skipped: [String] = []
        for item in group.items {
            let path = group.baseURL.appendingPathComponent(item).path
            if FileManager.default.fileExists(atPath: path) {
                included.append(item)
            } else {
                skipped.append(item)
            }
        }
        guard !included.isEmpty else { throw BackupError.noSources(group.title) }

        let archive = snapshotsDir.appendingPathComponent("\(group.key)-\(timestamp()).tar.gz")
        var arguments = ["-czf", archive.path]
        for exclude in group.excludes { arguments.append("--exclude=\(exclude)") }
        arguments.append(contentsOf: ["-C", group.baseURL.path])
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

    static func listArchives(in snapshotsDir: URL) -> [BackupArchive] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: snapshotsDir, includingPropertiesForKeys: keys) else { return [] }

        return entries
            .filter { $0.lastPathComponent.hasSuffix(".tar.gz") }
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

    static func restore(archive: URL, into baseURL: URL) throws -> RestoreResult {
        guard FileManager.default.fileExists(atPath: archive.path) else { throw BackupError.noArchive }
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)

        let result = try run("/usr/bin/tar", ["-xzf", archive.path, "-C", baseURL.path])
        guard result.status == 0 else { throw BackupError.tarFailed(result.output) }

        let listing = try run("/usr/bin/tar", ["-tzf", archive.path])
        let tops = Set(listing.output.split(separator: "\n").map { line -> String in
            let parts = line.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: true)
            if parts.count >= 2 { return "\(parts[0])/\(parts[1])" }
            return String(parts.first ?? "")
        }).sorted()
        return RestoreResult(items: tops)
    }

    static func reveal(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - 輔助（SnapshotService 共用）

    static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    static func sizeText(of url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    // 來源目前實際大小（du -sk 加總）。大資料夾要跑一陣子，請在背景呼叫。
    // du 遇無權限項目會回非零 exit code 但仍有輸出，所以不檢查 status。
    static func sourceSizeText(of urls: [URL]) -> String {
        guard !urls.isEmpty else { return "—" }
        guard let result = try? run("/usr/bin/du", ["-sk"] + urls.map(\.path)) else { return "?" }
        var totalKB: Int64 = 0
        for line in result.output.split(separator: "\n") {
            if let kb = Int64(line.split(separator: "\t").first ?? "") { totalKB += kb }
        }
        guard totalKB > 0 else { return "?" }
        return ByteCountFormatter.string(fromByteCount: totalKB * 1024, countStyle: .file)
    }

    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String]) throws
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
