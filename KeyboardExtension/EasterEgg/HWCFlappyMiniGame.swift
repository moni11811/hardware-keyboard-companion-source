import SwiftUI
import UIKit

private enum HWCFlappyConstants {
    static let gravity: CGFloat = 1_400
    static let flapImpulse: CGFloat = -420
    static let pipeSpeed: CGFloat = 140
    static let pipeGap: CGFloat = 130
    static let pipeSpacing: CGFloat = 200
    static let pipeWidth: CGFloat = 44
    static let birdSize: CGFloat = 28
    static let groundHeight: CGFloat = 24
}

@MainActor
final class HWCFlappyMiniGameModel: ObservableObject {
    struct Pipe: Identifiable, Equatable {
        let id = UUID()
        var x: CGFloat
        var gapCenter: CGFloat
        var hasScored = false
    }

    @Published private(set) var birdY: CGFloat = 120
    @Published private(set) var birdVelocity: CGFloat = 0
    @Published private(set) var pipes = [Pipe]()
    @Published private(set) var score = 0
    @Published private(set) var bestScore = 0
    @Published private(set) var worldOffset: CGFloat = 0
    @Published private(set) var isGameOver = false
    @Published private(set) var isStarted = false

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var viewSize: CGSize = .zero
    private var difficultyMultiplier: CGFloat {
        min(1.65, 1 + CGFloat(score) * 0.035)
    }

    var birdRotationDegrees: Double {
        Double(min(34, max(-24, birdVelocity / 16)))
    }

