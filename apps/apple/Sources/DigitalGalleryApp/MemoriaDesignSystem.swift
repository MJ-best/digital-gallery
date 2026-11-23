import SwiftUI

// MARK: - Memoria Pastel Blue Palette (Cohesive Sky Blue & Cloud White)
enum MemoriaPalette {
    static let canvas = Color(red: 0.94, green: 0.97, blue: 1.00)
    static let softSky = Color(red: 0.88, green: 0.94, blue: 1.00)
    static let softLavender = Color(red: 0.90, green: 0.95, blue: 1.00)
    static let ink = Color(red: 0.07, green: 0.10, blue: 0.16)
    static let subInk = Color(red: 0.44, green: 0.50, blue: 0.59)
    static let purple = Color(red: 0.27, green: 0.60, blue: 0.98)
    static let sky = Color(red: 0.36, green: 0.70, blue: 1.00)
    static let coralPink = Color(red: 0.36, green: 0.68, blue: 1.00)
    static let warmYellow = Color(red: 0.54, green: 0.79, blue: 1.00)

    static var iconGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.38, green: 0.56, blue: 0.98),
                Color(red: 0.35, green: 0.70, blue: 1.00),
                Color(red: 0.44, green: 0.80, blue: 1.00),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var sunsetPill: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.43, green: 0.75, blue: 1.00),
                Color(red: 0.27, green: 0.60, blue: 0.98),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static var skyLavenderPill: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.43, green: 0.75, blue: 1.00),
                Color(red: 0.27, green: 0.60, blue: 0.98),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static var mintSkyWave: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.80, green: 0.92, blue: 1.00),
                Color(red: 0.65, green: 0.86, blue: 1.00),
                Color(red: 0.52, green: 0.78, blue: 1.00),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Exact Memoria App Logo Mark (Matching reference S-wave & tilted eyes)
struct MemoriaLogoMark: View {
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(MemoriaPalette.iconGradient)

            // Soft left lavender-pink edge glow
            Circle()
                .fill(Color(red: 0.86, green: 0.54, blue: 0.88).opacity(0.60))
                .frame(width: size * 0.75, height: size * 0.75)
                .blur(radius: size * 0.14)
                .offset(x: -size * 0.36, y: size * 0.08)

            // Upper-right 4-point star (✦)
            FourPointSparkle()
                .fill(Color.white)
                .frame(width: size * 0.19, height: size * 0.19)
                .offset(x: size * 0.27, y: -size * 0.26)

            // Outer translucent dome halo
            Ellipse()
                .fill(Color.white.opacity(0.22))
                .frame(width: size * 0.94, height: size * 0.82)
                .offset(y: size * 0.22)

            // White dome character
            Ellipse()
                .fill(Color.white)
                .frame(width: size * 0.88, height: size * 0.76)
                .offset(y: size * 0.25)

            // Two tilted dark navy oval eyes (\ \)
            HStack(spacing: size * 0.13) {
                Capsule()
                    .fill(MemoriaPalette.ink)
                    .frame(width: size * 0.082, height: size * 0.165)
                    .rotationEffect(.degrees(-11))
                Capsule()
                    .fill(MemoriaPalette.ink)
                    .frame(width: size * 0.082, height: size * 0.165)
                    .rotationEffect(.degrees(-11))
                    .offset(y: -size * 0.018)
            }
            .offset(y: size * 0.12)

            // Smooth S-curve bottom wave (pale cream left -> pastel sky blue right)
            MemoriaSWaveShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.00, green: 0.95, blue: 0.74),
                            Color(red: 0.86, green: 0.94, blue: 0.98),
                            Color(red: 0.56, green: 0.82, blue: 1.00),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .shadow(color: Color(red: 0.27, green: 0.58, blue: 0.96).opacity(0.22), radius: 10, y: 4)
    }
}

