import SwiftUI

// 手繪線條（設計稿「Mac 備份 Redesign」）：SVG path 字串 → 取樣成折線 → 依 seed 做小幅位移，
// 每 0.1375 秒換一個 seed 就是線條「抖動」（line boil）。路徑沿用設計稿的 SVG 座標，方便對照。
// macOS 13 沒有 CGPath.flattened，曲線自己取樣。

struct SketchGeometry {
    let subpaths: [[CGPoint]]   // viewBox 座標
    let length: CGFloat

    private static var cache: [String: SketchGeometry] = [:]
    private static let lock = NSLock()

    static func of(_ d: String) -> SketchGeometry {
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[d] { return hit }
        let geometry = SketchGeometry(subpaths: parse(d))
        cache[d] = geometry
        return geometry
    }

    private init(subpaths: [[CGPoint]]) {
        self.subpaths = subpaths
        length = subpaths.reduce(0) { sum, pts in
            zip(pts, pts.dropFirst()).reduce(sum) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        }
    }

    // 沿整條路徑、依長度比例取點（檔案圖示沿傳輸線移動用）
    func point(at fraction: CGFloat) -> CGPoint {
        var remaining = max(0, min(1, fraction)) * length
        for pts in subpaths {
            for (a, b) in zip(pts, pts.dropFirst()) {
                let seg = hypot(b.x - a.x, b.y - a.y)
                if remaining <= seg, seg > 0 {
                    let t = remaining / seg
                    return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                }
                remaining -= seg
            }
        }
        return subpaths.last?.last ?? .zero
    }

    // 只支援設計稿用到的絕對座標指令：M L C S Q Z
    private static func parse(_ d: String) -> [[CGPoint]] {
        var tokens: [String] = []
        var number = ""
        for ch in d {
            if ch.isLetter {
                if !number.isEmpty { tokens.append(number); number = "" }
                tokens.append(String(ch))
            } else if ch == "," || ch == " " || ch == "\n" {
                if !number.isEmpty { tokens.append(number); number = "" }
            } else if ch == "-" && !number.isEmpty && !number.hasSuffix("e") {
                tokens.append(number); number = "-"
            } else {
                number.append(ch)
            }
        }
        if !number.isEmpty { tokens.append(number) }

        var result: [[CGPoint]] = []
        var current: [CGPoint] = []
        var pos = CGPoint.zero, start = CGPoint.zero, lastCtrl: CGPoint?
        var cmd = "M", i = 0
        func num() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i]) ?? 0) }
        func pt() -> CGPoint { let x = num(); return CGPoint(x: x, y: num()) }
        func line(to p: CGPoint) {
            let steps = max(1, Int(hypot(p.x - pos.x, p.y - pos.y) / 3))
            for s in 1...steps {
                let t = CGFloat(s) / CGFloat(steps)
                current.append(CGPoint(x: pos.x + (p.x - pos.x) * t, y: pos.y + (p.y - pos.y) * t))
            }
            pos = p
        }
        func cubic(_ c1: CGPoint, _ c2: CGPoint, _ p: CGPoint) {
            let approx = hypot(c1.x - pos.x, c1.y - pos.y) + hypot(c2.x - c1.x, c2.y - c1.y) + hypot(p.x - c2.x, p.y - c2.y)
            let steps = max(4, Int(approx / 3))
            for s in 1...steps {
                let t = CGFloat(s) / CGFloat(steps), u = 1 - t
                let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, e = t * t * t
                current.append(CGPoint(x: a * pos.x + b * c1.x + c * c2.x + e * p.x,
                                       y: a * pos.y + b * c1.y + c * c2.y + e * p.y))
            }
            pos = p
        }
        while i < tokens.count {
            if let c = tokens[i].first, c.isLetter { cmd = String(c); i += 1 }
            switch cmd {
            case "M":
                if current.count > 1 { result.append(current) }
                pos = pt(); start = pos; current = [pos]; lastCtrl = nil
                cmd = "L"  // M 後續的座標視為 L
            case "L":
                line(to: pt()); lastCtrl = nil
            case "C":
                let c1 = pt(), c2 = pt(), p = pt()
                cubic(c1, c2, p); lastCtrl = c2
            case "S":
                let c1 = lastCtrl.map { CGPoint(x: 2 * pos.x - $0.x, y: 2 * pos.y - $0.y) } ?? pos
                let c2 = pt(), p = pt()
                cubic(c1, c2, p); lastCtrl = c2
            case "Q":
                let q = pt(), p = pt()
                let c1 = CGPoint(x: pos.x + 2 / 3 * (q.x - pos.x), y: pos.y + 2 / 3 * (q.y - pos.y))
                let c2 = CGPoint(x: p.x + 2 / 3 * (q.x - p.x), y: p.y + 2 / 3 * (q.y - p.y))
                cubic(c1, c2, p); lastCtrl = nil
            case "Z", "z":
                line(to: start); lastCtrl = nil
            default:
                i += 1
            }
        }
        if current.count > 1 { result.append(current) }
        return result
    }
}

