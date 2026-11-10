import SwiftUI
import AppKit
import TaskyfyCore

// MARK: - Palette & Theme Tokens (Helium Paper Minimal & Apple System UI)

public struct ThemePalette: Sendable {
    public let backgroundPrimary: Color
    public let backgroundSecondary: Color
    public let cardSurface: Color
    public let cardBorder: Color
    public let subtleFill: Color
    public let textPrimary: Color
    public let textSecondary: Color
    public let accentCyan: Color
    public let accentViolet: Color
    public let accentEmerald: Color
    public let accentAmber: Color
    public let accentCoral: Color
    public let preferredColorScheme: ColorScheme?

    public static func forTheme(_ theme: AppTheme) -> ThemePalette {
        switch theme {
        case .solarisDaylight:
            // Helium Paper Minimal (Default White)
            return ThemePalette(
                backgroundPrimary: Color(red: 1.0, green: 1.0, blue: 1.0),
                backgroundSecondary: Color(red: 0.949, green: 0.949, blue: 0.941), // #F2F2F0 warm sidebar
                cardSurface: Color(red: 0.978, green: 0.978, blue: 0.973),         // #F9F9F8 subtle paper card
                cardBorder: Color.black.opacity(0.085),
                subtleFill: Color.black.opacity(0.055),                            // #E5E5E3 active pill
                textPrimary: Color(red: 0.086, green: 0.086, blue: 0.098),         // #161619 Apple ink
                textSecondary: Color(red: 0.45, green: 0.45, blue: 0.48),          // #73737A muted gray
                accentCyan: Color(red: 0.11, green: 0.11, blue: 0.13),             // #1C1C21 monochrome charcoal
                accentViolet: Color(red: 0.35, green: 0.38, blue: 0.46),           // #596175 calm slate
                accentEmerald: Color(red: 0.086, green: 0.639, blue: 0.290),       // #16A34A Helium green
                accentAmber: Color(red: 0.80, green: 0.44, blue: 0.04),            // #CC700A calm amber
                accentCoral: Color(red: 0.84, green: 0.18, blue: 0.18),            // #D62E2E calm red
                preferredColorScheme: .light
            )
        case .systemAdaptive:
            return ThemePalette(
                backgroundPrimary: Color(nsColor: .windowBackgroundColor),
                backgroundSecondary: Color(nsColor: .underPageBackgroundColor),
                cardSurface: Color.primary.opacity(0.035),
                cardBorder: Color.primary.opacity(0.09),
                subtleFill: Color.primary.opacity(0.06),
                textPrimary: Color.primary,
                textSecondary: Color.secondary,
                accentCyan: Color.primary,
                accentViolet: Color(red: 0.38, green: 0.42, blue: 0.52),
                accentEmerald: Color(red: 0.086, green: 0.639, blue: 0.290),
                accentAmber: Color(red: 0.82, green: 0.46, blue: 0.05),
                accentCoral: Color(red: 0.84, green: 0.18, blue: 0.18),
                preferredColorScheme: nil
            )
        case .cyberGraphite:
            return ThemePalette(
                backgroundPrimary: Color(red: 0.09, green: 0.09, blue: 0.10),
                backgroundSecondary: Color(red: 0.12, green: 0.12, blue: 0.135),
                cardSurface: Color.white.opacity(0.045),
                cardBorder: Color.white.opacity(0.09),
                subtleFill: Color.white.opacity(0.07),
                textPrimary: Color(red: 0.95, green: 0.95, blue: 0.96),
                textSecondary: Color(red: 0.60, green: 0.61, blue: 0.65),
                accentCyan: Color(red: 0.88, green: 0.89, blue: 0.92),
                accentViolet: Color(red: 0.58, green: 0.62, blue: 0.72),
                accentEmerald: Color(red: 0.16, green: 0.76, blue: 0.42),
                accentAmber: Color(red: 0.92, green: 0.62, blue: 0.14),
                accentCoral: Color(red: 0.92, green: 0.32, blue: 0.32),
                preferredColorScheme: .dark
            )
        case .obsidianAurora:
            return ThemePalette(
                backgroundPrimary: Color(red: 0.07, green: 0.075, blue: 0.09),
                backgroundSecondary: Color(red: 0.10, green: 0.105, blue: 0.125),
                cardSurface: Color.white.opacity(0.045),
                cardBorder: Color.white.opacity(0.09),
                subtleFill: Color.white.opacity(0.07),
                textPrimary: Color(red: 0.95, green: 0.96, blue: 0.98),
                textSecondary: Color(red: 0.60, green: 0.63, blue: 0.68),
                accentCyan: Color(red: 0.82, green: 0.85, blue: 0.90),
                accentViolet: Color(red: 0.56, green: 0.60, blue: 0.72),
                accentEmerald: Color(red: 0.16, green: 0.76, blue: 0.42),
                accentAmber: Color(red: 0.92, green: 0.62, blue: 0.14),
                accentCoral: Color(red: 0.92, green: 0.32, blue: 0.32),
                preferredColorScheme: .dark
            )
        }
    }
}

