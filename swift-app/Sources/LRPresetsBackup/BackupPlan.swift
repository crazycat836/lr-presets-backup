import Foundation

// tar.gz 快照類備份群組：一個 base 目錄 + 白名單 items。
struct ArchiveGroup: Identifiable {
    let key: String        // 檔名 prefix 與識別
    let title: String      // UI 顯示名稱
    let baseURL: URL       // tar -C 的 base；還原也解回這裡
    let items: [String]    // 相對 base 的白名單路徑（缺的自動略過）
    let excludes: [String]

    var id: String { key }
}

// rsync 增量同步類項目（大檔資料夾）。
struct SyncItem: Identifiable {
    let key: String        // 目的地 sync/ 下的子資料夾名
    let title: String
    let sourceURL: URL
    var excludes: [String] = []  // 相對來源的 rsync --exclude 樣式

    var id: String { key }
}

// 備份計畫本身：內建清單即計畫，對應重灌備份盤點結果（2026-08）。
enum BackupPlan {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    // pkg-snapshots（Brewfile / mas 清單）由 SnapshotService 動態產生，不在此表。
    static let archiveGroups: [ArchiveGroup] = [
        ArchiveGroup(
            key: "lr-presets",
            title: "Lightroom 風格檔",
            baseURL: home.appendingPathComponent("Library/Application Support/Adobe"),
            // 明確不含：CameraRaw/ModelZoo(AI 模型)、Logs、GPU cache、app 偏好 plist。
            items: [
                "Lightroom",
                "CameraRaw/Settings",
                "CameraRaw/Defaults",
                "CameraRaw/ImportedSettings",
                "CameraRaw/CameraProfiles",
                "CameraRaw/LensProfiles",
                "CameraRaw/Curves",
                "CameraRaw/LocalCorrections",
                "CameraRaw/LensProfileDefaults",
            ],
            excludes: [".DS_Store", "*.log"]),
        ArchiveGroup(
            key: "dev-env",
            title: "開發環境（SSH 金鑰、shell 設定）",
            baseURL: home,
            items: [
                ".ssh",
                ".gitconfig",
                ".zshrc",
                ".zprofile",
                ".p10k.zsh",
                ".oh-my-zsh/custom",
            ],
            excludes: [".DS_Store"]),
        ArchiveGroup(
            key: "claude",
            title: "Claude 設定與對話紀錄",
            baseURL: home,
            items: [
                ".claude/projects",
                ".claude/settings.json",
                ".claude/CLAUDE.md",
                ".claude/skills",
                ".claude/commands",
                ".claude/plugins",
                ".claude/statusline-command.sh",
                ".claude.json",
                "Library/Application Support/Claude/claude_desktop_config.json",
                "Library/Application Support/Claude/Claude Extensions Settings",
            ],
            excludes: [".DS_Store", "*.log", ".claude/plugins/cache"]),
        ArchiveGroup(
            key: "hermes",
            title: "Hermes 設定與記憶",
            baseURL: home.appendingPathComponent(".hermes"),
            items: [
                "config.yaml",
                "auth.json",
                "google_token.json",
                "google_client_secret.json",
                "memories",
                "mcp-tokens",
                "skills",
            ],
            excludes: [".DS_Store", "*.log"]),
    ]

    static let syncItems: [SyncItem] = [
        SyncItem(key: "Pictures", title: "照片（Lightroom catalog + RAW）",
                 sourceURL: home.appendingPathComponent("Pictures"),
                 // 照片圖庫走 iCloud 照片，不重複備份；Lightroom catalog 與 RAW 只存在本機，照常同步
                 excludes: ["/Photos Library.photoslibrary"]),
        SyncItem(key: "Desktop", title: "桌面",
                 sourceURL: home.appendingPathComponent("Desktop")),
        SyncItem(key: "Documents", title: "文件",
                 sourceURL: home.appendingPathComponent("Documents")),
        SyncItem(key: "Downloads", title: "下載",
                 sourceURL: home.appendingPathComponent("Downloads")),
    ]

    // 由備份檔名（<key>-<timestamp>.tar.gz）對回群組；pkg-snapshots 等無對應者回 nil。
    static func group(forArchiveName name: String) -> ArchiveGroup? {
        archiveGroups.first { name.hasPrefix("\($0.key)-") }
    }
}