struct Sketch: Shape {
    let d: String
    let viewBox: CGSize
    var rough: CGFloat = 2.5
    var seed: Int = 0
    var stretch = false  // true = preserveAspectRatio="none"（底線、進度線）

    func path(in rect: CGRect) -> Path {
        let geometry = SketchGeometry.of(d)
        let sx = rect.width / viewBox.width
        let sy = stretch ? rect.height / viewBox.height : sx
        let s = CGFloat(seed) * 1.37
        var path = Path()
        for pts in geometry.subpaths {
            for (index, p) in pts.enumerated() {
                // 平滑的偽雜訊位移，量級同設計稿 feDisplacementMap（±rough/2）
                let dx = rough / 2 * (sin(p.x * 0.19 + s * 5.1) * cos(p.y * 0.13 + s * 2.7) * 0.7 + sin((p.x + p.y) * 0.07 + s) * 0.3)
                let dy = rough / 2 * (cos(p.x * 0.11 + s * 3.3) * sin(p.y * 0.21 + s * 4.3) * 0.7 + cos((p.x - p.y) * 0.08 + s) * 0.3)
                let q = CGPoint(x: rect.minX + (p.x + dx) * sx, y: rect.minY + (p.y + dy) * sy)
                if index == 0 { path.move(to: q) } else { path.addLine(to: q) }
            }
        }
        return path
    }
}

// 線條抖動的時鐘：減少動態效果時固定 seed
struct Boiling<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder let content: (Int) -> Content

    var body: some View {
        if reduceMotion {
            content(0)
        } else {
            TimelineView(.periodic(from: .now, by: 0.1375)) { context in
                content(Int(context.date.timeIntervalSinceReferenceDate / 0.1375) % 4)
            }
        }
    }
}

// 一筆畫描邊：出現時從頭畫到尾（stroke-dashoffset 1 → 0）
struct InkStroke: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let d: String
    let viewBox: CGSize
    var color: Color
    var width: CGFloat = 2.2
    var duration: Double = 0.8
    var delay: Double = 0
    var seed = 0
    var rough: CGFloat = 2.5
    var stretch = false
    private let progress = State(initialValue: CGFloat(0))

    var body: some View {
        Sketch(d: d, viewBox: viewBox, rough: rough, seed: seed, stretch: stretch)
            .trim(from: 0, to: reduceMotion ? 1 : progress.wrappedValue)
            .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            .onAppear {
                withAnimation(.easeInOut(duration: duration).delay(delay)) { progress.wrappedValue = 1 }
            }
    }
}

// 延遲淡入（LED、強調點）
struct FadeIn: ViewModifier {
    let delay: Double
    private let shown = State(initialValue: false)

    func body(content: Content) -> some View {
        content
            .opacity(shown.wrappedValue ? 1 : 0)
            .onAppear { withAnimation(.easeOut(duration: 0.3).delay(delay)) { shown.wrappedValue = true } }
    }
}

// 完成時的小星星：縮放彈出並帶一點旋轉
struct PopIn: ViewModifier {
    let delay: Double
    private let shown = State(initialValue: false)

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown.wrappedValue ? 1 : 0.01)
            .rotationEffect(.degrees(shown.wrappedValue ? 0 : -30))
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.45).delay(delay)) { shown.wrappedValue = true }
            }
    }
}