// MARK: - Taskyfy Minimal White & Black Geometric Logo (Canva Design DAHafeKpN-M)

public struct TaskyfyLogo: View {
    public var size: CGFloat = 28
    public var showPulseRing: Bool = false

    public init(size: CGFloat = 28, showPulseRing: Bool = false) {
        self.size = size
        self.showPulseRing = showPulseRing
    }

    public var body: some View {
        ZStack {
            // Pure white squircle with subtle crisp black border
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.16), lineWidth: 1)
                )

            // Canva Minimal Black Display + Symmetric Pulse + T-Stand Mark
            Canvas { context, canvasSize in
                let w = canvasSize.width
                let h = canvasSize.height
                let strokeW = max(1.5, w * 0.075)

                // 1. Top rounded monitor arch
                var arch = Path()
                let archRect = CGRect(x: w * 0.17, y: h * 0.17, width: w * 0.66, height: h * 0.36)
                let r = w * 0.08
                arch.move(to: CGPoint(x: archRect.minX, y: archRect.maxY))
                arch.addLine(to: CGPoint(x: archRect.minX, y: archRect.minY + r))
                arch.addQuadCurve(
                    to: CGPoint(x: archRect.minX + r, y: archRect.minY),
                    control: CGPoint(x: archRect.minX, y: archRect.minY)
                )
                arch.addLine(to: CGPoint(x: archRect.maxX - r, y: archRect.minY))
                arch.addQuadCurve(
                    to: CGPoint(x: archRect.maxX, y: archRect.minY + r),
                    control: CGPoint(x: archRect.maxX, y: archRect.minY)
                )
                arch.addLine(to: CGPoint(x: archRect.maxX, y: archRect.maxY))
                context.stroke(
                    arch,
                    with: .color(.black),
                    style: StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round)
                )

                // 2. Symmetric telemetry pulse wave across the display base
                var wave = Path()
                let baseY = h * 0.61
                wave.move(to: CGPoint(x: w * 0.17, y: baseY))
                wave.addLine(to: CGPoint(x: w * 0.31, y: baseY))
                wave.addLine(to: CGPoint(x: w * 0.36, y: h * 0.52))
                wave.addLine(to: CGPoint(x: w * 0.41, y: baseY))
                wave.addLine(to: CGPoint(x: w * 0.44, y: baseY))
                wave.addLine(to: CGPoint(x: w * 0.50, y: h * 0.32))
                wave.addLine(to: CGPoint(x: w * 0.56, y: baseY))
                wave.addLine(to: CGPoint(x: w * 0.59, y: baseY))
                wave.addLine(to: CGPoint(x: w * 0.64, y: h * 0.52))
                wave.addLine(to: CGPoint(x: w * 0.69, y: baseY))
                wave.addLine(to: CGPoint(x: w * 0.83, y: baseY))
                context.stroke(
                    wave,
                    with: .color(.black),
                    style: StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round)
                )

                // 3. Bottom symmetric T-stand pillars
                var leftStand = Path()
                leftStand.move(to: CGPoint(x: w * 0.35, y: h * 0.70))
                leftStand.addLine(to: CGPoint(x: w * 0.46, y: h * 0.70))
                leftStand.addLine(to: CGPoint(x: w * 0.46, y: h * 0.85))
                context.stroke(
                    leftStand,
                    with: .color(.black),
                    style: StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round)
                )

                var rightStand = Path()
                rightStand.move(to: CGPoint(x: w * 0.65, y: h * 0.70))
                rightStand.addLine(to: CGPoint(x: w * 0.54, y: h * 0.70))
                rightStand.addLine(to: CGPoint(x: w * 0.54, y: h * 0.85))
                context.stroke(
                    rightStand,
                    with: .color(.black),
                    style: StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Clean Minimal Card & Pill Surfaces

public struct GlassCard<Content: View>: View {
    private let palette: ThemePalette
    private let padding: CGFloat
    private let cornerRadius: CGFloat
    private let tint: Color?
    private let content: Content

    public init(
        palette: ThemePalette,
        padding: CGFloat = 14,
        cornerRadius: CGFloat = 12,
        tint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.palette = palette
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(palette.cardSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(palette.cardBorder, lineWidth: 1)
            )
    }
}

public struct StatusPill: View {
    public let label: String
    public let color: Color
    public var symbol: String? = nil

    public init(label: String, color: Color, symbol: String? = nil) {
        self.label = label
        self.color = color
        self.symbol = symbol
    }

    public var body: some View {
        HStack(spacing: 4.5) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .medium))
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 5.5, height: 5.5)
            }
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(0.08))
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}
