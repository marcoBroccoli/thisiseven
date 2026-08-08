#if os(iOS)
    import CoreMotion
    import SpriteKit
    import SwiftUI

    // The beam scale, made physical: the beam and its hanging buckets live in a
    // transparent SpriteKit scene; completed work drops in as balls that settle
    // under real gravity. Percentages roll numerically beside it in SwiftUI.

    /// Pebble sizing. Task weight is always **1…3** (light / medium / heavy).
    /// Fixed radii below × ``scale`` × layout scale.
    public enum EvenBeamPebbleMetrics {
        /// Allowed task-weight range (matches product heft).
        public static let weightRange = 1 ... 3

        /// Fixed radii at layoutScale 1, before ``scale``.
        public static let lightRadius: CGFloat = 6 // weight 1
        public static let mediumRadius: CGFloat = 8 // weight 2
        public static let heavyRadius: CGFloat = 10 // weight 3

        /// Multiplies every pebble (0.7 smaller, 1.0 default, 1.2 bigger).
        public static let scale: CGFloat = 0.75

        fileprivate static let dishStroke: CGFloat = 1.8
        fileprivate static var dishLift: CGFloat {
            dishStroke * 0.5 + 0.35
        }

        fileprivate static func radius(weight: Int, layoutScale u: CGFloat) -> CGFloat {
            let w = min(max(weight, weightRange.lowerBound), weightRange.upperBound)
            let base: CGFloat =
                switch w {
                case 1: lightRadius
                case 2: mediumRadius
                default: heavyRadius
                }
            return base * u * scale
        }
    }

    /// Feeds the beam's physics gravity from the phone's live tilt. The angle is
    /// clamped to ±maxTiltDegrees from straight-down so a full flip of the phone
    /// can never invert gravity — worst case at the clamp is straight sideways,
    /// never upside-down.
    @MainActor
    final class EvenBeamTiltProvider {
        static let maxTiltDegrees: Double = 90

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
    }

    #if canImport(UIKit)
        private func skColor(_ color: Color) -> SKColor {
            UIColor(color)
        }
    #else
        private func skColor(_ color: Color) -> SKColor {
            NSColor(color)
        }
    #endif

    // MARK: - Scene

    final class EvenBeamPhysicsScene: SKScene {
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

        private var u: CGFloat {
            layoutScale
        }

        private var beamHalf: CGFloat {
            148 * u
        }

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
        private var pendingSync: (me: [Int], partner: [Int])?
        private var shownPercentMe = 0
        private var shownPercentPartner = 0

        /// Fired on the main queue whenever landed weight changes (me, partner).
        var onLandedWeightsChange: ((Double, Double) -> Void)?

        private var pivot: CGPoint {
            CGPoint(x: size.width / 2, y: size.height - pivotFromTop)
        }

        private let restGravityMagnitude: CGFloat = 11
        private var tiltAngle: CGFloat = 0

        override func didMove(to _: SKView) {
            backgroundColor = .clear
            physicsWorld.gravity = CGVector(dx: 0, dy: -restGravityMagnitude)
            physicsWorld.speed = 1
            buildIfNeeded()
        }

        /// Rotates gravity itself around the beam, so a tilt of the phone reads
        /// as a tilt of "down" — the balls roll and the beam leans with it, on
        /// top of the weight-driven spring. The pans read this same angle every
        /// frame in `update` to stay plumb with it.
        func setTiltAngle(_ angle: CGFloat) {
            tiltAngle = angle
            physicsWorld.gravity = CGVector(
                dx: sin(angle) * restGravityMagnitude,
                dy: -cos(angle) * restGravityMagnitude
            )
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
            for name in [
                "bar", "pivotDot", "endL", "endR",
                "labelMe", "labelPartner", "percentMe", "percentPartner",
            ] {
                beamNode.childNode(withName: name)?.removeFromParent()
            }
            let bar = SKShapeNode(
                rect: CGRect(
                    x: -beamHalf - 2 * u, y: -1.5, width: (beamHalf + 2 * u) * 2, height: 3
                ),
                cornerRadius: 1.5
            )
            bar.name = "bar"
            beamNode.addChild(bar)
            for (name, x, r) in [
                ("pivotDot", CGFloat(0), 4 * u),
                ("endL", -beamHalf, 2 * u), ("endR", beamHalf, 2 * u),
            ] {
                let dot = SKShapeNode(circleOfRadius: r)
                dot.name = name
                dot.position = CGPoint(x: x, y: 0)
                beamNode.addChild(dot)
            }
            // Names + share % rest on the arms and ride the beam's live angle.
            for (name, x) in [("labelMe", -beamHalf * 0.55), ("labelPartner", beamHalf * 0.55)] {
                let label = SKLabelNode()
                label.name = name
                label.position = CGPoint(x: x, y: 7 * u)
                label.verticalAlignmentMode = .bottom
                label.horizontalAlignmentMode = .center
                beamNode.addChild(label)
            }
            for (name, x) in [
                ("percentMe", -beamHalf * 0.98), ("percentPartner", beamHalf * 0.98),
            ] {
                let label = SKLabelNode()
                label.name = name
                label.position = CGPoint(x: x, y: 14 * u)
                label.verticalAlignmentMode = .bottom
                label.horizontalAlignmentMode = .center
                beamNode.addChild(label)
            }
            styleArmLabels()
            stylePercentLabels()
        }

        private func styleArmLabels() {
            guard built else { return }
            let entries: [(String, String, SKColor, CGFloat)] = [
                ("labelMe", meName, meColor, 1),
                (
                    "labelPartner", partnerName, ghostPartner ? subColor : partnerColor,
                    ghostPartner ? 0.7 : 1
                ),
            ]
            for (node, text, color, alpha) in entries {
                guard let label = beamNode.childNode(withName: node) as? SKLabelNode else {
                    continue
                }
                #if canImport(UIKit)
                    let font =
                        UIFont(name: "SourceSans3-Roman_SemiBold", size: 8.5)
                            ?? UIFont.systemFont(ofSize: 8.5, weight: .semibold)
                #else
                    let font = NSFont.systemFont(ofSize: 8.5, weight: .semibold)
                #endif
                label.attributedText = NSAttributedString(
                    string: text.uppercased(),
                    attributes: [.font: font, .kern: 1.7, .foregroundColor: color]
                )
                label.alpha = alpha
            }
        }

        private func stylePercentLabels() {
            guard built else { return }
            let size = 38 * u
            let entries: [(String, Int, SKColor, CGFloat)] = [
                ("percentMe", shownPercentMe, meColor, 1),
                (
                    "percentPartner", shownPercentPartner,
                    ghostPartner ? subColor : partnerColor,
                    ghostPartner ? 0.6 : 1
                ),
            ]
            for (node, value, color, alpha) in entries {
                guard let label = beamNode.childNode(withName: node) as? SKLabelNode else {
                    continue
                }
                #if canImport(UIKit)
                    let font =
                        UIFont(name: "NewsreaderRoman-Medium", size: size)
                            ?? UIFont(name: "Newsreader", size: size)
                            ?? UIFont.systemFont(ofSize: size, weight: .medium)
                #else
                    let font =
                        NSFont(name: "NewsreaderRoman-Medium", size: size)
                            ?? NSFont.systemFont(ofSize: size, weight: .medium)
                #endif
                label.text = "\(value)"
                label.fontName = font.fontName
                label.fontSize = size
                label.fontColor = color
                label.alpha = alpha
            }
        }

        /// Drive the on-beam share labels (counts up as pebbles land).
        func setArmPercents(me: Int, partner: Int) {
            removeAction(forKey: "percentRoll")
            let startMe = shownPercentMe
            let startPartner = shownPercentPartner
            guard startMe != me || startPartner != partner else {
                stylePercentLabels()
                return
            }
            let delta = max(abs(me - startMe), abs(partner - startPartner))
            let duration = delta <= 8 ? 0.18 : min(0.45, 0.04 * Double(delta))
            let roll = SKAction.customAction(withDuration: duration) { [weak self] _, elapsed in
                guard let self else { return }
                let t = duration > 0 ? min(1, elapsed / CGFloat(duration)) : 1
                let eased = 1 - pow(1 - t, 2.2)
                self.shownPercentMe =
                    startMe + Int((Double(me - startMe) * Double(eased)).rounded())
                self.shownPercentPartner =
                    startPartner + Int((Double(partner - startPartner) * Double(eased)).rounded())
                self.stylePercentLabels()
            }
            let finish = SKAction.run { [weak self] in
                self?.shownPercentMe = me
                self?.shownPercentPartner = partner
                self?.stylePercentLabels()
            }
            run(.sequence([roll, finish]), withKey: "percentRoll")
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
                for i in 0 ... 12 {
                    let t = CGFloat(i) / 12
                    path.addLine(
                        to: CGPoint(
                            x: quad(-36 * u, 0, 36 * u, t),
                            y: quad(rimY, -66 * u, rimY, t)
                        )
                    )
                }
            } else {
                path.addQuadCurve(
                    to: CGPoint(x: 36 * u, y: rimY), control: CGPoint(x: 0, y: -66 * u)
                )
            }
            return path
        }

        private func quad(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ t: CGFloat) -> CGFloat {
            (1 - t) * (1 - t) * a + 2 * (1 - t) * t * b + t * t * c
        }

        private func buildBucket(_ bucket: SKNode) {
            let vis = SKShapeNode()
            vis.name = "vis"
            vis.lineWidth = EvenBeamPebbleMetrics.dishStroke
            vis.lineCap = .round
            vis.fillColor = .clear
            bucket.addChild(vis)

            // Sealed physics amphora: tall side walls + dish + lid. Balls spawn
            // inside (never through an open mouth), so beam sway / phone tilt /
            // pile height can never spill a pebble out of the pan.
            // Lift puts the collider on the stroke so pebble bottoms rest on the ink.
            let lift = EvenBeamPebbleMetrics.dishLift
            let lidY: CGFloat = 48 * u
            let wallPath = CGMutablePath()
            wallPath.move(to: CGPoint(x: -28 * u, y: lidY))
            wallPath.addLine(to: CGPoint(x: -39 * u, y: 24 * u))
            wallPath.addLine(to: CGPoint(x: -38 * u, y: -46 * u + lift))
            for i in 0 ... 12 {
                let t = CGFloat(i) / 12
                wallPath.addLine(
                    to: CGPoint(
                        x: quad(-36 * u, 0, 36 * u, t),
                        y: quad(-46 * u, -66 * u, -46 * u, t) + lift
                    )
                )
            }
            wallPath.addLine(to: CGPoint(x: 38 * u, y: -46 * u + lift))
            wallPath.addLine(to: CGPoint(x: 39 * u, y: 24 * u))
            wallPath.addLine(to: CGPoint(x: 28 * u, y: lidY))
            wallPath.closeSubpath()
            let walls = SKNode()
            walls.name = "walls"
            walls.physicsBody = SKPhysicsBody(edgeLoopFrom: wallPath)
            walls.physicsBody?.friction = 1.0
            walls.physicsBody?.restitution = 0.05
            walls.physicsBody?.isDynamic = false
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
            CGPoint(
                x: pivot.x + cos(angle) * beamHalf * sign,
                y: pivot.y + sin(angle) * beamHalf * sign
            )
        }

        // MARK: Styling

        func apply(
            ink: Color, sub: Color, me: Color, partner: Color, ghostPartner: Bool,
            meName: String, partnerName: String
        ) {
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
            stylePercentLabels()
            for (bucket, ghost) in [(meBucket, false), (partnerBucket, ghostPartner)] {
                if let vis = bucket.childNode(withName: "vis") as? SKShapeNode {
                    let base = bucketPath(sampled: false)
                    vis.path = ghost ? base.copy(dashingWithPhase: 0, lengths: [3, 5]) : base
                    vis.strokeColor = inkColor
                    vis.alpha = ghost ? 0.45 : 1
                }
            }
            for ball in meBalls {
                ball.fillColor = meColor
                ball.strokeColor = meColor
            }
            for ball in partnerBalls {
                ball.fillColor = partnerColor
                ball.strokeColor = partnerColor
            }
        }

        // MARK: Tilt

        func publishLandedWeights() {
            let me = landedMe
            let partner = landedPartner
            DispatchQueue.main.async { [weak self] in
                self?.onLandedWeightsChange?(me, partner)
            }
        }

        /// Degrees of tilt per unit of weight difference — tuned so each pebble
        /// visibly tips the beam as it enters (full ±8° around ~7 weight units).
        static let degreesPerWeightUnit: Double = 1.2

        private func retarget() {
            // SpriteKit: positive zRotation is counterclockwise → left arm sinks.
            // Heavier "me" (leading / left) must go down.
            let diff = landedMe - landedPartner
            let degrees = max(-8, min(8, Self.degreesPerWeightUnit * diff))
            targetAngle = CGFloat(degrees * .pi / 180)
        }

        /// Recompute pan weights from balls currently in the dishes — beam tips
        /// live as pebbles spawn/despawn, not on a delayed "landed" timer.
        private func syncWeightFromBalls() {
            var me = 0.0
            var partner = 0.0
            for ball in meBalls where ball.parent != nil {
                me += Double(ball.userData?["w"] as? Int ?? 1)
            }
            for ball in partnerBalls where ball.parent != nil {
                partner += Double(ball.userData?["w"] as? Int ?? 1)
            }
            guard me != landedMe || partner != landedPartner else { return }
            landedMe = me
            landedPartner = partner
            retarget()
            publishLandedWeights()
        }

        // MARK: Balls

        /// Desired ball weights per side; the scene diffs against what it holds —
        /// new ones drop in (shuffled order, random delays), removed ones pop out.
        func syncBalls(me desiredMe: [Int], partner: [Int]) {
            let desiredPartner = partner
            guard built else {
                pendingSync = (desiredMe, desiredPartner)
                return
            }
            let meDesired = Array(desiredMe.suffix(maxBallsPerSide))
            let partnerDesired = Array(desiredPartner.suffix(maxBallsPerSide))

            removeExtras(side: .me, desired: meDesired)
            removeExtras(side: .partner, desired: partnerDesired)

            var spawns: [(Side, Int)] = []
            spawns.append(
                contentsOf: missingWeights(side: .me, desired: meDesired).map { (.me, $0) }
            )
            spawns.append(
                contentsOf: missingWeights(side: .partner, desired: partnerDesired).map {
                    (.partner, $0)
                }
            )
            spawns.shuffle()

            // Stagger drops so the beam rebalances continuously as each pebble
            // enters — not in one late burst after almost everything has landed.
            for (index, (side, weight)) in spawns.enumerated() {
                let delay = 0.05 + Double(index) * 0.08 + Double.random(in: 0 ... 0.04)
                scheduleDrop(side: side, weight: weight, delay: delay)
            }
            syncWeightFromBalls()
        }

        private func removeExtras(side: Side, desired: [Int]) {
            var current = side == .me ? meBalls : partnerBalls
            let desiredCounts = histogram(desired)
            let currentCounts = histogram(current.map { $0.userData?["w"] as? Int ?? 1 })

            for (weight, count) in currentCounts {
                let extra = count - (desiredCounts[weight] ?? 0)
                guard extra > 0 else { continue }
                var removed = 0
                for ball in current.reversed()
                    where (ball.userData?["w"] as? Int) == weight && removed < extra
                {
                    removed += 1
                    current.removeAll { $0 === ball }
                    ball.physicsBody = nil
                    ball.run(
                        .sequence([
                            .group([.fadeOut(withDuration: 0.22), .scale(to: 0.4, duration: 0.22)]),
                            .removeFromParent(),
                        ])
                    )
                }
            }
            if side == .me { meBalls = current } else { partnerBalls = current }
            syncWeightFromBalls()
        }

        /// Weights still missing on this side (one entry per ball to spawn).
        private func missingWeights(side: Side, desired: [Int]) -> [Int] {
            let current = side == .me ? meBalls : partnerBalls
            var have = histogram(current.map { $0.userData?["w"] as? Int ?? 1 })
            var missing: [Int] = []
            for weight in desired {
                let left = have[weight, default: 0]
                if left > 0 {
                    have[weight] = left - 1
                } else {
                    missing.append(weight)
                }
            }
            return missing
        }

        private func scheduleDrop(side: Side, weight: Int, delay: TimeInterval) {
            let ball = makeBall(side: side, weight: weight)
            if side == .me { meBalls.append(ball) } else { partnerBalls.append(ball) }
            run(
                .sequence([
                    .wait(forDuration: delay),
                    .run { [weak self] in
                        self?.dropIn(ball, side: side)
                        self?.syncWeightFromBalls()
                    },
                ])
            )
        }

        private func histogram(_ weights: [Int]) -> [Int: Int] {
            weights.reduce(into: [:]) { $0[$1, default: 0] += 1 }
        }

        private func radius(for weight: Int) -> CGFloat {
            EvenBeamPebbleMetrics.radius(weight: weight, layoutScale: u)
        }

        private func makeBall(side: Side, weight: Int) -> SKShapeNode {
            let r = radius(for: weight)
            let ball = SKShapeNode(circleOfRadius: r)
            let color = side == .me ? meColor : partnerColor
            ball.fillColor = color
            ball.strokeColor = color.withAlphaComponent(0.35)
            ball.lineWidth = 1
            ball.zPosition = 10
            ball.userData = ["w": weight]
            return ball
        }

        private func dropIn(_ ball: SKShapeNode, side: Side) {
            guard ball.parent == nil else { return }
            let bucket = side == .me ? meBucket : partnerBucket
            let weight = ball.userData?["w"] as? Int ?? 1
            let r = radius(for: weight)
            // Re-path at current layout scale (ball may have been made earlier).
            ball.path = CGPath(
                ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: nil
            )
            // Parent to the pan (local space) so beam motion cannot tunnel balls
            // through the collider. Spawn under the sealed lid, above the pile.
            let maxX = max(4 * u, 14 * u - r)
            let jitter = CGFloat.random(in: -maxX ... maxX)
            ball.position = CGPoint(
                x: jitter,
                y: CGFloat.random(in: (10 * u) ... (30 * u))
            )
            ball.alpha = 0
            ball.setScale(1)
            let body = SKPhysicsBody(circleOfRadius: r)
            body.restitution = 0.08
            body.friction = 1.0
            body.linearDamping = 0.55
            body.angularDamping = 0.8
            body.density = 1.4
            body.allowsRotation = true
            body.usesPreciseCollisionDetection = true
            ball.physicsBody = body
            bucket.addChild(ball)
            ball.run(.fadeIn(withDuration: 0.12))
        }

        // MARK: Simulation

        override func update(_ currentTime: TimeInterval) {
            let dt: CGFloat
            if let last = lastTime {
                dt = CGFloat(min(currentTime - last, 1.0 / 30.0))
            } else {
                dt = 1.0 / 60.0
            }
            lastTime = currentTime

            // Live spring toward weight-driven tilt — responsive enough that
            // each pebble tips the beam as it enters, with a short settle.
            let k: CGFloat = 52
            let c: CGFloat = 7.8
            angularVel += (targetAngle - angle) * k * dt - angularVel * c * dt
            angle += angularVel * dt
            beamNode.zRotation = angle
            positionBuckets()

            // Pans swing toward plumb (the live tilt angle) a bit livelier than
            // the heavier beam, so they lag realistically instead of snapping.
            let pk: CGFloat = 46
            let pc: CGFloat = 8.5
            meBucketAngularVel +=
                (tiltAngle - meBucketAngle) * pk * dt - meBucketAngularVel * pc * dt
            meBucketAngle += meBucketAngularVel * dt
            meBucket.zRotation = meBucketAngle
            partnerBucketAngularVel +=
                (tiltAngle - partnerBucketAngle) * pk * dt - partnerBucketAngularVel * pc * dt
            partnerBucketAngle += partnerBucketAngularVel * dt
            partnerBucket.zRotation = partnerBucketAngle

            containEscapedBalls()
        }

        /// Last-resort: if a ball ever leaves the sealed amphora (tunneling),
        /// snap it back into the dish rather than letting it fall off-screen.
        private func containEscapedBalls() {
            let lidY = 48 * u
            let maxAbsX = 40 * u
            for (balls, bucket) in [(meBalls, meBucket), (partnerBalls, partnerBucket)] {
                for ball in balls where ball.parent === bucket {
                    let p = ball.position
                    if p.y > lidY - 2 * u || abs(p.x) > maxAbsX || p.y < -80 * u {
                        ball.position = CGPoint(x: 0, y: -20 * u)
                        ball.physicsBody?.velocity = .zero
                        ball.physicsBody?.angularVelocity = 0
                    }
                }
            }
        }
    }

    // MARK: - Public API

    /// Pan color vocabulary for the beam (maps to Design tokens).
    public enum EvenBeamPanTone: Equatable, Sendable {
        case clay
        case pine
        case stone
        /// A member's chosen profile colour (0xRRGGBB) — the beam follows the
        /// people on it, not the default pair.
        case custom(UInt32)

        public var color: Color {
            switch self {
            case .clay: EvenTokens.terracotta
            case .pine: EvenTokens.pine
            case .stone: EvenTokens.stone
            case let .custom(rgb): Color(hex: rgb)
            }
        }
    }

    /// One pan of the household beam — name, share %, tone, and landed pebble weights.
    public struct EvenBeamPan: Equatable, Sendable {
        public var name: String
        public var percent: Int
        public var tone: EvenBeamPanTone
        public var pebbleWeights: [Int]
        /// Dashed / faded pan when the partner hasn't joined yet.
        public var isGhost: Bool

        public init(
            name: String,
            percent: Int,
            tone: EvenBeamPanTone,
            pebbleWeights: [Int] = [],
            isGhost: Bool = false
        ) {
            self.name = name
            self.percent = percent
            self.tone = tone
            self.pebbleWeights = pebbleWeights
            self.isGhost = isGhost
        }

        public var color: Color {
            tone.color
        }
    }

    /// Configuration for ``EvenBeamScale`` — domain-agnostic (no Summary / Member).
    public struct EvenBeamScaleConfiguration: Equatable, Sendable {
        public var weekIndex: Int
        public var leading: EvenBeamPan
        public var trailing: EvenBeamPan

        public init(weekIndex: Int, leading: EvenBeamPan, trailing: EvenBeamPan) {
            self.weekIndex = weekIndex
            self.leading = leading
            self.trailing = trailing
        }
    }

    /// Physical balance beam — SpriteKit pans + SwiftUI rolling percents.
    /// Features map their domain into ``EvenBeamScaleConfiguration``.
    public struct EvenBeamScale: View {
        public var configuration: EvenBeamScaleConfiguration

        @State private var scene: EvenBeamPhysicsScene = {
            let scene = EvenBeamPhysicsScene(size: CGSize(width: 390, height: 240))
            scene.scaleMode = .resizeFill
            return scene
        }()

        @State private var tiltProvider = EvenBeamTiltProvider()
        /// Percents driven by landed pebble weight so they count up as balls settle.
        @State private var leadingPercent = 0
        @State private var trailingPercent = 0

        public init(configuration: EvenBeamScaleConfiguration) {
            self.configuration = configuration
        }

        public var body: some View {
            GeometryReader { geo in
                let cx = geo.size.width / 2
                let leading = configuration.leading
                let trailing = configuration.trailing

                ZStack {
                    EvenTokens.espresso.frame(width: 2, height: 132).position(x: cx, y: 64 + 66)
                    Capsule().fill(EvenTokens.espresso).frame(width: 120, height: 2).position(
                        x: cx, y: 196
                    )
                    Text("WEEK \(configuration.weekIndex)")
                        .font(.system(size: 7.5, weight: .semibold))
                        .tracking(2.4)
                        .foregroundStyle(EvenTokens.stone)
                        .position(x: cx, y: 210)

                    let overflowMargin: CGFloat = 90
                    let sceneSize = CGSize(
                        width: geo.size.width + overflowMargin * 2, height: geo.size.height
                    )

                    SpriteView(scene: scene, options: [.allowsTransparency])
                        .frame(width: sceneSize.width, height: sceneSize.height)
                        .position(x: cx, y: geo.size.height / 2)
                        .allowsHitTesting(false)
                        .onAppear {
                            scene.layoutScale = min(1, geo.size.width / 400)
                            scene.size = sceneSize
                            scene.isPaused = false
                            configureScene()
                            tiltProvider.start { angle in scene.setTiltAngle(angle) }
                        }
                        .onDisappear {
                            scene.isPaused = true
                            tiltProvider.stop()
                            scene.setTiltAngle(0)
                        }
                        .onChange(of: geo.size.width) { _, newWidth in
                            let newSize = CGSize(
                                width: newWidth + overflowMargin * 2, height: geo.size.height
                            )
                            scene.layoutScale = min(1, newWidth / 400)
                            scene.size = newSize
                        }

                    Color.clear.frame(width: 1, height: 1)
                        .position(x: cx - 100, y: 40)
                        .accessibilityLabel("\(leading.name), \(leadingPercent) percent")
                        .accessibilityAddTraits(.isStaticText)
                    Color.clear.frame(width: 1, height: 1)
                        .position(x: cx + 100, y: 40)
                        .accessibilityLabel("\(trailing.name), \(trailingPercent) percent")
                        .accessibilityAddTraits(.isStaticText)
                }
                .onChange(of: configuration) { configureScene() }
            }
        }

        private func configureScene() {
            let leading = configuration.leading
            let trailing = configuration.trailing
            scene.onLandedWeightsChange = { [self] me, partner in
                updateDisplayedPercents(landedMe: me, landedPartner: partner)
            }
            scene.apply(
                ink: EvenTokens.espresso,
                sub: EvenTokens.stone,
                me: leading.color,
                partner: trailing.color,
                ghostPartner: trailing.isGhost,
                meName: leading.name,
                partnerName: trailing.name
            )
            scene.syncBalls(me: leading.pebbleWeights, partner: trailing.pebbleWeights)
            scene.publishLandedWeights()
        }

        private func updateDisplayedPercents(landedMe: Double, landedPartner: Double) {
            let expectedMe = Double(configuration.leading.pebbleWeights.reduce(0, +))
            let expectedPartner = Double(configuration.trailing.pebbleWeights.reduce(0, +))
            let targetLeading = configuration.leading.percent
            let targetTrailing = configuration.trailing.percent

            let nextLeading: Int
            let nextTrailing: Int

            // No pebbles → show the configured share immediately.
            if expectedMe == 0, expectedPartner == 0 {
                nextLeading = targetLeading
                nextTrailing = targetTrailing
            } else {
                let leadingProgress = expectedMe > 0 ? min(1, landedMe / expectedMe) : 1
                let trailingProgress =
                    expectedPartner > 0
                        ? min(1, landedPartner / expectedPartner)
                        : (configuration.trailing.isGhost ? 0 : 1)

                if landedMe >= expectedMe, landedPartner >= expectedPartner {
                    nextLeading = targetLeading
                    nextTrailing = targetTrailing
                } else {
                    nextLeading = Int((Double(targetLeading) * leadingProgress).rounded())
                    nextTrailing = Int((Double(targetTrailing) * trailingProgress).rounded())
                }
            }

            leadingPercent = nextLeading
            trailingPercent = nextTrailing
            scene.setArmPercents(me: nextLeading, partner: nextTrailing)
        }
    }

    #Preview("EvenBeamScale") {
        EvenBeamScale(configuration: DesignPreviewSupport.beamScale)
            .frame(height: 240)
            .padding()
            .evenPaperBackground()
    }