    init() {
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    deinit {
        displayLink?.invalidate()
    }

    func update(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let wasUnset = viewSize == .zero
        viewSize = size
        if wasUnset {
            resetBoard()
        }
    }

    func flap() {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        if isGameOver {
            resetBoard()
        }
        if !isStarted {
            isStarted = true
            lastTimestamp = nil
            displayLink?.isPaused = false
        }
        birdVelocity = HWCFlappyConstants.flapImpulse
    }

    func pause() {
        displayLink?.isPaused = true
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    func resume() {
        guard isStarted, !isGameOver else { return }
        lastTimestamp = nil
        displayLink?.isPaused = false
    }

    func topPipeHeight(for pipe: Pipe) -> CGFloat {
        max(0, pipe.gapCenter - HWCFlappyConstants.pipeGap / 2)
    }

    func bottomPipeFrame(for pipe: Pipe, in size: CGSize) -> CGRect {
        let groundTop = max(0, size.height - HWCFlappyConstants.groundHeight)
        let top = min(groundTop, pipe.gapCenter + HWCFlappyConstants.pipeGap / 2)
        return CGRect(
            x: pipe.x,
            y: top,
            width: HWCFlappyConstants.pipeWidth,
            height: max(0, groundTop - top)
        )
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard isStarted, !isGameOver, viewSize.width > 0, viewSize.height > 0 else { return }
        let dt: CGFloat
        if let lastTimestamp {
            dt = min(CGFloat(link.timestamp - lastTimestamp), 1 / 30)
        } else {
            dt = 1 / 60
        }
        lastTimestamp = link.timestamp
        step(dt: dt)
    }

    private func step(dt: CGFloat) {
        birdVelocity += HWCFlappyConstants.gravity * dt
        birdY += birdVelocity * dt
        worldOffset = (worldOffset + HWCFlappyConstants.pipeSpeed * difficultyMultiplier * dt)
            .truncatingRemainder(dividingBy: 240)

        for index in pipes.indices {
            pipes[index].x -= HWCFlappyConstants.pipeSpeed * difficultyMultiplier * dt
        }

        pipes.removeAll { $0.x + HWCFlappyConstants.pipeWidth < -20 }
        refillPipes()
        updateScore()
        if hasCollision() {
            isGameOver = true
            displayLink?.isPaused = true
        }
    }

    private func resetBoard() {
        birdY = max(72, viewSize.height * 0.42)
        birdVelocity = 0
        score = 0
        worldOffset = 0
        isGameOver = false
        isStarted = false
        lastTimestamp = nil
        pipes = []
        refillPipes(startingAt: viewSize.width + 96)
        displayLink?.isPaused = true
    }

    private func refillPipes(startingAt firstX: CGFloat? = nil) {
        guard viewSize.width > 0 else { return }
        var nextX = firstX ?? ((pipes.last?.x ?? (viewSize.width + 96)) + HWCFlappyConstants.pipeSpacing)
        while nextX < viewSize.width + HWCFlappyConstants.pipeSpacing * 2 {
            pipes.append(Pipe(x: nextX, gapCenter: randomGapCenter()))
            nextX += HWCFlappyConstants.pipeSpacing
        }
    }

    private func randomGapCenter() -> CGFloat {
        let groundTop = max(HWCFlappyConstants.groundHeight, viewSize.height - HWCFlappyConstants.groundHeight)
        let low = HWCFlappyConstants.pipeGap / 2 + 28
        let high = max(low, groundTop - HWCFlappyConstants.pipeGap / 2 - 28)
        return CGFloat.random(in: low...high)
    }

    private func updateScore() {
        let birdX = viewSize.width * 0.32
        for index in pipes.indices where !pipes[index].hasScored && pipes[index].x + HWCFlappyConstants.pipeWidth < birdX {
            pipes[index].hasScored = true
            score += 1
            bestScore = max(bestScore, score)
        }
    }

    private func hasCollision() -> Bool {
        let birdRect = CGRect(
            x: viewSize.width * 0.32 - HWCFlappyConstants.birdSize / 2,
            y: birdY - HWCFlappyConstants.birdSize / 2,
            width: HWCFlappyConstants.birdSize,
            height: HWCFlappyConstants.birdSize
        )
        let groundTop = max(0, viewSize.height - HWCFlappyConstants.groundHeight)
        guard birdRect.minY > 0, birdRect.maxY < groundTop else { return true }

        for pipe in pipes {
            let topRect = CGRect(
                x: pipe.x,
                y: 0,
                width: HWCFlappyConstants.pipeWidth,
                height: topPipeHeight(for: pipe)
            )
            if birdRect.intersects(topRect) || birdRect.intersects(bottomPipeFrame(for: pipe, in: viewSize)) {
                return true
            }
        }
        return false
    }
}

struct HWCFlappyMiniGame: View {
    @ObservedObject private var model: HWCFlappyMiniGameModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let onClose: () -> Void

    init(model: HWCFlappyMiniGameModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
    }

    @MainActor
    func flap() {
        model.flap()
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                background
                cloudLayer(in: geometry.size)
                pipes(in: geometry.size)
                groundStripes(in: geometry.size)
                bird(in: geometry.size)
                score(in: geometry.size)
                statusOverlay(in: geometry.size)
                closeButton
            }
            .contentShape(Rectangle())
            .onTapGesture {
                model.flap()
            }
            .onAppear {
                model.update(size: geometry.size)
            }
            .onChange(of: geometry.size) { _, newSize in
                model.update(size: newSize)
            }
        }
    }