// MARK: - 插畫

// 備份目的地卡片的主插畫：筆電 → 傳輸線 → 備份碟。備份中線上有檔案流動，完成時冒出星星。
struct BackupHeroIllustration: View {
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let running: Bool
    let done: Bool
    let ledColor: Color

    private static let box = CGSize(width: 560, height: 120)
    static let cable = "M170 95 C 225 95, 232 46, 290 54 S 372 108, 430 76 S 462 64, 472 70"
    private static let strokes: [(d: String, width: CGFloat, duration: Double, delay: Double)] = [
        ("M62 18 Q58 18 58 22 L58 78 Q58 82 62 82 L148 82 Q152 82 152 78 L152 22 Q152 18 148 18 Z", 2.2, 0.8, 0.1),
        ("M40 90 L170 90 L160 100 L50 100 Z", 2.2, 0.5, 0.8),
        ("M82 44 C 88 40, 92 40, 96 44 M114 44 C 120 40, 124 40, 128 44 M92 60 C 100 68, 112 68, 120 60", 2.2, 0.6, 1.2),
        (cable, 2.2, 1.0, 1.5),
        ("M480 42 L540 42 Q550 42 550 52 L550 92 Q550 102 540 102 L480 102 Q470 102 470 92 L470 52 Q470 42 480 42 Z", 2.2, 0.8, 2.3),
        ("M484 58 L522 58 M484 68 L508 68", 1.8, 0.4, 2.9),
    ]
    private static let file = "M-6 -8 L3 -8 L7 -4 L7 8 L-6 8 Z"
    private static let sparkles: [(d: String, delay: Double)] = [
        ("M456 22 L456 34 M450 28 L462 28", 0),
        ("M560 30 L560 44 M553 37 L567 37", 0.12),
        ("M548 8 C 550 14, 552 16, 558 18 C 552 20, 550 22, 548 28 C 546 22, 544 20, 538 18 C 544 16, 546 14, 548 8 Z", 0.24),
        ("M500 20 C 504 16, 512 16, 516 20", 0.3),
    ]

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / Self.box.width
            ZStack(alignment: .topLeading) {
                Boiling { seed in
                    ZStack {
                        ForEach(0..<Self.strokes.count, id: \.self) { i in
                            let st = Self.strokes[i]
                            InkStroke(d: st.d, viewBox: Self.box, color: p.ink, width: st.width,
                                      duration: st.duration, delay: st.delay, seed: seed)
                        }
                    }
                }
                Circle().fill(ledColor)
                    .frame(width: 8 * s, height: 8 * s)
                    .position(x: 536 * s, y: 90 * s)
                    .modifier(FadeIn(delay: 3.1))
                if running { flow(scale: s) }
                if done {
                    ZStack {
                        ForEach(0..<Self.sparkles.count, id: \.self) { i in
                            Sketch(d: Self.sparkles[i].d, viewBox: Self.box, rough: 0)
                                .stroke(p.accent, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                                .modifier(PopIn(delay: Self.sparkles[i].delay))
                        }
                    }
                }
            }
        }
        // 視窗依內容定尺寸時不會提供建議大小，aspectRatio 會塌成 0；卡片內寬固定 564，直接給高度
        .frame(maxWidth: .infinity)
        .frame(height: 564 * Self.box.height / Self.box.width)
    }

    // 傳輸線上流動的虛線 + 三個沿線移動的檔案
    private func flow(scale s: CGFloat) -> some View {
        let geometry = SketchGeometry.of(Self.cable)
        let length = geometry.length * s
        return TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .topLeading) {
                Sketch(d: Self.cable, viewBox: Self.box, rough: 0)
                    .stroke(p.accent, style: StrokeStyle(lineWidth: 2.6, lineCap: .round,
                                                         dash: [length * 0.015, length * 0.035],
                                                         dashPhase: -CGFloat(t.truncatingRemainder(dividingBy: 3) / 3) * length))
                ForEach(0..<3, id: \.self) { i in
                    let fraction = CGFloat(((t + Double(i) * 0.8) / 2.4).truncatingRemainder(dividingBy: 1))
                    let at = geometry.point(at: fraction)
                    ZStack {
                        Sketch(d: Self.file, viewBox: CGSize(width: 14, height: 16), rough: 0).offset(x: 7, y: 8)
                            .fill(p.paper)
                        Sketch(d: Self.file, viewBox: CGSize(width: 14, height: 16), rough: 0).offset(x: 7, y: 8)
                            .stroke(p.ink, style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
                    }
                    .frame(width: 14, height: 16)
                    .scaleEffect(s)
                    .position(x: at.x * s, y: at.y * s)
                }
            }
        }
    }
}

