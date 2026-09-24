import Foundation

// 套件清單快照：brew bundle dump（formula + cask + mas）與 mas list，
// 打包成 pkg-snapshots-<timestamp>.tar.gz。還原方式是重灌後手動
// `brew bundle install`，所以此群組不提供 App 內還原。
enum SnapshotService {
    private static let brewPath = "/opt/homebrew/bin/brew"
    private static let masPath = "/opt/homebrew/bin/mas"

    static func snapshot(to snapshotsDir: URL) throws -> BackupResult {
        try FileManager.default.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("pkg-snapshots-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        var included: [String] = []
        var skipped: [String] = []

        // Brewfile（brew bundle 會自動涵蓋 mas 裝的 App Store 項目）
        if FileManager.default.fileExists(atPath: brewPath) {
            let brewfile = staging.appendingPathComponent("Brewfile")
            let result = try BackupService.run(brewPath, [
                "bundle", "dump", "--file=\(brewfile.path)", "--force",
            ])
            if result.status == 0, FileManager.default.fileExists(atPath: brewfile.path) {
                included.append("Brewfile")
            } else {
                skipped.append("Brewfile（brew bundle dump 失敗）")
            }
        } else {
            skipped.append("Brewfile（找不到 brew）")
        }

        // mas list 純文字備援快照
        if FileManager.default.fileExists(atPath: masPath) {
            let result = try BackupService.run(masPath, ["list"])
            if result.status == 0, !result.output.isEmpty {
                let listFile = staging.appendingPathComponent("mas-apps.txt")
                try result.output.write(to: listFile, atomically: true, encoding: .utf8)
                included.append("mas-apps.txt")
            } else {
                skipped.append("mas-apps.txt（mas list 失敗）")
            }
        } else {
            skipped.append("mas-apps.txt（找不到 mas）")
        }

        guard !included.isEmpty else { throw BackupError.noSources("套件清單") }

        let archive = snapshotsDir.appendingPathComponent("pkg-snapshots-\(BackupService.timestamp()).tar.gz")
        var arguments = ["-czf", archive.path, "-C", staging.path]
        arguments.append(contentsOf: included)
        let result = try BackupService.run("/usr/bin/tar", arguments)
        guard result.status == 0 else { throw BackupError.tarFailed(result.output) }

        return BackupResult(
            archive: archive,
            fileCount: included.count,
            sizeText: BackupService.sizeText(of: archive),
            included: included,
            skipped: skipped)
    }
}
