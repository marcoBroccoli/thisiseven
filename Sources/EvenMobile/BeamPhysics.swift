import SwiftUI
import SpriteKit
#if os(iOS)
import CoreMotion
#endif
import EvenCore

// The beam scale, made physical: the beam and its hanging buckets live in a
// transparent SpriteKit scene; completed work drops in as balls that settle
// under real gravity. Percentages roll numerically beside it in SwiftUI.

/// Feeds the beam's physics gravity from the phone's live tilt. The angle is
/// clamped to ±maxTiltDegrees from straight-down so a full flip of the phone
/// can never invert gravity — worst case at the clamp is straight sideways,
/// never upside-down.
@MainActor
final class TiltGravityProvider {
    static let maxTiltDegrees: Double = 90

    #if os(iOS)
    private let manager = CMMotionManager()

    func start(onTilt: @escaping (CGFloat) -> Void) {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { motion, _ in
            guard let g = motion?.gravity else { return }
            let degrees = atan2(g.x, -g.y) * 180 / .pi
            let clamped = max(-Self.maxTiltDegrees, min(Self.maxTiltDegrees, degrees))
            onTilt(CGFloat(clamped * .pi / 180))
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
    #else
    func start(onTilt: @escaping (CGFloat) -> Void) {}
    func stop() {}
    #endif
}

#if canImport(UIKit)
private func skColor(_ color: Color) -> SKColor { UIColor(color) }
#else
private func skColor(_ color: Color) -> SKColor { NSColor(color) }
#endif

// MARK: - Scene

final class BeamPhysicsScene: SKScene {
    enum Side { case me, partner }

    /// Uniform layout scale so the whole assembly fits the container width.
    /// The scene can build before SwiftUI delivers the real width (didMove
    /// fires with the init size), so a later change rebuilds all geometry —
    /// visual AND physics stay one truth. (The collider-sunk-balls bug was
    /// exactly this: walls built at scale 1, visuals restyled at 0.905.)
    var layoutScale: CGFloat = 1 {
        didSet {
            guard built, layoutScale != oldValue else { return }
            rebuildGeometry()
        }
    }
    private var u: CGFloat { layoutScale }
    private var beamHalf: CGFloat { 148 * u }
    private let pivotFromTop: CGFloat = 64
    private let maxBallsPerSide = 16

    // Spring toward the target tilt (matches the old SwiftUI spring feel).
    // The target is derived ONLY from weight that has physically landed —
    // the beam never leans ahead of its balls.
    private var targetAngle: CGFloat = 0
    private var landedMe: Double = 0
    private var landedPartner: Double = 0
    private var angle: CGFloat = 0
    private var angularVel: CGFloat = 0

    // Each pan hangs off the beam like a real one: it swings to stay plumb
    // with whatever direction gravity currently points, independent of the
    // beam's own tilt. Without this the pan's bowl stays scene-upright while
    // gravity swings sideways, so balls roll straight out over the rim.
    private var meBucketAngle: CGFloat = 0
    private var meBucketAngularVel: CGFloat = 0
    private var partnerBucketAngle: CGFloat = 0
    private var partnerBucketAngularVel: CGFloat = 0
    private var lastTime: TimeInterval?

    private let beamNode = SKNode()
    private var meName = "YOU"
    private var partnerName = "\u{2014} ?"
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

    private let restGravityMagnitude: CGFloat = 6.2
    private var tiltAngle: CGFloat = 0

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        physicsWorld.gravity = CGVector(dx: 0, dy: -restGravityMagnitude)
        buildIfNeeded()
    }

    /// Rotates gravity itself around the beam, so a tilt of the phone reads
    /// as a tilt of "down" — the balls roll and the beam leans with it, on
    /// top of the weight-driven spring. The pans read this same angle every
    /// frame in `update` to stay plumb with it.
    func setTiltAngle(_ angle: CGFloat) {
        tiltAngle = angle
        physicsWorld.gravity = CGVector(dx: sin(angle) * restGravityMagnitude,
                                        dy: -cos(angle) * restGravityMagnitude)
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

        buildBeamParts()

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

    private func buildBeamParts() {
        for name in ["bar", "pivotDot", "endL", "endR", "labelMe", "labelPartner"] {
            beamNode.childNode(withName: name)?.removeFromParent()
        }
        let bar = SKShapeNode(rect: CGRect(x: -beamHalf - 2 * u, y: -1.5, width: (beamHalf + 2 * u) * 2, height: 3),
                              cornerRadius: 1.5)
        bar.name = "bar"
        beamNode.addChild(bar)
        for (name, x, r) in [("pivotDot", CGFloat(0), 4 * u),
                             ("endL", -beamHalf, 2 * u), ("endR", beamHalf, 2 * u)] {
            let dot = SKShapeNode(circleOfRadius: r)
            dot.name = name
            dot.position = CGPoint(x: x, y: 0)
            beamNode.addChild(dot)
        }
        // Member names rest along the arms and ride the beam's live angle.
        for (name, x) in [("labelMe", -beamHalf * 0.55), ("labelPartner", beamHalf * 0.55)] {
            let label = SKLabelNode()
            label.name = name
            label.position = CGPoint(x: x, y: 7 * u)
            label.verticalAlignmentMode = .bottom
            label.horizontalAlignmentMode = .center
            beamNode.addChild(label)
        }
        styleArmLabels()
    }

    private func styleArmLabels() {
        guard built else { return }
        let entries: [(String, String, SKColor, CGFloat)] = [
            ("labelMe", meName, meColor, 1),
            ("labelPartner", partnerName, ghostPartner ? subColor : partnerColor, ghostPartner ? 0.7 : 1)
        ]
        for (node, text, color, alpha) in entries {
            guard let label = beamNode.childNode(withName: node) as? SKLabelNode else { continue }
            #if canImport(UIKit)
            let font = UIFont(name: "SourceSans3-Roman_SemiBold", size: 8.5)
                ?? UIFont.systemFont(ofSize: 8.5, weight: .semibold)
            #else
            let font = NSFont.systemFont(ofSize: 8.5, weight: .semibold)
            #endif
            label.attributedText = NSAttributedString(
                string: text.uppercased(),
                attributes: [.font: font, .kern: 1.7, .foregroundColor: color])
            label.alpha = alpha
        }
    }

    /// Rebuild everything geometric after a layout-scale change: beam parts,
    /// bucket visuals, wall bodies, debug overlays. Balls keep living.
    private func rebuildGeometry() {
        buildBeamParts()
        for bucket in [meBucket, partnerBucket] {
            bucket.childNode(withName: "vis")?.removeFromParent()
            bucket.childNode(withName: "walls")?.removeFromParent()
            bucket.childNode(withName: "debug-overlay")?.removeFromParent()
            buildBucket(bucket)
        }
        beamNode.position = pivot
        positionBuckets()
        restyle()
    }

    /// Bucket-local geometry: apex at (0,0) hangs off the beam end; strings
    /// run down to the dish rim; the dish arc terminates EXACTLY at the
    /// string endpoints (±36u) — no overhanging tips at tilt.
    private func bucketPath(sampled: Bool) -> CGPath {
        let path = CGMutablePath()
        let rimY: CGFloat = -46 * u
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: -36 * u, y: rimY))
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 36 * u, y: rimY))
        path.move(to: CGPoint(x: -36 * u, y: rimY))
        if sampled {
            for i in 0...12 {
                let t = CGFloat(i) / 12
                path.addLine(to: CGPoint(x: quad(-36 * u, 0, 36 * u, t),
                                         y: quad(rimY, -66 * u, rimY, t)))
            }
        } else {
            path.addQuadCurve(to: CGPoint(x: 36 * u, y: rimY), control: CGPoint(x: 0, y: -66 * u))
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
        let lift: CGFloat = 0.7   // half the 1.4pt stroke: balls kiss the line's top
        let wallPath = CGMutablePath()
        wallPath.move(to: CGPoint(x: -30 * u, y: 40 * u))
        wallPath.addLine(to: CGPoint(x: -39 * u, y: 24 * u))
        wallPath.addLine(to: CGPoint(x: -38 * u, y: -46 * u + lift))
        for i in 0...12 {
            let t = CGFloat(i) / 12
            wallPath.addLine(to: CGPoint(x: quad(-36 * u, 0, 36 * u, t),
                                         y: quad(-46 * u, -66 * u, -46 * u, t) + lift))
        }
        wallPath.addLine(to: CGPoint(x: 38 * u, y: -46 * u + lift))
        wallPath.addLine(to: CGPoint(x: 39 * u, y: 24 * u))
        wallPath.addLine(to: CGPoint(x: 30 * u, y: 40 * u))
        let walls = SKNode()
        walls.name = "walls"
        walls.physicsBody = SKPhysicsBody(edgeChainFrom: wallPath)
        walls.physicsBody?.friction = 0.9
        walls.physicsBody?.restitution = 0.1
        bucket.addChild(walls)

        #if DEBUG
        if CommandLine.arguments.contains("--physics-debug") {
            let overlay = SKShapeNode(path: wallPath)
            overlay.name = "debug-overlay"
            overlay.strokeColor = .red
            overlay.lineWidth = 1
            overlay.alpha = 0.85
            overlay.zPosition = 50
            bucket.addChild(overlay)
        }
        #endif
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

    func apply(ink: Color, sub: Color, me: Color, partner: Color, ghostPartner: Bool,
               meName: String, partnerName: String) {
        inkColor = skColor(ink)
        subColor = skColor(sub)
        meColor = skColor(me)
        partnerColor = skColor(partner)
        self.ghostPartner = ghostPartner
        self.meName = meName
        self.partnerName = partnerName
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
        styleArmLabels()
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

    private func landed(side: Side, weight: Int) {
        if side == .me { landedMe += Double(weight) } else { landedPartner += Double(weight) }
        retarget()
    }

    private func unlanded(side: Side, weight: Int) {
        if side == .me { landedMe = max(0, landedMe - Double(weight)) }
        else { landedPartner = max(0, landedPartner - Double(weight)) }
        retarget()
    }

    /// Degrees of tilt per unit of landed weight difference: every ball
    /// landing sinks its side a visible step further (~6-7 units of
    /// difference traverse the full ±8° range), instead of the old ratio
    /// formula that hit the clamp on the very first solo ball.
    static let degreesPerWeightUnit: Double = 1.2

    private func retarget() {
        let diff = landedMe - landedPartner
        let degrees = max(-8, min(8, Self.degreesPerWeightUnit * diff))
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
                if ball.parent != nil { unlanded(side: side, weight: weight) }
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
                let ballWeight = weight
                run(.sequence([.wait(forDuration: delay), .run { [weak self] in
                    self?.dropIn(ball, side: side)
                    self?.pendingSpawns = max(0, (self?.pendingSpawns ?? 1) - 1)
                }, .wait(forDuration: 0.42), .run { [weak self] in
                    guard ball.parent != nil else { return }
                    self?.landed(side: side, weight: ballWeight)
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
        case 1: return 4 * u
        case 2: return 5.5 * u
        default: return 7 * u
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
        let jitter = CGFloat.random(in: (-16 * u)...(16 * u))
        ball.position = CGPoint(x: bucket.position.x + jitter,
                                y: bucket.position.y + CGFloat.random(in: (4 * u)...(24 * u)))
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

        // Pans swing toward plumb (the live tilt angle) a bit livelier than
        // the heavier beam, so they lag realistically instead of snapping.
        let pk: CGFloat = 46, pc: CGFloat = 8.5
        meBucketAngularVel += (tiltAngle - meBucketAngle) * pk * dt - meBucketAngularVel * pc * dt
        meBucketAngle += meBucketAngularVel * dt
        meBucket.zRotation = meBucketAngle
        partnerBucketAngularVel += (tiltAngle - partnerBucketAngle) * pk * dt - partnerBucketAngularVel * pc * dt
        partnerBucketAngle += partnerBucketAngularVel * dt
        partnerBucket.zRotation = partnerBucketAngle
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
    @State private var tiltProvider = TiltGravityProvider()

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

                // A swung-out pan reaches well past the beam's resting
                // footprint, so the render surface needs to be wider than
                // the card itself — sized around the same `cx` center — or
                // a hard tilt clips the pan against the card's own edge.
                let overflowMargin: CGFloat = 90
                let sceneSize = CGSize(width: geo.size.width + overflowMargin * 2, height: geo.size.height)

                SpriteView(scene: scene, options: [.allowsTransparency])
                    .frame(width: sceneSize.width, height: sceneSize.height)
                    .position(x: cx, y: geo.size.height / 2)
                    .allowsHitTesting(false)
                    .onAppear {
                        scene.layoutScale = min(1, geo.size.width / 400)
                        scene.size = sceneSize
                        scene.isPaused = false
                        configureScene(meColor: meColor, partnerColor: partnerColor)
                        tiltProvider.start { angle in scene.setTiltAngle(angle) }
                    }
                    .onDisappear {
                        scene.isPaused = true
                        tiltProvider.stop()
                        scene.setTiltAngle(0)
                    }
                    .onChange(of: geo.size.width) { _, newWidth in
                        let newSize = CGSize(width: newWidth + overflowMargin * 2, height: geo.size.height)
                        scene.layoutScale = min(1, newWidth / 400)
                        scene.size = newSize
                    }

                // Names render in-scene on the beam arms; these invisible
                // statics keep VoiceOver + the E2E name assertions alive.
                Color.clear.frame(width: 1, height: 1)
                    .position(x: cx - 100, y: 40)
                    .accessibilityLabel((model.me?.displayName ?? "You").uppercased())
                    .accessibilityAddTraits(.isStaticText)
                Color.clear.frame(width: 1, height: 1)
                    .position(x: cx + 100, y: 40)
                    .accessibilityLabel((model.partner?.displayName ?? "— ?").uppercased())
                    .accessibilityAddTraits(.isStaticText)

                RollingNumber(value: summary.percentMe)
                    .font(EvenFont.serif(34, .medium))
                    .monospacedDigit()
                    .foregroundStyle(meColor)
                    .position(x: cx - 128 * unit(geo), y: 34)
                RollingNumber(value: summary.percentPartner)
                    .font(EvenFont.serif(34, .medium))
                    .monospacedDigit()
                    .foregroundStyle(model.partner == nil ? AnyShapeStyle(palette.sub.opacity(0.6))
                                                          : AnyShapeStyle(partnerColor))
                    .position(x: cx + 128 * unit(geo), y: 34)
            }
            .onChange(of: summary.percentMe) { configureScene(meColor: meColor, partnerColor: partnerColor) }
            .onChange(of: summary.pebbles) { configureScene(meColor: meColor, partnerColor: partnerColor) }
            .onChange(of: palette) { configureScene(meColor: meColor, partnerColor: partnerColor) }
        }
    }

    private func unit(_ geo: GeometryProxy) -> CGFloat {
        min(1, geo.size.width / 400)
    }

    private func configureScene(meColor: Color, partnerColor: Color) {
        scene.apply(ink: palette.ink, sub: palette.sub,
                    me: meColor, partner: partnerColor,
                    ghostPartner: model.partner == nil,
                    meName: model.me?.displayName ?? "You",
                    partnerName: model.partner?.displayName ?? "\u{2014} ?")
        #if DEBUG
        if let idx = CommandLine.arguments.firstIndex(of: "--physics-stress") {
            // Optional trailing count: `--physics-stress 3` drops that many
            // max-weight balls (default 16 = the containment stress).
            let count = CommandLine.arguments.dropFirst(idx + 1).first.flatMap(Int.init) ?? 16
            scene.syncBalls(me: Array(repeating: 3, count: count), partner: [])
            return
        }
        #endif
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
