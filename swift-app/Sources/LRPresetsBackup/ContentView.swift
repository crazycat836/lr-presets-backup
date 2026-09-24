import SwiftUI

// 手繪線條風格（設計稿「Mac 備份 Redesign」）：墨色線條＋一個強調色、紙張底、線條抖動。
// 配色、字體、按鈕在 InkStyle.swift；插畫與線條在 Sketch.swift。

// 卡片標題：手寫楷體
struct CardTitle: View {
    let text: String
    var size: CGFloat = 17

    var body: some View {
        Text(text).font(InkFont.hand(size))
    }
}

// 備份項目狀態列（群組或同步項目）：標題 + 來源目前大小 + 最近結果
private struct ItemStatusRow: View {
    @Environment(\.palette) private var p
    let title: String
    let sizeText: String?
    let statusText: String?

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title).font(.system(size: 13))
                if inProgress { InkSpinner() }
            }
            Spacer(minLength: 8)
            Text(sizeText ?? "—")
                .font(InkFont.mono(12))
                .foregroundStyle(p.muted)
                .frame(width: 90, alignment: .trailing)
            Text(statusText ?? "—")
                .font(InkFont.mono(12, weight: .medium))
                .foregroundStyle(statusColor)
                .lineLimit(1)
                .frame(width: 150, alignment: .trailing)
                .animation(.easeOut(duration: 0.3), value: statusText)
        }
        .padding(.vertical, 5)
        .overlay(alignment: .top) { DashedRule() }
    }

    private var inProgress: Bool { statusText?.contains("中…") ?? false }

    private var statusColor: Color {
        guard let statusText else { return p.muted }
        if statusText.contains("失敗") { return p.bad }
        if statusText.contains("完成") { return p.ok }
        if inProgress { return p.accent }
        return p.muted
    }
}

// 清單列之間的虛線分隔
private struct DashedRule: View {
    @Environment(\.palette) private var p

