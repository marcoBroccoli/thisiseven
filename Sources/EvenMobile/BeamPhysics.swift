import SwiftUI
import SpriteKit
import EvenCore

// The beam scale, made physical: the beam and its hanging buckets live in a
// transparent SpriteKit scene; completed work drops in as balls that settle
// under real gravity. Percentages roll numerically beside it in SwiftUI.

#if canImport(UIKit)
private func skColor(_ color: Color) -> SKColor { UIColor(color) }
#else
private func skColor(_ color: Color) -> SKColor { NSColor(color) }
#endif

// MARK: - Scene

final class BeamPhysicsScene: SKScene {
    enum Side { case me, partner }

    private let beamHalf: CGFloat = 148
    private let pivotFromTop: CGFloat = 64
    private let maxBallsPerSide = 16

    // Spring toward the target tilt (matches the old SwiftUI spring feel).
    private var targetAngle: CGFloat = 0
    private var angle: CGFloat = 0
    private var angularVel: CGFloat = 0
    private var lastTime: TimeInterval?

    private let beamNode = SKNode()
    private let meBucket = SKNode()
    private let partnerBucket = SKNode()
    private var built = false
    private var ghostPartner = false

    private var inkColor = SKColor.black
    private var subColor = SKColor.gray
    private var meColor = SKColor.orange
    private var partnerColor = SKColor.green

    private var meBalls: [SKShapeNode] = []
    private var partnerBalls: [SKShapeNode] = []
    private var pendingSpawns = 0
    private var pendingSync: (me: [Int], partner: [Int])?

