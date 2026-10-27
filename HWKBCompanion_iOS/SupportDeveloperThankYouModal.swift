import SwiftUI

struct SupportDeveloperThankYouModal: View {
    let prompt: SupportDeveloperThankYouPrompt
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var emblemPopped = false

    private var accentColors: [Color] {
        switch prompt.kind {
        case .coffee:
            return [Color(red: 0.85, green: 0.55, blue: 0.22), Color(red: 0.55, green: 0.30, blue: 0.14)]
        case .burger:
            return [Color(red: 0.97, green: 0.58, blue: 0.20), Color(red: 0.89, green: 0.20, blue: 0.28)]
        case .yearly:
            return [
                Color(red: 0.95, green: 0.16, blue: 0.30),
                Color(red: 0.18, green: 0.55, blue: 0.96),
                Color(red: 0.13, green: 0.80, blue: 0.42)
            ]
        }
    }

    private var emblemSymbol: String {
        switch prompt.kind {
        case .coffee: return "cup.and.saucer.fill"
        case .burger: return "takeoutbag.and.cup.and.straw.fill"
        case .yearly: return "crown.fill"
        }
    }

    private var accentGradient: LinearGradient {
        LinearGradient(colors: accentColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var isCelebration: Bool { prompt.kind == .yearly }

    var body: some View {
        ZStack {
            Color.black.opacity(appeared ? 0.66 : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            if isCelebration && !reduceMotion {
                ThankYouConfettiView(active: appeared, colors: accentColors)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }

            card
                .scaleEffect(appeared || reduceMotion ? 1 : 0.86)
                .opacity(appeared ? 1 : 0)
                .padding(.horizontal, 28)
        }
        .onAppear {
            if reduceMotion {
                appeared = true
                emblemPopped = true
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { appeared = true }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.58).delay(0.12)) { emblemPopped = true }
            }
        }
    }

    private var card: some View {
        VStack(spacing: 16) {
            emblem
            Text(prompt.title)
                .font(.system(size: 25, weight: .heavy))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(prompt.message)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundColor(.white.opacity(0.82))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if !prompt.steps.isEmpty {
                stepsSection.padding(.top, 2)
            }
            Button(action: { dismiss() }) {
                Text("Done")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(red: 0.07, green: 0.08, blue: 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(accentGradient, lineWidth: 1.5)
        )
        .shadow(color: accentColors[0].opacity(0.4), radius: 28, x: 0, y: 18)
    }

    private var emblem: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: 2)
                .frame(width: 92, height: 92)
                .scaleEffect(emblemPopped ? 1.08 : 0.85)
                .opacity(emblemPopped ? 0 : 0.9)
            Circle()
                .fill(accentGradient)
                .frame(width: 72, height: 72)
                .shadow(color: accentColors[0].opacity(0.6), radius: 16, x: 0, y: 8)
            Image(systemName: emblemSymbol)
                .font(.system(size: 31, weight: .bold))
                .foregroundColor(.white)
        }
        .scaleEffect(emblemPopped ? 1 : 0.4)
        .rotationEffect(.degrees(emblemPopped ? 0 : -16))
    }

    @ViewBuilder
    private var stepsSection: some View {
        switch prompt.kind {
        case .coffee:
            keycapGrid
        case .burger, .yearly:
            benefitsList
        }
    }

    private var keycapGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 8)], spacing: 8) {
            ForEach(Array(prompt.steps.enumerated()), id: \.offset) { index, step in
                Text(step)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 8)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8).delay(0.18 + Double(index) * 0.05),
                        value: appeared
                    )
            }
        }
    }

    private var benefitsList: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(prompt.steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(accentColors[0])
                    Text(step)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer(minLength: 0)
                }
                .opacity(appeared ? 1 : 0)
                .offset(x: appeared ? 0 : -12)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82).delay(0.2 + Double(index) * 0.08),
                    value: appeared
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    private func dismiss() {
        if reduceMotion {
            onDismiss()
            return
        }
        withAnimation(.easeIn(duration: 0.22)) { appeared = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onDismiss() }
    }
}

private struct ThankYouConfettiPiece {
    let xFraction: CGFloat
    let delay: Double
    let duration: Double
    let width: CGFloat
    let height: CGFloat
    let spin: Double
    let drift: CGFloat
}

private struct ThankYouConfettiView: View {
    let active: Bool
    let colors: [Color]
    private let pieces: [ThankYouConfettiPiece]

    init(active: Bool, colors: [Color]) {
        self.active = active
        self.colors = colors
        self.pieces = (0..<28).map { _ in
            let w = CGFloat.random(in: 5...9)
            return ThankYouConfettiPiece(
                xFraction: CGFloat.random(in: 0.04...0.96),
                delay: Double.random(in: 0...0.3),
                duration: Double.random(in: 1.5...2.6),
                width: w,
                height: w * CGFloat.random(in: 1.4...2.0),
                spin: Double.random(in: -420...420),
                drift: CGFloat.random(in: -50...50)
            )
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(pieces.indices, id: \.self) { i in
                    let piece = pieces[i]
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(colors[i % colors.count])
                        .frame(width: piece.width, height: piece.height)
                        .position(
                            x: geo.size.width * piece.xFraction + (active ? piece.drift : 0),
                            y: active ? geo.size.height + 50 : -50
                        )
                        .rotationEffect(.degrees(active ? piece.spin : 0))
                        .opacity(active ? 0 : 1)
                        .animation(.easeIn(duration: piece.duration).delay(piece.delay), value: active)
                }
            }
        }
    }
}