    var body: some View {
        Line().stroke(p.faint, style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { $0.move(to: CGPoint(x: rect.minX, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
        }
    }
}

struct ContentView: View {
    @StateObject private var model = AppModel()
    @Environment(\.colorScheme) private var systemScheme

    private var isDark: Bool { model.prefersDark ?? (systemScheme == .dark) }
    private var p: Palette { isDark ? .dark : .light }

    var body: some View {
        Group {
            if model.showOnboarding {
                onboardingView
            } else {
                mainView
            }
        }
        .overlay { confirmOverlay }
        .frame(width: 640)
        .frame(maxHeight: .infinity)
        .background(p.bg.ignoresSafeArea())
        .foregroundStyle(p.ink)
        .environment(\.palette, p)
        .preferredColorScheme(model.prefersDark.map { $0 ? .dark : .light })
        .tint(p.accent)
        .animation(.easeInOut(duration: 0.4), value: isDark)
        .toolbarBackground(p.bg, for: .windowToolbar)  // 標題列跟紙張同色
    }

    private var themeToggle: some View {
        ThemeToggle(isDark: isDark) { model.setDarkTheme(!isDark) }
    }

    private var mainView: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            tabBar
            // 備份分頁含權限提示時比小筆電螢幕還高，分頁內容可捲動
            ScrollView {
                Group {
                    switch model.selectedTab {
                    case 0: backupTab
                    case 1: restoreTab
                    default: GuideView(model: model)
                    }
                }
                .transition(.opacity.combined(with: .offset(y: 6)))
                .padding(.bottom, 20).padding(.horizontal, 20)
            }
            .frame(minHeight: 480)
            .padding(.horizontal, -20)  // 捲軸貼視窗邊，不壓在卡片上
        }
        .padding(.top, 20).padding(.horizontal, 20)
        .onAppear {
            // 到達主畫面代表已授權或已明確略過，這時才碰資料夾
            model.refresh()
            model.calculateSourceSizes()
        }
    }

    // MARK: - 分頁切換列：手寫字 + 選中時畫出波浪底線

    private var tabBar: some View {
        HStack(spacing: 28) {
            tabButton(0, "備份")
            tabButton(1, "還原")
            tabButton(2, "重灌指南")
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(p.faint).frame(height: 1) }
    }

    private func tabButton(_ tag: Int, _ title: String) -> some View {
        let selected = model.selectedTab == tag
        return Button {
            withAnimation(.easeOut(duration: 0.35)) { model.selectedTab = tag }
        } label: {
            Text(title)
                .font(InkFont.hand(16))
                .foregroundStyle(selected ? p.ink : p.muted)
                .padding(.top, 8).padding(.bottom, 12).padding(.horizontal, 2)
                .overlay(alignment: .bottom) {
                    if selected {
                        SquiggleUnderline().padding(.horizontal, -4).offset(y: 2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 首次啟動：權限關卡（在觸發任何資料夾詢問之前先處理 FDA）

    private var onboardingView: some View {
        VStack(spacing: 26) {
            OnboardingIllustration()

            VStack(spacing: 10) {
                Text("歡迎使用 Mac 備份")
                    .font(InkFont.hand(28))
                Text("開始前，先授權一次「完整磁碟取用權」。\n之後備份照片、桌面、文件時就不會逐資料夾跳出權限詢問。")
                    .font(.system(size: 14))
                    .lineSpacing(5)
                    .foregroundStyle(p.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                Button { model.openFullDiskAccessSettings() } label: {
                    Text("開啟系統設定授權").frame(minWidth: 200)
                }
                .buttonStyle(InkButtonStyle())

                Text("按下後「Mac 備份」會自動出現在清單中，打開開關即可。\n本頁會自動偵測，授權完成後自動進入主畫面。")
                    .font(.system(size: 12))
                    .lineSpacing(4)
                    .foregroundStyle(p.muted)
                    .multilineTextAlignment(.center)

                HStack(spacing: 8) {
                    InkSpinner(size: 14, period: 1.4)
                    Text("等待授權中…")
                        .font(.system(size: 12))
                        .foregroundStyle(p.muted)
                }
            }

            VStack(spacing: 8) {
                Button { model.relaunchApp() } label: {
                    Text("已授權但沒反應？重新啟動 App")
                        .font(.system(size: 12))
                        .underline(color: p.accent)
                }
                .buttonStyle(.plain)

                Button { model.skipFDA() } label: {
                    Text("略過，改用逐資料夾授權（會多次跳出詢問）")
                        .font(.system(size: 12))
                        .underline()
                        .foregroundStyle(p.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 48).padding(.vertical, 40)
        .frame(maxWidth: .infinity, minHeight: 640)
        .overlay(alignment: .topTrailing) { themeToggle.padding(16) }
        .onAppear { model.startPermissionPolling() }
        .onDisappear { model.stopPermissionPolling() }
    }

    // MARK: - 標題列

    private var header: some View {
        HStack(spacing: 14) {
            AppGlyph()
            VStack(alignment: .leading, spacing: 3) {
                Text("Mac 備份")
                    .font(InkFont.hand(24))
                Text("設定檔 tar 快照＋大檔 rsync 增量同步，重灌前一鍵備份")
                    .font(.system(size: 13))
                    .foregroundStyle(p.muted)
            }
            Spacer(minLength: 0)
            themeToggle
        }
    }

    // MARK: - 備份分頁

    private var backupTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !model.hasFullDiskAccess { permissionBanner }
            destinationCard
            backupCard
            logCard
        }
    }

    // 完整磁碟取用權引導：授權一次，之後不再逐資料夾跳詢問
    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("建議先授權「完整磁碟取用權」")
                    .font(InkFont.hand(15))
                    .foregroundStyle(p.warn)
                Text("授權一次後，備份不再逐資料夾跳出權限詢問。按「開啟系統設定」後，「Mac 備份」會自動出現在清單中（設定視窗已開著的話請關閉重開）——打開開關，再重開本 App 生效。若清單仍沒出現，用「在 Finder 顯示 App」把它拖進清單。")
                    .font(.system(size: 12.5))
                    .lineSpacing(3)
                    .foregroundStyle(p.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .trailing, spacing: 6) {
                Button("開啟系統設定") { model.openFullDiskAccessSettings() }
                    .buttonStyle(SmallFilledButtonStyle())
                Button("在 Finder 顯示 App") { model.revealAppInFinder() }
                    .buttonStyle(InkButtonStyle(kind: .small))
                Button("重新檢查") { model.recheckPermissions() }
                    .buttonStyle(InkButtonStyle(kind: .small))
            }
            .fixedSize()
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(p.warnBg))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(p.warn, style: StrokeStyle(lineWidth: 1.6, dash: [6, 4])))
    }

    private var backupDone: Bool { !model.isRunning && model.status == "備份完成" }

    private var heroState: (text: String, color: Color) {
        if model.isRunning { return ("備份中…保持掛載", p.accent) }
        if model.destination == nil { return ("尚未選擇目的地", p.muted) }
        if !model.destinationMounted { return ("未掛載", p.warn) }
        if backupDone { return ("全部完成", p.ok) }
        return ("已掛載", p.ok)
    }

    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                CardTitle(text: "備份目的地")
                Spacer()
                Text(heroState.text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(heroState.color)
            }
            BackupHeroIllustration(running: model.isRunning, done: backupDone,
                                   ledColor: model.isRunning ? p.accent : (model.destinationMounted ? p.ok : p.warn))
            HStack(spacing: 10) {
                Circle()
                    .fill(model.destination == nil ? p.muted : (model.destinationMounted ? p.ok : p.warn))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    if let destination = model.destination {
                        Text(destination.path)
                            .font(InkFont.mono(12.5))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if !model.destinationMounted {
                            Text("目的地未掛載（外接碟未接上或 NAS 未連線）")
                                .font(.system(size: 12))
                                .foregroundStyle(p.warn)
                        }
                    } else {
                        Text("尚未選擇目的地")
                            .font(.system(size: 13))
                            .foregroundStyle(p.muted)
                    }
                }
                Spacer(minLength: 0)
                Button("選擇資料夾") { model.chooseDestination() }
                    .buttonStyle(InkButtonStyle(kind: .small))
                    .disabled(model.isRunning)
                if model.destinationMounted {
                    Button("在 Finder 開啟") { model.revealDestination() }
                        .buttonStyle(InkButtonStyle(kind: .small))
                }
            }
        }
        .inkCard(padding: EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
    }

    private var backupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button { model.confirmFullBackup = true } label: {
                    HStack(spacing: 10) {
                        Text("完整備份（設定＋大檔）")
                        Text("⌘B").font(InkFont.mono(11, weight: .medium)).opacity(0.6)
                    }
                }
                .buttonStyle(InkButtonStyle())
                .keyboardShortcut("b")
                .disabled(model.isRunning || !model.destinationMounted)

                Button("只備份設定檔") { model.runConfigBackup() }
                    .buttonStyle(InkButtonStyle(kind: .outline))
                    .disabled(model.isRunning || !model.destinationMounted)
            }

            if model.lastConfigBackupText != nil || model.lastFullBackupText != nil {
                HStack(spacing: 18) {
                    if let text = model.lastFullBackupText { Text("上次完整備份：\(text)") }
                    if let text = model.lastConfigBackupText { Text("上次設定檔備份：\(text)") }
                }
                .font(.system(size: 12))
                .foregroundStyle(p.muted)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        CardTitle(text: "設定檔快照", size: 13)
                        Text("tar.gz").font(InkFont.mono(11)).foregroundStyle(p.muted)
                    }
                    Spacer()
                    Text("來源大小").frame(width: 90, alignment: .trailing)
                    Text("狀態").frame(width: 150, alignment: .trailing)
                }
                .font(.system(size: 11))
                .foregroundStyle(p.muted)
                .padding(.bottom, 4)

                ItemStatusRow(title: "套件清單（Brewfile / mas）", sizeText: nil,
                              statusText: model.itemStatus["pkg-snapshots"])
                ForEach(BackupPlan.archiveGroups) { group in
                    ItemStatusRow(title: group.title, sizeText: model.itemSize[group.key],
                                  statusText: model.itemStatus[group.key])
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    CardTitle(text: "大檔同步", size: 13)
                    Text("rsync -a").font(InkFont.mono(11)).foregroundStyle(p.muted)
                }
                .padding(.top, 12).padding(.bottom, 4)

                ForEach(BackupPlan.syncItems) { item in
                    ItemStatusRow(title: item.title, sizeText: model.itemSize[item.key],
                                  statusText: model.itemStatus[item.key])
                }
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 10).fill(p.well))
        }
        .inkCard()
    }

    // MARK: - 還原分頁

    private var restoreTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            restoreCard
            logCard
        }
    }

    private var restoreCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                CardTitle(text: "還原設定檔快照")
                Spacer()
                Text("解回原始位置・覆蓋同名檔・不刪其他檔案")
                    .font(.system(size: 12))
                    .foregroundStyle(p.muted)
            }
            if model.archives.isEmpty {
                Text(model.destination == nil ? "先到「備份」分頁選擇目的地。" : "目的地尚無備份快照。")
                    .font(.system(size: 13))
                    .foregroundStyle(p.muted)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(RoundedRectangle(cornerRadius: 10).fill(p.well))
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.archives) { archive in
                            snapshotRow(archive)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 280)
                .fixedSize(horizontal: false, vertical: true)
                .background(RoundedRectangle(cornerRadius: 10).fill(p.well))
            }
            HStack(spacing: 10) {
                Button("還原選取的快照") { model.confirmRestore = true }
                    .buttonStyle(InkButtonStyle())
                    .disabled(model.selectedID == nil || model.isRunning)
                Button("重新整理") { model.refresh() }
                    .buttonStyle(InkButtonStyle(kind: .outline))
            }
            Text("大檔（照片、文件等）還原：直接從目的地 sync/ 資料夾用 Finder 拷回，不經過本 App。完整步驟見「重灌指南」分頁。")
                .font(.system(size: 12))
                .lineSpacing(3)
                .foregroundStyle(p.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .inkCard()
    }

    private func snapshotRow(_ archive: BackupArchive) -> some View {
        let selected = model.selectedID == archive.id
        return Button { model.selectedID = archive.id } label: {
            HStack(spacing: 12) {
                Text(String(archive.name.prefix { $0 != "-" }.prefix(5)).uppercased())
                    .font(InkFont.mono(10, weight: .medium))
                    .foregroundStyle(p.muted)
                    .frame(width: 32, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(archive.name).font(InkFont.mono(12.5, weight: .medium))
                    Text("\(archive.sizeText) · \(archive.modifiedText)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(p.muted)
                }
                Spacer(minLength: 0)
                if selected {
                    InkStroke(d: "M5 12.5 L10 17 L19 6.5", viewBox: CGSize(width: 24, height: 24),
                              color: p.accent, width: 2.6, duration: 0.35, rough: 0)
                        .frame(width: 22, height: 22)
                }
            }
            .padding(.vertical, 9).padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? p.sel : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: selected)
    }

    // MARK: - 紀錄

    private var logLines: [String] {
        model.log.isEmpty ? [] : model.log.components(separatedBy: "\n")
    }

    private func logColor(_ line: String) -> Color {
        if line.contains("失敗") { return p.bad }
        if line.contains("全部完成") || line.hasPrefix("還原完成") { return p.ok }
        if line.hasPrefix("===") { return p.ink }
        return p.muted
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                CardTitle(text: "紀錄")
                Spacer()
                if model.isRunning { InkSpinner() }
                Text(model.status.isEmpty ? "待命" : model.status)
                    .font(.system(size: 12))
                    .foregroundStyle(model.status.contains("失敗") ? p.bad : p.accent)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        if logLines.isEmpty {
                            Text("（尚無操作）").foregroundStyle(p.muted)
                        }
                        ForEach(Array(logLines.enumerated()), id: \.offset) { index, line in
                            Text(line).foregroundStyle(logColor(line)).id(index)
                        }
                    }
                    .font(InkFont.mono(11.5))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10).padding(.horizontal, 12)
                }
                .frame(height: 110)
                .background(RoundedRectangle(cornerRadius: 10).fill(p.well))
                .onChange(of: model.log) { _ in
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(logLines.count - 1, anchor: .bottom) }
                }
            }
        }
        .inkCard(padding: EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
    }

    // MARK: - 確認對話框（紙卡＋墨色實心影子）

    @ViewBuilder private var confirmOverlay: some View {
        if model.confirmFullBackup {
            ConfirmCard(title: "執行完整備份？",
                        message: "大檔同步（照片、桌面、文件…）第一次執行需要很長時間，之後為增量同步會快很多。過程中請保持目的地掛載。",
                        confirmTitle: "開始完整備份", confirmFill: nil,
                        onCancel: { model.confirmFullBackup = false },
                        onConfirm: { model.confirmFullBackup = false; model.runFullBackup() })
        } else if model.confirmRestore {
            ConfirmCard(title: "確定要還原這個快照？",
                        message: "還原會把快照內容解回原始位置，覆蓋同名檔，但不會刪除其他既有檔案。還原 Lightroom 群組前請先關閉 Lightroom Classic。",
                        confirmTitle: "確定還原", confirmFill: p.bad,
                        onCancel: { model.confirmRestore = false },
                        onConfirm: { model.confirmRestore = false; model.restoreSelected() })
        }
    }
}