    private var pivot: CGPoint {
        CGPoint(x: size.width / 2, y: size.height - pivotFromTop)
    }

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        physicsWorld.gravity = CGVector(dx: 0, dy: -6.2)
        buildIfNeeded()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        buildIfNeeded()
        guard built else { return }
        beamNode.position = pivot
        positionBuckets()
    }

    private func buildIfNeeded() {
        guard !built, size.width > 10 else { return }
        built = true

        beamNode.position = pivot
        addChild(beamNode)

        let bar = SKShapeNode(rect: CGRect(x: -beamHalf - 2, y: -1.5, width: (beamHalf + 2) * 2, height: 3),
                              cornerRadius: 1.5)
        bar.name = "bar"
        beamNode.addChild(bar)
        for (name, x, r) in [("pivotDot", CGFloat(0), CGFloat(4)),
                             ("endL", -beamHalf, 2), ("endR", beamHalf, 2)] {
            let dot = SKShapeNode(circleOfRadius: r)
            dot.name = name
            dot.position = CGPoint(x: x, y: 0)
            beamNode.addChild(dot)
        }

        for bucket in [meBucket, partnerBucket] {
            buildBucket(bucket)
            addChild(bucket)
        }
        positionBuckets()
        restyle()
        if let pending = pendingSync {
            pendingSync = nil
            syncBalls(me: pending.me, partner: pending.partner)
        }
    }

    /// Bucket-local geometry: apex at (0,0) hangs off the beam end; strings
    /// run down to the dish rim; the dish is the design's quad arc. The
    /// physics edge follows strings + dish so balls settle in the V.
    private func bucketPath(sampled: Bool) -> CGPath {
        let path = CGMutablePath()
        let rimY: CGFloat = -46
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: -36, y: rimY))
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 36, y: rimY))
        path.move(to: CGPoint(x: -42, y: rimY))
        if sampled {
            var pts: [CGPoint] = []
            for i in 0...12 {
                let t = CGFloat(i) / 12
                let x = quad(-42, 0, 42, t)
                let y = quad(rimY, -68, rimY, t)
                pts.append(CGPoint(x: x, y: y))
            }
            for p in pts { path.addLine(to: p) }
        } else {
            path.addQuadCurve(to: CGPoint(x: 42, y: rimY), control: CGPoint(x: 0, y: -68))
        }
        return path
    }

    private func quad(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ t: CGFloat) -> CGFloat {
        (1 - t) * (1 - t) * a + 2 * (1 - t) * t * b + t * t * c
    }

    private func buildBucket(_ bucket: SKNode) {
        let vis = SKShapeNode()
        vis.name = "vis"
        vis.lineWidth = 1.4
        vis.lineCap = .round
        vis.fillColor = .clear
        bucket.addChild(vis)

        // Physics container: tall invisible side walls (slight inward lip at
        // the top) + the dish arc — one continuous concave bucket, so a full
        // pile at max tilt cannot crest or slip a joint.
        let wallPath = CGMutablePath()
        wallPath.move(to: CGPoint(x: -36, y: 40))
        wallPath.addLine(to: CGPoint(x: -45, y: 24))
        wallPath.addLine(to: CGPoint(x: -44, y: -46))
        for i in 0...12 {
            let t = CGFloat(i) / 12
            wallPath.addLine(to: CGPoint(x: quad(-42, 0, 42, t), y: quad(-46, -68, -46, t)))
        }
        wallPath.addLine(to: CGPoint(x: 44, y: -46))
        wallPath.addLine(to: CGPoint(x: 45, y: 24))
        wallPath.addLine(to: CGPoint(x: 36, y: 40))
        let walls = SKNode()
        walls.name = "walls"
        walls.physicsBody = SKPhysicsBody(edgeChainFrom: wallPath)
        walls.physicsBody?.friction = 0.9
        walls.physicsBody?.restitution = 0.1
        bucket.addChild(walls)

    }

    private func positionBuckets() {
        meBucket.position = beamEnd(sign: -1)
        partnerBucket.position = beamEnd(sign: 1)
    }

    private func beamEnd(sign: CGFloat) -> CGPoint {
        CGPoint(x: pivot.x + cos(angle) * beamHalf * sign,
                y: pivot.y + sin(angle) * beamHalf * sign)
    }

    // MARK: Styling

    func apply(ink: Color, sub: Color, me: Color, partner: Color, ghostPartner: Bool) {
        inkColor = skColor(ink)
        subColor = skColor(sub)
        meColor = skColor(me)
        partnerColor = skColor(partner)
        self.ghostPartner = ghostPartner
        restyle()
    }

    private func restyle() {
        guard built else { return }
        for node in beamNode.children {
            if let shape = node as? SKShapeNode {
                shape.fillColor = inkColor
                shape.strokeColor = inkColor
            }
        }
        for (bucket, ghost) in [(meBucket, false), (partnerBucket, ghostPartner)] {
            if let vis = bucket.childNode(withName: "vis") as? SKShapeNode {
                let base = bucketPath(sampled: false)
                vis.path = ghost ? base.copy(dashingWithPhase: 0, lengths: [3, 5]) : base
                vis.strokeColor = inkColor
                vis.alpha = ghost ? 0.45 : 1
            }
        }
        for ball in meBalls { ball.fillColor = meColor; ball.strokeColor = meColor }
        for ball in partnerBalls { ball.fillColor = partnerColor; ball.strokeColor = partnerColor }
    }

    // MARK: Tilt

    func setTilt(percentMe: Int) {
        let degrees = max(-8, min(8, (Double(percentMe) - 50) * 0.5))
        targetAngle = CGFloat(degrees * .pi / 180)
    }

    // MARK: Balls

    /// Desired ball weights per side, in completion order; the scene diffs
    /// against what it holds — new ones drop in, removed ones pop out.
    func syncBalls(me desiredMe: [Int], partner: [Int]) {
        let desiredPartner = partner
        guard built else {
            pendingSync = (desiredMe, desiredPartner)
            return
        }
        sync(side: .me, desired: Array(desiredMe.suffix(maxBallsPerSide)))
        sync(side: .partner, desired: Array(desiredPartner.suffix(maxBallsPerSide)))
    }

    private func sync(side: Side, desired: [Int]) {
        var current = side == .me ? meBalls : partnerBalls
        var desiredCounts = histogram(desired)
        let currentCounts = histogram(current.map { $0.userData?["w"] as? Int ?? 1 })

        // Removals: newest first per weight.
        for (weight, count) in currentCounts {
            let extra = count - (desiredCounts[weight] ?? 0)
            guard extra > 0 else { continue }
            var removed = 0
            for ball in current.reversed() where (ball.userData?["w"] as? Int) == weight && removed < extra {
                removed += 1
                current.removeAll { $0 === ball }
                ball.physicsBody = nil
                ball.run(.sequence([
                    .group([.fadeOut(withDuration: 0.22), .scale(to: 0.4, duration: 0.22)]),
                    .removeFromParent()
                ]))
            }
        }

        // Additions: spawn staggered so piles build up naturally.
        for (weight, count) in histogram(desired) {
            let have = current.filter { ($0.userData?["w"] as? Int) == weight }.count
            for _ in 0..<max(0, count - have) {
                let delay = Double(pendingSpawns) * 0.09
                pendingSpawns += 1
                let ball = makeBall(side: side, weight: weight)
                current.append(ball)
                run(.sequence([.wait(forDuration: delay), .run { [weak self] in
                    self?.dropIn(ball, side: side)
                    self?.pendingSpawns = max(0, (self?.pendingSpawns ?? 1) - 1)
                }]))
            }
        }
        _ = desiredCounts
        if side == .me { meBalls = current } else { partnerBalls = current }
    }

    private func histogram(_ weights: [Int]) -> [Int: Int] {
        weights.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    private func radius(for weight: Int) -> CGFloat {
        switch weight {
        case 1: return 4
        case 2: return 5.5
        default: return 7
        }
    }

    private func makeBall(side: Side, weight: Int) -> SKShapeNode {
        let ball = SKShapeNode(circleOfRadius: radius(for: weight))
        let color = side == .me ? meColor : partnerColor
        ball.fillColor = color
        ball.strokeColor = color
        ball.lineWidth = 0
        ball.userData = ["w": weight]
        return ball
    }

    private func dropIn(_ ball: SKShapeNode, side: Side) {
        guard ball.parent == nil else { return }
        let bucket = side == .me ? meBucket : partnerBucket
        let jitter = CGFloat.random(in: -16...16)
        ball.position = CGPoint(x: bucket.position.x + jitter,
                                y: bucket.position.y + CGFloat.random(in: 4...24))
        let body = SKPhysicsBody(circleOfRadius: radius(for: ball.userData?["w"] as? Int ?? 1))
        body.restitution = 0.16
        body.friction = 0.9
        body.linearDamping = 0.35
        body.density = 1
        body.usesPreciseCollisionDetection = true
        ball.physicsBody = body
        addChild(ball)
    }

    // MARK: Simulation

    override func update(_ currentTime: TimeInterval) {
        let dt: CGFloat
        if let last = lastTime { dt = CGFloat(min(currentTime - last, 1.0 / 30.0)) } else { dt = 1.0 / 60.0 }
        lastTime = currentTime

        // Critically-underdamped spring toward the target tilt.
        let k: CGFloat = 32, c: CGFloat = 6.3
        angularVel += (targetAngle - angle) * k * dt - angularVel * c * dt
        angle += angularVel * dt
        beamNode.zRotation = angle
        positionBuckets()
    }
}

