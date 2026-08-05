import SwiftUI

// UI 狀態與操作協調。tar 工作在背景執行，結果回主執行緒更新畫面。
@MainActor
final class AppModel: ObservableObject {
    @Published var archives: [BackupArchive] = []
    @Published var selectedID: BackupArchive.ID?
    @Published var log: String = ""
    @Published var isRunning = false
    @Published var status = ""
    @Published var confirmRestore = false

    var selectedArchive: BackupArchive? {
        archives.first { $0.id == selectedID }
    }

    func refresh() {
        archives = BackupService.listArchives()
        if selectedID == nil || !archives.contains(where: { $0.id == selectedID }) {
            selectedID = archives.first?.id
        }
    }

    func backup() {
        guard !isRunning else { return }
        isRunning = true
        status = "備份中…"
        Task {
            do {
                let result = try await Task.detached { try BackupService.backup() }.value
                appendLog("備份完成：\(result.archive.lastPathComponent)")
                appendLog("  大小 \(result.sizeText)，共 \(result.fileCount) 個檔案")
                if !result.skipped.isEmpty {
                    appendLog("  略過（不存在）：\(result.skipped.joined(separator: "、"))")
                }
                status = "備份完成"
                refresh()
                selectedID = archives.first?.id
            } catch {
                appendLog("備份失敗：\(error.localizedDescription)")
                status = "備份失敗"
            }
            isRunning = false
        }
    }

    func restoreSelected() {
        guard !isRunning, let archive = selectedArchive else { return }
        isRunning = true
        status = "還原中…"
        Task {
            do {
                let archiveURL = archive.url
                let result = try await Task.detached { try BackupService.restore(archiveURL) }.value
                appendLog("還原完成：\(archive.name)")
                appendLog("  已還原：\(result.items.joined(separator: "、"))")
                appendLog("  重開 Lightroom Classic 即可看到 presets／profiles／最愛。")
                status = "還原完成"
            } catch {
                appendLog("還原失敗：\(error.localizedDescription)")
                status = "還原失敗"
            }
            isRunning = false
        }
    }

    private func appendLog(_ line: String) {
        log += (log.isEmpty ? "" : "\n") + line
    }
}
