import AppKit
import SwiftUI

// UI 狀態與操作協調。tar／rsync 工作在背景執行，結果回主執行緒更新畫面。
// 注意：本專案無 Xcode（僅 CLT），@State 等 macro 不可用，所有狀態集中在此。
@MainActor
final class AppModel: ObservableObject {
    private static let destinationKey = "backupDestinationPath"
    private static let guideDoneKey = "guideDoneSteps"
    private static let darkThemeKey = "prefersDarkTheme"

    @Published var destination: URL?
    @Published var selectedTab = 0
    @Published var hasFullDiskAccess = AppModel.checkFullDiskAccess()
    // 略過只對本次啟動有效（不持久化）：FDA 對備份工具近乎必要，下次啟動仍會再引導
    @Published var fdaSkipped = false
    @Published var guideDone: Set<String> = Set(UserDefaults.standard.stringArray(forKey: guideDoneKey) ?? [])
    @Published var lastConfigBackupText: String?
    @Published var lastFullBackupText: String?
    // nil = 跟隨系統外觀；按過右上角切換後記住選擇
    @Published var prefersDark: Bool? = UserDefaults.standard.object(forKey: darkThemeKey) as? Bool
    private var permissionTimer: Timer?

    // 首次啟動先過權限關卡，通過（或明確略過）前不執行任何會觸發資料夾權限詢問的動作
    var showOnboarding: Bool { !hasFullDiskAccess && !fdaSkipped }
    @Published var archives: [BackupArchive] = []
    @Published var selectedID: BackupArchive.ID?
    @Published var itemStatus: [String: String] = [:]  // group/sync key -> 最近結果
    @Published var itemSize: [String: String] = [:]    // group/sync key -> 來源目前大小
    private var sizesStarted = false
    @Published var log: String = ""
    @Published var isRunning = false
    @Published var status = ""
    @Published var confirmRestore = false
    @Published var confirmFullBackup = false

    init() {
        if let path = UserDefaults.standard.string(forKey: Self.destinationKey) {
            destination = URL(fileURLWithPath: path)
        }
        lastConfigBackupText = Self.loadBackupDate("lastBackup.config")
        lastFullBackupText = Self.loadBackupDate("lastBackup.full")
    }

    // MARK: - 權限（完整磁碟取用權）

    // 授權一次 FDA 後，備份不再逐資料夾跳 TCC 詢問。
    // 偵測 = 探測：嘗試讀取多個受 FDA 保護的路徑。讀得到任一個代表已授權；
    // 讀不到時，這個「嘗試」本身會讓 tccd 把本 App 自動登記進系統設定的
    // 完整磁碟取用權清單（開關預設關閉），使用者不必手動按「＋」加入。
    static func checkFullDiskAccess() -> Bool {
        let home = NSHomeDirectory()
        let probes = [
            home + "/Library/Application Support/com.apple.TCC/TCC.db",
            home + "/Library/Safari/CloudTabs.db",
            home + "/Library/Safari/Bookmarks.plist",
            "/Library/Application Support/com.apple.TCC/TCC.db",
        ]
        var accessible = false
        for path in probes {
            if let handle = FileHandle(forReadingAtPath: path) {
                try? handle.close()
                accessible = true
            }
        }
        // 目錄列舉也會觸發 TCC 檢查，多一種探測方式保險
        _ = try? FileManager.default.contentsOfDirectory(atPath: home + "/Library/Safari")
        return accessible
    }

    func recheckPermissions() {
        let wasGranted = hasFullDiskAccess
        hasFullDiskAccess = Self.checkFullDiskAccess()
        if !wasGranted && hasFullDiskAccess {
            // 剛取得授權：停止輪詢，開始載入主畫面資料
            stopPermissionPolling()
            refresh()
            calculateSourceSizes()
        }
    }

