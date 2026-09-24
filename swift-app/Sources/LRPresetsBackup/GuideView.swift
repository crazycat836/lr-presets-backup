import SwiftUI

// 重灌指南：把還原流程與前置需求放進 App 本身，
// 重灌後從備份碟直接開 App 照著逐步勾選，不用翻 README。
struct GuideStep: Identifiable {
    let id: String
    let phase: Phase
    let title: String
    let detail: String

    enum Phase { case before, after }
}

enum Guide {
    static let steps: [GuideStep] = [
        .init(id: "pre-backup", phase: .before,
              title: "跑一次完整備份並抽查",
              detail: "在「備份」分頁執行完整備份。完成後到目的地確認：snapshots/ 有各群組 tar.gz、sync/ 有 Pictures、Desktop、Documents、Downloads 四個資料夾。"),
        .init(id: "pre-accounts", phase: .before,
              title: "確認帳號能在別台裝置登入",
              detail: "1Password（帳號＋Secret Key＋主密碼）、Apple ID、Adobe、Microsoft。這些若只存在這台 Mac 上，重灌後會被鎖在門外。"),
        .init(id: "login", phase: .after,
              title: "登入 Apple 帳號",
              detail: "iCloud 與 App Store 都要登入，後面裝 App Store 軟體會用到。"),
        .init(id: "open-app", phase: .after,
              title: "從備份碟直接開「Mac 備份.app」",
              detail: "App 就在備份裡：sync/Documents/Claude playground/Personal Project/lr-presets-backup/。開啟後先在「備份」分頁授權完整磁碟取用權（一次授權，之後不再逐資料夾詢問）。"),
        .init(id: "restore-snapshots", phase: .after,
              title: "還原各設定檔快照",
              detail: "在「還原」分頁依序還原 dev-env、claude、hermes、lr-presets。pkg-snapshots 不用在這裡還原，留到 Homebrew 步驟使用。"),
        .init(id: "copy-files", phase: .after,
              title: "大檔用 Finder 拷回",
              detail: "從目的地 sync/ 把 Pictures、Desktop、Documents、Downloads 拷回家目錄對應位置。"),
        .init(id: "homebrew", phase: .after,
              title: "裝 Homebrew 並重裝所有套件",
              detail: "到 brew.sh 安裝（會自動帶入 Command Line Tools）。解開 pkg-snapshots 快照後執行：brew bundle install --file=Brewfile。App Store 項目（mas）需要已登入 Apple 帳號。"),
        .init(id: "reinstall-apps", phase: .after,
              title: "重裝 Claude Code／Claude Desktop／Hermes 本體",
              detail: "快照還原的是設定與資料，程式本體要重新安裝。設定已就位，裝完即用。"),
        .init(id: "tcc", phase: .after,
              title: "重新授權自動化權限",
              detail: "系統設定 → 隱私權與安全性 → 自動化：把 Claude 對 Outlook／Calendar 的控制重新打勾。排程（如 Outlook email sync）第一次執行失敗屬正常。Cowork 首次操作本機 CLI 也會重新跳授權。"),
        .init(id: "subscriptions", phase: .after,
              title: "訂閱制軟體登入",
              detail: "Adobe、Office、1Password、Spotify、Figma 等登入帳號即回復，不需要還原任何檔案。"),
    ]
}

struct GuideView: View {
    @Environment(\.palette) private var p
    @ObservedObject var model: AppModel

    private static let progressLine = "M2 5 C 100 2, 200 8, 300 5 S 500 3, 598 5"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("照著做即可完成重灌前備份與重灌後還原。勾選進度會記住。")
                    .font(.system(size: 13))
                    .foregroundStyle(p.muted)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(model.guideDone.count)").font(InkFont.hand(20)).foregroundStyle(p.accent)
                    Text(" / \(Guide.steps.count)").font(InkFont.hand(14)).foregroundStyle(p.muted)
                }
                Button("重設") { withAnimation { model.resetGuide() } }
                    .buttonStyle(InkButtonStyle(kind: .small))
            }

            // 手繪進度線：底線淡色，完成比例用強調色畫出來
            ZStack {
                Sketch(d: Self.progressLine, viewBox: CGSize(width: 600, height: 10), rough: 0, stretch: true)
                    .stroke(p.faint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                Sketch(d: Self.progressLine, viewBox: CGSize(width: 600, height: 10), rough: 0, stretch: true)
                    .trim(from: 0, to: CGFloat(model.guideDone.count) / CGFloat(Guide.steps.count))
                    .stroke(p.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .animation(.timingCurve(0.3, 0.7, 0.3, 1, duration: 0.6), value: model.guideDone.count)
            }
            .frame(height: 10)

            VStack(alignment: .leading, spacing: 8) {
                phaseSection("重灌前", steps: Guide.steps.filter { $0.phase == .before })
                phaseSection("重灌後", steps: Guide.steps.filter { $0.phase == .after })
                    .padding(.top, 8)
            }
        }
        .inkCard()
    }

    private func phaseSection(_ title: String, steps: [GuideStep]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(InkFont.hand(14))
                .foregroundStyle(p.accent)
            ForEach(steps) { step in
                stepRow(step)
            }
        }
    }

    private func stepRow(_ step: GuideStep) -> some View {
        let done = model.guideDone.contains(step.id)
        return Button { model.toggleGuideStep(step.id) } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    // 沒閉合的手繪圓圈 + 打勾時畫出的勾
                    Sketch(d: "M12 3 C 18 3, 21 7, 21 12 C 21 17, 17 21, 12 21 C 6 21, 3 17, 3 12 C 3 7, 7 2.5, 13 3.5",
                           viewBox: CGSize(width: 24, height: 24), rough: 0)
                        .stroke(done ? p.accent : p.muted, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    Sketch(d: "M7 12.5 L10.5 16 L18 6", viewBox: CGSize(width: 24, height: 24), rough: 0)
                        .trim(from: 0, to: done ? 1 : 0)
                        .stroke(p.accent, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                }
                .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(step.title)
                        .font(.system(size: 14, weight: .semibold))
                        .strikethrough(done, color: p.accent)
                        .foregroundStyle(done ? p.muted : p.ink)
                    Text(step.detail)
                        .font(.system(size: 12.5))
                        .lineSpacing(3)
                        .foregroundStyle(p.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(p.well))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.35), value: done)
    }
}