// MARK: - SwiftUI wrapper

struct BeamScaleView: View {
    @Bindable var model: AppModel
    let summary: Summary
    @Environment(\.palette) private var palette
    @State private var scene: BeamPhysicsScene = {
        let scene = BeamPhysicsScene(size: CGSize(width: 390, height: 240))
        scene.scaleMode = .resizeFill
        return scene
    }()

    var body: some View {
        let meColor = model.me.map { palette.member($0.color) } ?? palette.clay
        let partnerColor = model.partner.map { palette.member($0.color) } ?? palette.teal

        GeometryReader { geo in
            let cx = geo.size.width / 2

            ZStack {
                // Pillar, base, week label — static paper furniture.
                palette.ink.frame(width: 2, height: 132).position(x: cx, y: 64 + 66)
                Capsule().fill(palette.ink).frame(width: 120, height: 2).position(x: cx, y: 196)
                Text("WK \(summary.week.index)")
                    .capsLabel(7.5, tracking: 2.4)
                    .foregroundStyle(palette.sub)
                    .padding(.horizontal, 6)
                    .background(palette.bg)
                    .position(x: cx, y: 189)

                SpriteView(scene: scene, options: [.allowsTransparency])
                    .onAppear {
                        scene.size = geo.size
                        scene.isPaused = false
                        configureScene(meColor: meColor, partnerColor: partnerColor)
                    }
                    .onDisappear { scene.isPaused = true }

                Text((model.me?.displayName ?? "You").uppercased())
                    .capsLabel(8.5, tracking: 1.7)
                    .foregroundStyle(meColor)
                    .position(x: cx - 148, y: 64 + endDrop(sign: -1) + 82)
                    .animation(.spring(response: 1.1, dampingFraction: 0.55), value: summary.percentMe)
                Text((model.partner?.displayName ?? "— ?").uppercased())
                    .capsLabel(8.5, tracking: 1.7)
                    .foregroundStyle(model.partner == nil ? AnyShapeStyle(palette.sub.opacity(0.6))
                                                          : AnyShapeStyle(partnerColor))
                    .position(x: cx + 148, y: 64 + endDrop(sign: 1) + 82)
                    .animation(.spring(response: 1.1, dampingFraction: 0.55), value: summary.percentPartner)

                RollingNumber(value: summary.percentMe)
                    .font(EvenFont.serif(34, .medium))
                    .monospacedDigit()
                    .foregroundStyle(meColor)
                    .position(x: cx - 128, y: 34)
                RollingNumber(value: summary.percentPartner)
                    .font(EvenFont.serif(34, .medium))
                    .monospacedDigit()
                    .foregroundStyle(model.partner == nil ? AnyShapeStyle(palette.sub.opacity(0.6))
                                                          : AnyShapeStyle(partnerColor))
                    .position(x: cx + 128, y: 34)
            }
            .onChange(of: summary.percentMe) { configureScene(meColor: meColor, partnerColor: partnerColor) }
            .onChange(of: summary.pebbles) { configureScene(meColor: meColor, partnerColor: partnerColor) }
            .onChange(of: palette) { configureScene(meColor: meColor, partnerColor: partnerColor) }
        }
    }