struct MemoriaSWaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: 0, y: h * 0.77))
        p.addCurve(
            to: CGPoint(x: w * 0.58, y: h * 0.82),
            control1: CGPoint(x: w * 0.18, y: h * 0.94),
            control2: CGPoint(x: w * 0.40, y: h * 0.93)
        )
        p.addCurve(
            to: CGPoint(x: w, y: h * 0.71),
            control1: CGPoint(x: w * 0.75, y: h * 0.70),
            control2: CGPoint(x: w * 0.89, y: h * 0.67)
        )
        p.addLine(to: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: 0, y: h))
        p.closeSubpath()
        return p
    }
}

struct FourPointSparkle: Shape {
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let cy = rect.midY
        let r = min(rect.width, rect.height) * 0.5
        let inner = r * 0.28
        var p = Path()
        p.move(to: CGPoint(x: cx, y: cy - r))
        p.addQuadCurve(to: CGPoint(x: cx + r, y: cy), control: CGPoint(x: cx + inner, y: cy - inner))
        p.addQuadCurve(to: CGPoint(x: cx, y: cy + r), control: CGPoint(x: cx + inner, y: cy + inner))
        p.addQuadCurve(to: CGPoint(x: cx - r, y: cy), control: CGPoint(x: cx - inner, y: cy + inner))
        p.addQuadCurve(to: CGPoint(x: cx, y: cy - r), control: CGPoint(x: cx - inner, y: cy - inner))
        p.closeSubpath()
        return p
    }
}

// MARK: - Pastel Blue Sky & Peeking Cloud Mascot Card (Matching Reference Right Screen)
struct MemoriaCameraMascotHero: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            // Pastel Blue Sky backdrop
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.34, green: 0.67, blue: 1.00),
                            Color(red: 0.65, green: 0.85, blue: 1.00),
                            Color(red: 0.90, green: 0.96, blue: 1.00),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Three cute white celebration lines (\ | /) on upper right
            ZStack {
                Capsule().fill(Color.white).frame(width: 3, height: 10).rotationEffect(.degrees(12)).offset(x: 34, y: -26)
                Capsule().fill(Color.white).frame(width: 3, height: 10).rotationEffect(.degrees(35)).offset(x: 42, y: -21)
                Capsule().fill(Color.white).frame(width: 3, height: 10).rotationEffect(.degrees(58)).offset(x: 47, y: -13)
            }

            // White peeking dome mascot with tilted (\ \) eyes
            ZStack {
                Ellipse()
                    .fill(Color.white)
                    .frame(width: 68, height: 56)
                HStack(spacing: 10) {
                    Capsule().fill(MemoriaPalette.ink).frame(width: 5, height: 11).rotationEffect(.degrees(-10))
                    Capsule().fill(MemoriaPalette.ink).frame(width: 5, height: 11).rotationEffect(.degrees(-10)).offset(y: -1)
                }
                .offset(y: -4)
            }
            .offset(y: 8)

            // Foreground fluffy white cloud puffs along the bottom
            HStack(spacing: -14) {
                Circle().fill(Color.white.opacity(0.92)).frame(width: 44, height: 32)
                Circle().fill(Color.white).frame(width: 56, height: 34)
                Circle().fill(Color.white).frame(width: 58, height: 34)
                Circle().fill(Color.white.opacity(0.92)).frame(width: 44, height: 32)
            }
            .offset(y: 14)
        }
        .frame(height: 82)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Soft White Card Container
struct MemoriaCard<Content: View>: View {
    let title: String?
    let icon: String?
    @ViewBuilder let content: Content

    init(title: String? = nil, icon: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 6) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MemoriaPalette.purple)
                    }
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(MemoriaPalette.ink)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color(red: 0.35, green: 0.68, blue: 1.00).opacity(0.14), lineWidth: 1)
                )
                .shadow(color: Color(red: 0.25, green: 0.50, blue: 0.85).opacity(0.06), radius: 16, y: 6)
        )
    }
}

// MARK: - Soft Input Field
struct MemoriaTextField: View {
    let label: String
    @Binding var text: String
    var multiline: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MemoriaPalette.subInk)
            if multiline {
                TextField(label, text: $text, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(MemoriaPalette.ink)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(MemoriaPalette.canvas)
                    )
            } else {
                TextField(label, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MemoriaPalette.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(MemoriaPalette.canvas)
                    )
            }
        }
    }
}
