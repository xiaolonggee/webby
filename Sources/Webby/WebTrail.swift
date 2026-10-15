import SwiftUI

/// Original vector mascot. No downloaded art or routing code.
struct WebbySpider: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for side in [-1.0, 1.0] {
                for leg in 0..<4 {
                    let dy = Double(leg) * 4 - 6
                    var path = Path()
                    path.move(to: CGPoint(x: center.x + side * 7, y: center.y + dy / 2))
                    path.addLine(to: CGPoint(x: center.x + side * 12, y: center.y + dy))
                    path.addLine(to: CGPoint(x: center.x + side * 15, y: center.y + dy + 5))
                    context.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                }
            }
            context.fill(Path(ellipseIn: CGRect(x: center.x - 9, y: center.y - 10, width: 18, height: 20)), with: .color(.primary))
            for side in [-1.0, 1.0] {
                let eye = CGRect(x: center.x + side * 4 - 3, y: center.y - 5, width: 6, height: 7)
                context.fill(Path(ellipseIn: eye), with: .color(Color(nsColor: .windowBackgroundColor)))
                context.fill(Path(ellipseIn: eye.insetBy(dx: 2, dy: 2).offsetBy(dx: 0.5, dy: 0.5)), with: .color(.primary))
            }
        }.frame(width: 36, height: 36).accessibilityHidden(true)
    }
}

/// A decorative route cue, never a claim about network traffic or health.
struct WebTrail: View {
    let destination: String
    let listening: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let end = max(24, proxy.size.width - 30)
                ZStack(alignment: .leading) {
                    Path { path in
                        for y in [8.0, 24.0, 40.0] {
                            path.move(to: CGPoint(x: 20, y: 24)); path.addLine(to: CGPoint(x: end, y: y))
                        }
                        for fraction in [0.35, 0.65] {
                            let x = 20 + (end - 20) * fraction
                            path.move(to: CGPoint(x: x, y: 24 - 16 * fraction))
                            path.addQuadCurve(to: CGPoint(x: x, y: 24 + 16 * fraction), control: CGPoint(x: x - 12, y: 24))
                        }
                    }
                        .stroke(.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    Circle().fill(.teal.opacity(0.25)).frame(width: 8, height: 8).offset(x: 16, y: 0)
                    Circle().stroke(listening ? Color.teal : Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: listening ? [] : [2, 2])).frame(width: 12, height: 12).offset(x: end - 6)
                    Image(systemName: "ladybug.fill").font(.system(size: 8)).foregroundStyle(.teal.opacity(0.55)).offset(x: end - 4, y: -16)
                    Image(systemName: "circle").font(.system(size: 7)).foregroundStyle(.secondary.opacity(0.45)).offset(x: end - 3, y: 16)
                    WebbySpider().offset(x: arrived ? end - 18 : 2)
                }.frame(height: 48)
            }.frame(height: 48)
            Text("织网导航 · \(destination)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(12).background(.teal.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
        .allowsHitTesting(false).accessibilityHidden(true)
        .task(id: destination) {
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { arrived = false }
            guard !reduceMotion else { arrived = true; return }
            try? await Task.sleep(for: .milliseconds(30))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.55)) { arrived = true }
        }
        .onChange(of: reduceMotion) { _, _ in
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { arrived = true }
        }
    }
}
struct DiscoveryGlow: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glow = false
    func body(content: Content) -> some View {
        content.background(.teal.opacity(glow ? 0.10 : 0), in: RoundedRectangle(cornerRadius: 8))
            .task {
                guard !reduceMotion else { return }
                glow = true
                try? await Task.sleep(for: .milliseconds(30))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.8)) { glow = false }
            }
    }
}