    /// Vertical drop of a beam end (SwiftUI y-down) at the settled tilt.
    private func endDrop(sign: Double) -> CGFloat {
        let degrees = max(-8, min(8, (Double(summary.percentMe) - 50) * 0.5))
        return CGFloat(-sin(degrees * .pi / 180) * 148 * sign) * -1
    }

    private func configureScene(meColor: Color, partnerColor: Color) {
        scene.apply(ink: palette.ink, sub: palette.sub,
                    me: meColor, partner: partnerColor,
                    ghostPartner: model.partner == nil)
        #if DEBUG
        if CommandLine.arguments.contains("--physics-stress") {
            scene.setTilt(percentMe: 100)
            scene.syncBalls(me: Array(repeating: 3, count: 16), partner: [])
            return
        }
        #endif
        scene.setTilt(percentMe: summary.percentMe)
        scene.syncBalls(me: weights(for: model.me?.id),
                        partner: weights(for: model.partner?.id))
    }

    private func weights(for memberId: UUID?) -> [Int] {
        guard let memberId else { return [] }
        return summary.pebbles.filter { $0.memberId == memberId }.map(\.weight)
    }
}

// MARK: - Rolling number

/// Counts through intermediate values so digit changes read as a roll.
struct RollingNumber: View {
    let value: Int
    @State private var shown: Int = 0
    @State private var roller: Task<Void, Never>?

    var body: some View {
        Text("\(shown)")
            .contentTransition(.numericText(value: Double(shown)))
            .onAppear { shown = value }
            .onChange(of: value) { _, target in
                roller?.cancel()
                let start = shown
                guard start != target else { return }
                roller = Task { @MainActor in
                    let steps = 12
                    for i in 1...steps {
                        guard !Task.isCancelled else { return }
                        // Ease-out spacing: fast start, settling finish.
                        let t = Double(i) / Double(steps)
                        let eased = 1 - pow(1 - t, 2.2)
                        withAnimation(.linear(duration: 0.045)) {
                            shown = start + Int((Double(target - start) * eased).rounded())
                        }
                        try? await Task.sleep(nanoseconds: 46_000_000)
                    }
                    withAnimation(.linear(duration: 0.04)) { shown = target }
                }
            }
    }
}