private struct ConfirmCard: View {
    @Environment(\.palette) private var p
    let title: String
    let message: String
    let confirmTitle: String
    let confirmFill: Color?
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            p.scrim.onTapGesture(perform: onCancel)
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(InkFont.hand(20))
                Text(message)
                    .font(.system(size: 13))
                    .lineSpacing(4)
                    .foregroundStyle(p.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Spacer()
                    Button("取消", action: onCancel)
                        .buttonStyle(InkButtonStyle(kind: .outline))
                        .keyboardShortcut(.cancelAction)
                    Button(confirmTitle, action: onConfirm)
                        .buttonStyle(InkButtonStyle(fill: confirmFill))
                }
                .padding(.top, 6)
            }
            .padding(22)
            .frame(width: 380)
            .background(RoundedRectangle(cornerRadius: 16).fill(p.ink).offset(x: 6, y: 6))
            .background(RoundedRectangle(cornerRadius: 16).fill(p.paper))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(p.ink, lineWidth: 1.8))
        }
        .transition(.opacity)
    }
}

// 權限提示裡的小型實心按鈕
private struct SmallFilledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SmallFilled(configuration: configuration)
    }

    private struct SmallFilled: View {
        @Environment(\.palette) private var p
        let configuration: ButtonStyleConfiguration

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(p.bg)
                .padding(.vertical, 7).padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 9).fill(p.ink))
                .opacity(configuration.isPressed ? 0.8 : 1)
        }
    }
}
