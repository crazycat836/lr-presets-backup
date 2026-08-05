import SwiftUI

// 深色 Lightroom 風配色（與 app icon 同一組色）
private enum Theme {
    static let background = Color(red: 0.075, green: 0.086, blue: 0.114) // 視窗底 #131620
    static let card = Color(red: 0.129, green: 0.149, blue: 0.192)       // 卡片底 #212631
    static let innerWell = Color.black.opacity(0.28)                     // 卡片內凹區
    static let accent = Color(red: 0.192, green: 0.659, blue: 1.0)       // LR 藍 #31A8FF
    static let stroke = Color.white.opacity(0.07)
}

private extension View {
    // 卡片外觀：圓角深色底 + 細邊框
    func lrCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.stroke))
    }
}

// 卡片標題列：SF Symbol 藍色圖示 + 標題
private struct CardHeader: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
        }
    }
}

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            backupCard
            restoreCard
            logCard
        }
        .padding(22)
        .frame(width: 600)
        .frame(minHeight: 680)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .onAppear { model.refresh() }
    }

    // MARK: - 標題列

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 48, height: 48)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.stroke))
            VStack(alignment: .leading, spacing: 3) {
                Text("Lightroom 風格檔備份")
                    .font(.system(size: 20, weight: .bold))
                Text("備份／還原 presets、profiles、鏡頭描述檔與最愛（Lightroom Classic）")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 備份

    private var backupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(icon: "arrow.down.circle.fill", title: "備份")
            Text("打包風格檔到 ~/Documents/LR-Presets-Backup")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button { model.backup() } label: {
                    Label("立即備份", systemImage: "arrow.down.doc")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("b")
                .disabled(model.isRunning)

                Button { BackupService.revealBackupFolder() } label: {
                    Label("開啟備份資料夾", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .lrCard()
    }

    // MARK: - 還原

    private var restoreCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(icon: "arrow.counterclockwise.circle.fill", title: "還原")
            if model.archives.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "tray")
                        .foregroundStyle(.secondary)
                    Text("尚無備份，請先執行備份。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                List(selection: $model.selectedID) {
                    ForEach(model.archives) { archive in
                        HStack(spacing: 10) {
                            Image(systemName: "doc.zipper")
                                .foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(archive.name)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                Text("\(archive.sizeText) · \(archive.modifiedText)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                        .tag(archive.id)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(height: 170)
                .background(Theme.innerWell)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 10) {
                    Button { model.confirmRestore = true } label: {
                        Label("還原選取的備份", systemImage: "arrow.up.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(model.selectedID == nil || model.isRunning)

                    Button { model.refresh() } label: {
                        Label("重新整理", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
        }
        .lrCard()
        .confirmationDialog(
            "確定要還原這個備份？",
            isPresented: $model.confirmRestore,
            titleVisibility: .visible
        ) {
            Button("確定還原", role: .destructive) { model.restoreSelected() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("請先完全關閉 Lightroom Classic。還原會覆蓋同名檔，但不會刪除你其他既有的 preset。")
        }
    }

    // MARK: - 紀錄

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardHeader(icon: "text.alignleft", title: "紀錄")
                Spacer()
                if model.isRunning { ProgressView().controlSize(.small) }
                Text(model.status)
                    .font(.system(size: 11))
                    .foregroundStyle(model.status.contains("失敗") ? .red : Theme.accent)
            }
            ScrollView {
                Text(model.log.isEmpty ? "（尚無操作）" : model.log)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(model.log.isEmpty ? Color.secondary : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(height: 150)
            .background(Theme.innerWell)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .lrCard()
    }
}
