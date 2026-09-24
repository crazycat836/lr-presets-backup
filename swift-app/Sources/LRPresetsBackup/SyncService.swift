import Foundation

// 大檔資料夾 rsync 增量同步。
// 本機 rsync 是 openrsync（相容 2.6.9），只用保守旗標：-a --exclude。
// 不加 --delete：只增量寫入，絕不刪除目的地既有檔案（安全優先）。
enum SyncService {
    struct SyncResult {
        let key: String
        let elapsedText: String
    }

    static func sync(item: SyncItem, to syncRoot: URL) throws -> SyncResult {
        guard FileManager.default.fileExists(atPath: item.sourceURL.path) else {
            throw BackupError.commandFailed("「\(item.title)」來源不存在：\(item.sourceURL.path)")
        }
        let destDir = syncRoot.appendingPathComponent(item.key)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let start = Date()
        // 來源尾端加 "/"：同步「內容」進 destDir，而不是在 destDir 下再包一層資料夾。
        let result = try BackupService.run("/usr/bin/rsync",
            ["-a", "--exclude=.DS_Store"]
            + item.excludes.map { "--exclude=\($0)" }
            + [item.sourceURL.path + "/", destDir.path])
        guard result.status == 0 else {
            // rsync 輸出可能很長，錯誤訊息只取尾段。
            throw BackupError.commandFailed("rsync 失敗（\(item.key)）：\(String(result.output.suffix(500)))")
        }

        let elapsed = Int(Date().timeIntervalSince(start))
        let elapsedText = elapsed >= 60 ? "\(elapsed / 60) 分 \(elapsed % 60) 秒" : "\(elapsed) 秒"
        return SyncResult(key: item.key, elapsedText: elapsedText)
    }
}