#else

    import SwiftUI

    /// watchOS / non-iOS stub — beam physics is iPhone-only.
    public enum EvenBeamPanTone: Equatable, Sendable {
        case clay, pine, stone
        case custom(UInt32)
        public var color: Color {
            switch self {
            case .clay: EvenTokens.terracotta
            case .pine: EvenTokens.pine
            case .stone: EvenTokens.stone
            case let .custom(rgb): Color(hex: rgb)
            }
        }
    }

    public struct EvenBeamPan: Equatable, Sendable {
        public var name: String
        public var percent: Int
        public var tone: EvenBeamPanTone
        public var pebbleWeights: [Int]
        public var isGhost: Bool

        public init(
            name: String,
            percent: Int,
            tone: EvenBeamPanTone,
            pebbleWeights: [Int] = [],
            isGhost: Bool = false
        ) {
            self.name = name
            self.percent = percent
            self.tone = tone
            self.pebbleWeights = pebbleWeights
            self.isGhost = isGhost
        }

        public var color: Color {
            tone.color
        }
    }

    public struct EvenBeamScaleConfiguration: Equatable, Sendable {
        public var weekIndex: Int
        public var leading: EvenBeamPan
        public var trailing: EvenBeamPan

        public init(weekIndex: Int, leading: EvenBeamPan, trailing: EvenBeamPan) {
            self.weekIndex = weekIndex
            self.leading = leading
            self.trailing = trailing
        }
    }

    public struct EvenBeamScale: View {
        public var configuration: EvenBeamScaleConfiguration

        public init(configuration: EvenBeamScaleConfiguration) {
            self.configuration = configuration
        }

        public var body: some View {
            Text(
                "WEEK \(configuration.weekIndex) · \(configuration.leading.percent)/\(configuration.trailing.percent)"
            )
            .font(.system(size: 14, design: .serif))
            .foregroundStyle(EvenTokens.stone)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

#endif