    // 歡迎頁顯示期間每 2 秒自動偵測，授權完成自動進入主畫面
    func startPermissionPolling() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recheckPermissions() }
        }
    }

    func stopPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    // 明確選擇不授權 FDA，改走逐資料夾詢問（僅本次啟動有效）
    func skipFDA() {
        fdaSkipped = true
        stopPermissionPolling()
        refresh()
        calculateSourceSizes()
    }

    // FDA 授權後若行程已在執行，權限可能要重啟才生效——提供一鍵重啟
    func relaunchApp() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }

    func openFullDiskAccessSettings() {
        // 先探測觸發 tccd 登記，再開設定頁，清單裡就會出現本 App
        recheckPermissions()
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    // 在 Finder 顯示 App 本身，方便拖進系統設定的完整磁碟取用權清單。
    func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func setDarkTheme(_ dark: Bool) {
        prefersDark = dark
        UserDefaults.standard.set(dark, forKey: Self.darkThemeKey)
    }

    // MARK: - 重灌指南勾選

    func toggleGuideStep(_ id: String) {
        if guideDone.contains(id) { guideDone.remove(id) } else { guideDone.insert(id) }
        UserDefaults.standard.set(Array(guideDone), forKey: Self.guideDoneKey)
    }

    func resetGuide() {
        guideDone = []
        UserDefaults.standard.removeObject(forKey: Self.guideDoneKey)
    }

    // MARK: - 目的地

    var destinationMounted: Bool {
        guard let destination else { return false }
        return FileManager.default.fileExists(atPath: destination.path)
    }

    var snapshotsDir: URL? { destination?.appendingPathComponent("snapshots") }
    var syncDir: URL? { destination?.appendingPathComponent("sync") }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "選為備份目的地"
        panel.message = "選擇外接硬碟或 NAS 上的備份資料夾"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        destination = url
        UserDefaults.standard.set(url.path, forKey: Self.destinationKey)
        appendLog("備份目的地：\(url.path)")
        refresh()
    }

    var selectedArchive: BackupArchive? {
        archives.first { $0.id == selectedID }
    }

    func refresh() {
        guard let snapshotsDir else {
            archives = []
            return
        }
        archives = BackupService.listArchives(in: snapshotsDir)
        if selectedID == nil || !archives.contains(where: { $0.id == selectedID }) {
            selectedID = archives.first?.id
        }
    }

    // 啟動時背景計算各項目來源目前大小（du），逐項更新，大資料夾較晚出現。
    func calculateSourceSizes() {
        guard !sizesStarted else { return }
        sizesStarted = true
        for group in BackupPlan.archiveGroups { itemSize[group.key] = "計算中…" }
        for item in BackupPlan.syncItems { itemSize[item.key] = "計算中…" }
        Task {
            for group in BackupPlan.archiveGroups {
                let urls = group.items
                    .map { group.baseURL.appendingPathComponent($0) }
                    .filter { FileManager.default.fileExists(atPath: $0.path) }
                itemSize[group.key] = await Task.detached { BackupService.sourceSizeText(of: urls) }.value
            }
            for item in BackupPlan.syncItems {
                let url = item.sourceURL
                itemSize[item.key] = await Task.detached { BackupService.sourceSizeText(of: [url]) }.value
            }
        }
    }

    // MARK: - 備份

    // 只備份設定檔類（套件清單 + 各 tar 群組），跑得快。
    func runConfigBackup() {
        runBackup(includeSync: false)
    }

    // 完整備份：設定檔 + 大檔 rsync（Pictures/Desktop/Documents…，第一次會跑很久）。
    func runFullBackup() {
        runBackup(includeSync: true)
    }

    private func runBackup(includeSync: Bool) {
        guard !isRunning, let snapshotsDir, let syncDir, destinationMounted else { return }
        isRunning = true
        status = includeSync ? "完整備份中…" : "設定檔備份中…"
        appendLog(includeSync ? "=== 完整備份開始 ===" : "=== 設定檔備份開始 ===")

        Task {
            var failures: [String] = []

            // 1. 套件清單快照
            setStatus("pkg-snapshots", "備份中…")
            do {
                let result = try await Task.detached { try SnapshotService.snapshot(to: snapshotsDir) }.value
                setStatus("pkg-snapshots", "完成 \(result.sizeText)")
                appendLog("套件清單：\(result.archive.lastPathComponent)（\(result.included.joined(separator: "、"))）")
                for skip in result.skipped { appendLog("  略過：\(skip)") }
            } catch {
                failures.append("套件清單")
                setStatus("pkg-snapshots", "失敗")
                appendLog("套件清單失敗：\(error.localizedDescription)")
            }

            // 2. 各 tar 群組
            for group in BackupPlan.archiveGroups {
                setStatus(group.key, "備份中…")
                do {
                    let result = try await Task.detached { try BackupService.backup(group: group, to: snapshotsDir) }.value
                    setStatus(group.key, "完成 \(result.sizeText)")
                    appendLog("\(group.title)：\(result.archive.lastPathComponent)（\(result.fileCount) 個檔案，\(result.sizeText)）")
                    if !result.skipped.isEmpty {
                        appendLog("  略過（不存在）：\(result.skipped.joined(separator: "、"))")
                    }
                } catch {
                    failures.append(group.title)
                    setStatus(group.key, "失敗")
                    appendLog("\(group.title)失敗：\(error.localizedDescription)")
                }
            }

            // 3. 大檔 rsync（僅完整備份）
            if includeSync {
                for item in BackupPlan.syncItems {
                    setStatus(item.key, "同步中…（大資料夾第一次會很久）")
                    status = "同步 \(item.title)…"
                    do {
                        let result = try await Task.detached { try SyncService.sync(item: item, to: syncDir) }.value
                        setStatus(item.key, "完成（\(result.elapsedText)）")
                        appendLog("\(item.title)：同步完成，耗時 \(result.elapsedText)")
                    } catch {
                        failures.append(item.title)
                        setStatus(item.key, "失敗")
                        appendLog("\(item.title)失敗：\(error.localizedDescription)")
                    }
                }
            }

            if failures.isEmpty {
                status = "備份完成"
                appendLog("=== 全部完成 ===")
            } else {
                status = "部分失敗"
                appendLog("=== 完成，但以下項目失敗：\(failures.joined(separator: "、")) ===")
            }
            recordBackupDate(full: includeSync)
            refresh()
            isRunning = false
        }
    }

    // MARK: - 還原

    func restoreSelected() {
        guard !isRunning, let archive = selectedArchive else { return }
        guard let group = BackupPlan.group(forArchiveName: archive.name) else {
            appendLog("「\(archive.name)」不支援 App 內還原（套件清單請解開後手動 brew bundle install）。")
            return
        }
        isRunning = true
        status = "還原中…"
        Task {
            do {
                let archiveURL = archive.url
                let baseURL = group.baseURL
                let result = try await Task.detached {
                    try BackupService.restore(archive: archiveURL, into: baseURL)
                }.value
                appendLog("還原完成：\(archive.name) → \(group.baseURL.path)")
                appendLog("  已還原：\(result.items.joined(separator: "、"))")
                status = "還原完成"
            } catch {
                appendLog("還原失敗：\(error.localizedDescription)")
                status = "還原失敗"
            }
            isRunning = false
        }
    }

    // MARK: - 輔助

    func revealDestination() {
        guard let destination else { return }
        BackupService.reveal(destination)
    }

    private func setStatus(_ key: String, _ text: String) {
        itemStatus[key] = text
    }

    private static let backupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static func loadBackupDate(_ key: String) -> String? {
        guard let date = UserDefaults.standard.object(forKey: key) as? Date else { return nil }
        return backupDateFormatter.string(from: date)
    }

    private func recordBackupDate(full: Bool) {
        let key = full ? "lastBackup.full" : "lastBackup.config"
        UserDefaults.standard.set(Date(), forKey: key)
        let text = Self.backupDateFormatter.string(from: Date())
        if full { lastFullBackupText = text } else { lastConfigBackupText = text }
    }

    private func appendLog(_ line: String) {
        log += (log.isEmpty ? "" : "\n") + line
    }
}