// 首次授權頁插畫：一筆畫線條繞出鎖頭，再牽到強調色小點
struct OnboardingIllustration: View {
    @Environment(\.palette) private var p
    private static let box = CGSize(width: 260, height: 130)
    private static let strokes: [(d: String, duration: Double, delay: Double)] = [
        ("M10 110 C 40 112, 60 100, 70 84 C 78 70, 70 58, 58 62 C 46 66, 50 84, 66 88 C 84 92, 96 80, 104 70", 1.1, 0.1),
        ("M104 70 C 104 48, 120 34, 140 34 C 160 34, 176 48, 176 70 C 176 92, 160 106, 140 106 C 120 106, 104 92, 104 70 Z", 1.0, 1.0),
        ("M140 58 C 146 58, 148 66, 142 70 L 146 86 L 134 86 L 138 70 C 132 66, 134 58, 140 58 Z", 0.7, 1.9),
        ("M176 70 C 196 70, 204 60, 214 52 C 224 44, 236 46, 250 44", 0.7, 2.5),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Boiling { seed in
                ZStack {
                    ForEach(0..<Self.strokes.count, id: \.self) { i in
                        let st = Self.strokes[i]
                        InkStroke(d: st.d, viewBox: Self.box, color: p.ink, duration: st.duration, delay: st.delay, seed: seed)
                    }
                }
            }
            Circle().fill(p.accent)
                .frame(width: 8, height: 8)
                .position(x: 250, y: 44)
                .modifier(FadeIn(delay: 3.1))
        }
        .frame(width: Self.box.width, height: Self.box.height)
    }
}

// 標題列 App 圖示：手繪硬碟 + 強調色指示燈
struct AppGlyph: View {
    @Environment(\.palette) private var p

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(p.paper)
            RoundedRectangle(cornerRadius: 14).strokeBorder(p.ink, lineWidth: 1.6)
            ZStack(alignment: .topLeading) {
                Boiling { seed in
                    Sketch(d: "M5 10 Q5 7 8 7 L22 7 Q25 7 25 10 L25 20 Q25 23 22 23 L8 23 Q5 23 5 20 Z M9 12 L17 12",
                           viewBox: CGSize(width: 30, height: 30), rough: 1.2, seed: seed)
                        .stroke(p.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                Circle().fill(p.accent).frame(width: 4, height: 4).position(x: 20.5, y: 18.5)
            }
            .frame(width: 30, height: 30)
        }
        .frame(width: 52, height: 52)
    }
}

// 分頁底下的手繪波浪底線
struct SquiggleUnderline: View {
    @Environment(\.palette) private var p

    var body: some View {
        InkStroke(d: "M2 6 C 20 2, 38 9, 55 5 S 85 3, 98 6", viewBox: CGSize(width: 100, height: 10),
                  color: p.accent, width: 2.6, duration: 0.45, rough: 0, stretch: true)
            .frame(height: 10)
    }
}

// 旋轉中的手繪弧線（取代 ProgressView）
struct InkSpinner: View {
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var size: CGFloat = 12
    var period: Double = 1

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(p.accent, style: StrokeStyle(lineWidth: size / 7, lineCap: .round))
                .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: period) / period * 360))
                .frame(width: size - 2, height: size - 2)
        }
        .frame(width: size, height: size)
    }
}
