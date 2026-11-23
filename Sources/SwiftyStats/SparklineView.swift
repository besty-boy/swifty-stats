import SwiftUI

struct SparklineView: View {
    let values: [Double]
    let minValue: Double
    let maxValue: Double
    let color: Color
    var height: CGFloat = 34

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            guard w > 4, h > 4 else { return }

            // Subtle mid reference line
            var midLine = Path()
            midLine.move(to: CGPoint(x: 0, y: h * 0.5))
            midLine.addLine(to: CGPoint(x: w, y: h * 0.5))
            context.stroke(
                midLine,
                with: .color(Color.primary.opacity(0.06)),
                style: StrokeStyle(lineWidth: 0.75, dash: [2, 3])
            )

            guard values.count >= 2 else {
                if let single = values.first {
                    let y = yCoord(single, height: h)
                    let dot = Path(ellipseIn: CGRect(x: w - 4, y: y - 2, width: 4, height: 4))
                    context.fill(dot, with: .color(color))
                }
                return
            }

            let stepX = w / CGFloat(max(values.count - 1, 1))
            var linePath = Path()
            var fillPath = Path()

            for (index, val) in values.enumerated() {
                let x = CGFloat(index) * stepX
                let y = yCoord(val, height: h)
                let pt = CGPoint(x: x, y: y)
                if index == 0 {
                    linePath.move(to: pt)
                    fillPath.move(to: CGPoint(x: x, y: h))
                    fillPath.addLine(to: pt)
                } else {
                    linePath.addLine(to: pt)
                    fillPath.addLine(to: pt)
                }
            }

            fillPath.addLine(to: CGPoint(x: w, y: h))
            fillPath.closeSubpath()

            context.fill(
                fillPath,
                with: .linearGradient(
                    Gradient(colors: [color.opacity(0.28), color.opacity(0.02)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: h)
                )
            )

            context.stroke(
                linePath,
                with: .color(color),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(height: height)
        .background(Color.primary.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
    }

    private func yCoord(_ value: Double, height: CGFloat) -> CGFloat {
        let range = max(0.001, maxValue - minValue)
        let normalized = min(1.0, max(0.0, (value - minValue) / range))
        let inset: CGFloat = 3.0
        return (height - inset) - CGFloat(normalized) * (height - inset * 2)
    }
}

struct SectionCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
}

struct SegmentedMemoryBar: View {
    let total: UInt64
    let app: UInt64
    let wired: UInt64
    let compressed: UInt64
    let cached: UInt64

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let denom = max(Double(total), 1)
            let appW = w * CGFloat(Double(app) / denom)
            let wiredW = w * CGFloat(Double(wired) / denom)
            let compW = w * CGFloat(Double(compressed) / denom)
            let cacheW = min(max(0, w - appW - wiredW - compW), w * CGFloat(Double(cached) / denom))

            HStack(spacing: 1) {
                if appW > 0.5 {
                    Rectangle().fill(Color.purple).frame(width: appW)
                }
                if wiredW > 0.5 {
                    Rectangle().fill(Color.orange).frame(width: wiredW)
                }
                if compW > 0.5 {
                    Rectangle().fill(Color.cyan).frame(width: compW)
                }
                if cacheW > 0.5 {
                    Rectangle().fill(Color.secondary.opacity(0.35)).frame(width: cacheW)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 7)
        .background(Color.primary.opacity(0.08))
        .clipShape(Capsule())
    }
}