    private var background: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color(red: 0.52, green: 0.82, blue: 0.98), Color(red: 0.86, green: 0.96, blue: 1)],
                startPoint: .top,
                endPoint: .bottom
            )
            Rectangle()
                .fill(Color(red: 0.55, green: 0.42, blue: 0.26))
                .frame(height: HWCFlappyConstants.groundHeight)
        }
        .ignoresSafeArea()
    }

    private func pipes(in size: CGSize) -> some View {
        ZStack {
            ForEach(model.pipes) { pipe in
                let topHeight = model.topPipeHeight(for: pipe)
                let bottomFrame = model.bottomPipeFrame(for: pipe, in: size)

                Rectangle()
                    .fill(Color(red: 0.08, green: 0.62, blue: 0.22))
                    .frame(width: HWCFlappyConstants.pipeWidth, height: topHeight)
                    .position(x: pipe.x + HWCFlappyConstants.pipeWidth / 2, y: topHeight / 2)

                Rectangle()
                    .fill(Color(red: 0.05, green: 0.40, blue: 0.16))
                    .frame(width: HWCFlappyConstants.pipeWidth + 10, height: 8)
                    .position(x: pipe.x + HWCFlappyConstants.pipeWidth / 2, y: max(4, topHeight - 4))

                Rectangle()
                    .fill(Color(red: 0.08, green: 0.62, blue: 0.22))
                    .frame(width: bottomFrame.width, height: bottomFrame.height)
                    .position(x: bottomFrame.midX, y: bottomFrame.midY)

                Rectangle()
                    .fill(Color(red: 0.05, green: 0.40, blue: 0.16))
                    .frame(width: HWCFlappyConstants.pipeWidth + 10, height: 8)
                    .position(x: bottomFrame.midX, y: bottomFrame.minY + 4)
            }
        }
    }

    private func bird(in size: CGSize) -> some View {
        Text("🐤")
            .font(.system(size: HWCFlappyConstants.birdSize))
            .frame(width: 44, height: 44)
            .scaleEffect(x: -1, y: 1)
            .rotationEffect(.degrees(model.birdRotationDegrees))
            .shadow(color: .black.opacity(0.22), radius: 4, x: 0, y: 3)
            .position(x: size.width * 0.32, y: model.birdY)
            .animation(.spring(response: 0.16, dampingFraction: 0.72), value: model.birdVelocity)
    }

    private func score(in size: CGSize) -> some View {
        HStack(spacing: 10) {
            Text("\(model.score)")
                .font(.system(size: 32, weight: .black, design: .rounded))

            if model.bestScore > 0 {
                Text("BEST \(model.bestScore)")
                    .font(.system(size: 11, weight: .black, design: .rounded))
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.18))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
        .position(x: size.width / 2, y: 34)
    }

    private func cloudLayer(in size: CGSize) -> some View {
        ZStack {
            cloud(x: size.width * 0.18 - model.worldOffset * 0.16, y: 42, scale: 0.78)
            cloud(x: size.width * 0.58 - model.worldOffset * 0.10, y: 74, scale: 1.02)
            cloud(x: size.width * 0.92 - model.worldOffset * 0.13, y: 38, scale: 0.66)
        }
        .opacity(0.78)
    }

    private func cloud(x: CGFloat, y: CGFloat, scale: CGFloat) -> some View {
        let wrappedX = ((x.truncatingRemainder(dividingBy: 420)) + 420).truncatingRemainder(dividingBy: 420) - 40
        return ZStack {
            Capsule()
                .fill(.white.opacity(0.72))
                .frame(width: 68 * scale, height: 18 * scale)
            Circle()
                .fill(.white.opacity(0.78))
                .frame(width: 28 * scale, height: 28 * scale)
                .offset(x: -18 * scale, y: -5 * scale)
            Circle()
                .fill(.white.opacity(0.66))
                .frame(width: 24 * scale, height: 24 * scale)
                .offset(x: 12 * scale, y: -6 * scale)
        }
        .position(x: wrappedX, y: y)
    }

    private func groundStripes(in size: CGSize) -> some View {
        let stripeWidth: CGFloat = 26
        return HStack(spacing: 0) {
            ForEach(0..<18, id: \.self) { index in
                Rectangle()
                    .fill(index.isMultiple(of: 2) ? Color.white.opacity(0.15) : Color.clear)
                    .frame(width: stripeWidth, height: HWCFlappyConstants.groundHeight)
            }
        }
        .offset(x: -model.worldOffset.truncatingRemainder(dividingBy: stripeWidth))
        .frame(width: size.width, height: HWCFlappyConstants.groundHeight, alignment: .leading)
        .clipped()
        .position(x: size.width / 2, y: size.height - HWCFlappyConstants.groundHeight / 2)
    }

    @ViewBuilder
    private func statusOverlay(in size: CGSize) -> some View {
        if !model.isStarted || model.isGameOver {
            VStack(spacing: 10) {
                Text(model.isGameOver ? "GAME OVER" : "READY")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)

                if model.isGameOver {
                    Button(action: model.flap) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 18, weight: .black))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 36)
                            .background(.white.opacity(0.18))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Restart")
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(.black.opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .position(x: size.width / 2, y: size.height * 0.38)
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 44, height: 44)
                .background(closeButtonBackground)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(6)
    }

    @ViewBuilder
    private var closeButtonBackground: some View {
        if reduceTransparency {
            Circle()
                .fill(Color.black.opacity(0.82))
        } else {
            Circle()
                .fill(.ultraThinMaterial)
        }
    }
}
