import SwiftUI
import TaskyfyCore

// MARK: - RingGauge

public struct RingGauge: View {
    public let progress: Double
    public let primaryText: String
    public let secondaryText: String
    public let color: Color
    public var size: CGFloat = 56
    public var lineWidth: CGFloat = 5.0

    public init(
        progress: Double,
        primaryText: String,
        secondaryText: String = "",
        color: Color,
        size: CGFloat = 56,
        lineWidth: CGFloat = 5.0
    ) {
        self.progress = min(max(progress, 0), 1)
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.color = color
        self.size = size
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.10), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0.5) {
                Text(primaryText)
                    .font(.system(size: size * 0.21, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if !secondaryText.isEmpty {
                    Text(secondaryText)
                        .font(.system(size: max(8, size * 0.13), weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Interactive AreaChart

public struct AreaChart: View {
    public let points: [TimePoint]
    public let color: Color
    public var fixedMax: Double? = nil
    public var height: CGFloat = 56
    public var valueFormatter: ((Double) -> String)? = nil

    @State private var hoverRatio: CGFloat?

    public init(
        points: [TimePoint],
        color: Color,
        fixedMax: Double? = nil,
        height: CGFloat = 56,
        valueFormatter: ((Double) -> String)? = nil
    ) {
        self.points = points
        self.color = color
        self.fixedMax = fixedMax
        self.height = height
        self.valueFormatter = valueFormatter
    }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let maxVal = max(fixedMax ?? (points.map(\.value).max() ?? 1.0), 0.001)

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    guard points.count >= 2 else { return }
                    let count = points.count
                    let stepX = size.width / CGFloat(max(1, count - 1))

                    var linePath = Path()
                    var fillPath = Path()

                    for (idx, pt) in points.enumerated() {
                        let x = CGFloat(idx) * stepX
                        let normalized = min(max(pt.value / maxVal, 0), 1)
                        let y = size.height - CGFloat(normalized) * (size.height - 4) - 2

                        if idx == 0 {
                            linePath.move(to: CGPoint(x: x, y: y))
                            fillPath.move(to: CGPoint(x: x, y: size.height))
                            fillPath.addLine(to: CGPoint(x: x, y: y))
                        } else {
                            linePath.addLine(to: CGPoint(x: x, y: y))
                            fillPath.addLine(to: CGPoint(x: x, y: y))
                        }
                    }

                    fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
                    fillPath.closeSubpath()

                    context.fill(
                        fillPath,
                        with: .linearGradient(
                            Gradient(colors: [color.opacity(0.14), color.opacity(0.01)]),
                            startPoint: CGPoint(x: 0, y: 0),
                            endPoint: CGPoint(x: 0, y: size.height)
                        )
                    )

                    context.stroke(
                        linePath,
                        with: .color(color.opacity(0.85)),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                    )
                }

                if let ratio = hoverRatio, points.count >= 2 {
                    let idx = min(max(Int(round(ratio * CGFloat(points.count - 1))), 0), points.count - 1)
                    let pt = points[idx]
                    let x = ratio * w
                    let label = valueFormatter?(pt.value) ?? String(format: "%.1f", pt.value)

                    Path { p in
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: h))
                    }
                    .stroke(color.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))

                    Text("\(label) · \(Format.relativeTime(from: pt.timestamp))")
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.regularMaterial, in: Capsule())
                        .offset(x: min(max(4, x - 48), max(4, w - 110)), y: 2)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc):
                    hoverRatio = min(max(loc.x / max(1, w), 0), 1)
                case .ended:
                    hoverRatio = nil
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - DualAreaChart (RX/TX & Disk Read/Write)

public struct DualAreaChart: View {
    public let primaryPoints: [TimePoint]
    public let secondaryPoints: [TimePoint]
    public let primaryColor: Color
    public let secondaryColor: Color
    public let primaryLabel: String
    public let secondaryLabel: String
    public var height: CGFloat = 100
    public var formatter: (Double) -> String = { Format.rate($0) }

    @State private var hoverRatio: CGFloat?

    public init(
        primaryPoints: [TimePoint],
        secondaryPoints: [TimePoint],
        primaryColor: Color,
        secondaryColor: Color,
        primaryLabel: String,
        secondaryLabel: String,
        height: CGFloat = 100,
        formatter: @escaping (Double) -> String = { Format.rate($0) }
    ) {
        self.primaryPoints = primaryPoints
        self.secondaryPoints = secondaryPoints
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.primaryLabel = primaryLabel
        self.secondaryLabel = secondaryLabel
        self.height = height
        self.formatter = formatter
    }

    public var body: some View {
        let maxPrimary = primaryPoints.map(\.value).max() ?? 1
        let maxSecondary = secondaryPoints.map(\.value).max() ?? 1
        let sharedMax = max(maxPrimary, maxSecondary, 1024)

        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    Self.drawSeries(
                        in: &context,
                        size: size,
                        points: secondaryPoints,
                        maxVal: sharedMax,
                        color: secondaryColor
                    )
                    Self.drawSeries(
                        in: &context,
                        size: size,
                        points: primaryPoints,
                        maxVal: sharedMax,
                        color: primaryColor
                    )
                }

                if let ratio = hoverRatio, primaryPoints.count >= 2 {
                    let idx1 = min(max(Int(round(ratio * CGFloat(primaryPoints.count - 1))), 0), primaryPoints.count - 1)
                    let idx2 = min(max(Int(round(ratio * CGFloat(max(1, secondaryPoints.count) - 1))), 0), max(0, secondaryPoints.count - 1))
                    let v1 = primaryPoints[idx1].value
                    let v2 = secondaryPoints.isEmpty ? 0 : secondaryPoints[idx2].value
                    let x = ratio * w

                    Path { p in
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: h))
                    }
                    .stroke(primaryColor.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))

                    HStack(spacing: 8) {
                        Text("\(primaryLabel): \(formatter(v1))")
                            .foregroundStyle(primaryColor)
                        Text("\(secondaryLabel): \(formatter(v2))")
                            .foregroundStyle(secondaryColor)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.regularMaterial, in: Capsule())
                    .offset(x: min(max(4, x - 80), max(4, w - 210)), y: 4)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc):
                    hoverRatio = min(max(loc.x / max(1, w), 0), 1)
                case .ended:
                    hoverRatio = nil
                }
            }
        }
        .frame(height: height)
    }

    private static func drawSeries(
        in context: inout GraphicsContext,
        size: CGSize,
        points: [TimePoint],
        maxVal: Double,
        color: Color
    ) {
        guard points.count >= 2 else { return }
        let stepX = size.width / CGFloat(max(1, points.count - 1))
        var line = Path()
        var fill = Path()

        for (i, pt) in points.enumerated() {
            let x = CGFloat(i) * stepX
            let norm = min(max(pt.value / maxVal, 0), 1)
            let y = size.height - CGFloat(norm) * (size.height - 6) - 3
            if i == 0 {
                line.move(to: CGPoint(x: x, y: y))
                fill.move(to: CGPoint(x: x, y: size.height))
                fill.addLine(to: CGPoint(x: x, y: y))
            } else {
                line.addLine(to: CGPoint(x: x, y: y))
                fill.addLine(to: CGPoint(x: x, y: y))
            }
        }
        fill.addLine(to: CGPoint(x: size.width, y: size.height))
        fill.closeSubpath()

        context.fill(
            fill,
            with: .linearGradient(
                Gradient(colors: [color.opacity(0.12), color.opacity(0.01)]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: size.height)
            )
        )
        context.stroke(line, with: .color(color.opacity(0.85)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }
}

// MARK: - Inline Sparkline

public struct Sparkline: View {
    public let values: [Double]
    public let color: Color
    public var fixedMax: Double? = nil

    public init(values: [Double], color: Color, fixedMax: Double? = nil) {
        self.values = values
        self.color = color
        self.fixedMax = fixedMax
    }

    public var body: some View {
        Canvas { context, size in
            guard values.count >= 2 else { return }
            let maxVal = max(fixedMax ?? (values.max() ?? 1.0), 0.001)
            let stepX = size.width / CGFloat(max(1, values.count - 1))
            var path = Path()
            for (idx, val) in values.enumerated() {
                let x = CGFloat(idx) * stepX
                let norm = min(max(val / maxVal, 0), 1)
                let y = size.height - CGFloat(norm) * (size.height - 2) - 1
                if idx == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(path, with: .color(color.opacity(0.75)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - CoreHeatmapGrid

public struct CoreHeatmapGrid: View {
    public let cores: [CoreSeries]
    public let palette: ThemePalette

    public init(cores: [CoreSeries], palette: ThemePalette) {
        self.cores = cores
        self.palette = palette
    }

    private let columns = [
        GridItem(.adaptive(minimum: 112, maximum: 170), spacing: 8)
    ]

    public var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(cores) { core in
                let coreColor = core.type == .efficiency ? palette.accentEmerald : palette.accentCyan
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("\(core.type.rawValue)\(core.id + 1)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Spacer()
                        Text(Format.percent(core.currentUsage, decimals: 0))
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                    }

                    Sparkline(
                        values: core.points.map(\.value),
                        color: coreColor,
                        fixedMax: 100
                    )
                    .frame(height: 20)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(palette.subtleFill)
                            Capsule()
                                .fill(coreColor.opacity(0.85))
                                .frame(width: geo.size.width * CGFloat(min(max(core.currentUsage / 100.0, 0), 1)))
                        }
                    }
                    .frame(height: 4)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.backgroundPrimary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(palette.cardBorder, lineWidth: 1)
                )
            }
        }
    }
}
