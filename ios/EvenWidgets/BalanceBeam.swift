import SwiftUI
import EvenCore

// A static port of the app's balance beam (Sources/EvenMobile/BeamPhysics.swift).
// Same geometry — pivot pillar, base, a tilting bar, two hanging dish buckets —
// but frozen: widgets don't animate. The tilt is derived from the week's share
// split; each bucket carries a small pile of dots for that member's done count.
struct BalanceBeam: View {
    let snapshot: EvenWidgetSnapshot
    let palette: WidgetPalette

    /// Degrees of lean, clamped to the app's ±8° range. Positive ⇒ clay heavier.
    private var leanDegrees: Double {
        let diff = Double(snapshot.clay.share - snapshot.teal.share)   // −100…100
        return max(-8, min(8, diff * 0.11))
    }

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let u = min(w / 300, h / 210)
            let cx = w / 2
            let pivotY = h * 0.24
            let beamHalf = 128 * u
            let pivot = CGPoint(x: cx, y: pivotY)

            // Static paper furniture: the pillar and its base.
            let pillarH = 118 * u
            ctx.fill(Path(CGRect(x: cx - u, y: pivotY, width: 2 * u, height: pillarH)),
                     with: .color(palette.ink))
            ctx.fill(Path(roundedRect: CGRect(x: cx - 58 * u, y: pivotY + pillarH,
                                              width: 116 * u, height: 2.4 * u),
                          cornerRadius: 1.2 * u),
                     with: .color(palette.ink))

            // The bar tilts about the pivot. Screen y grows downward, so the
            // heavier (clay/left) side must sink: rotate by −lean.
            let ang = CGFloat(-leanDegrees * .pi / 180)
            func end(_ sign: CGFloat) -> CGPoint {
                let x = sign * beamHalf
                return CGPoint(x: pivot.x + x * cos(ang), y: pivot.y + x * sin(ang))
            }
            let left = end(-1), right = end(1)

            var bar = Path()
            bar.move(to: left); bar.addLine(to: right)
            ctx.stroke(bar, with: .color(palette.ink),
                       style: StrokeStyle(lineWidth: 2.4 * u, lineCap: .round))

            // Pivot + arm-end dots.
            for (p, r) in [(pivot, 3.4 * u), (left, 2 * u), (right, 2 * u)] {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(palette.ink))
            }

            // Buckets hang vertically from the (moved) arm ends.
            drawBucket(&ctx, at: left, u: u, ghost: false,
                       dots: snapshot.clay.done, dotColor: palette.member(snapshot.clay.color))
            drawBucket(&ctx, at: right, u: u, ghost: !snapshot.hasPartner,
                       dots: snapshot.teal.done, dotColor: palette.member(snapshot.teal.color))
        }
    }

    /// A dish bucket: two strings from the apex down to the rim, a shallow
    /// quadratic dish between them, and a small settled pile of member dots.
    private func drawBucket(_ ctx: inout GraphicsContext, at apex: CGPoint, u: CGFloat,
                            ghost: Bool, dots: Int, dotColor: Color) {
        let rimY = apex.y + 40 * u
        let rimX = 30 * u
        let ctrlY = apex.y + 58 * u

        var path = Path()
        path.move(to: apex); path.addLine(to: CGPoint(x: apex.x - rimX, y: rimY))
        path.move(to: apex); path.addLine(to: CGPoint(x: apex.x + rimX, y: rimY))
        path.move(to: CGPoint(x: apex.x - rimX, y: rimY))
        path.addQuadCurve(to: CGPoint(x: apex.x + rimX, y: rimY),
                          control: CGPoint(x: apex.x, y: ctrlY))

        ctx.stroke(path, with: .color(palette.ink.opacity(ghost ? 0.5 : 1)),
                   style: StrokeStyle(lineWidth: 1.3 * u, lineCap: .round,
                                      dash: ghost ? [2.5 * u, 3.5 * u] : []))

        guard dots > 0 else { return }
        let n = min(dots, 8)
        let r = 3.0 * u
        // Settle the pile in rows along the bottom of the dish.
        for i in 0..<n {
            let row = i / 3
            let inRow = min(3, n - row * 3)
            let col = i % 3
            let dx = (CGFloat(col) - CGFloat(inRow - 1) / 2) * (r * 2.2)
            let dy = ctrlY - r * 1.3 - CGFloat(row) * (r * 1.9)
            ctx.fill(Path(ellipseIn: CGRect(x: apex.x + dx - r, y: dy - r, width: r * 2, height: r * 2)),
                     with: .color(dotColor.opacity(ghost ? 0.4 : 1)))
        }
    }
}

/// The split ring (lock accessoryCircular): a clay arc sized to the clay share,
/// a teal arc filling the rest, on a faint track.
struct SplitRing: View {
    let snapshot: EvenWidgetSnapshot
    let palette: WidgetPalette
    var lineWidth: CGFloat = 5

    private var clayFraction: CGFloat {
        let total = max(1, snapshot.clay.share + snapshot.teal.share)
        return CGFloat(snapshot.clay.share) / CGFloat(total)
    }

    var body: some View {
        ZStack {
            Circle().stroke(palette.faint, lineWidth: lineWidth)
            Circle().trim(from: 0, to: clayFraction)
                .stroke(palette.member(snapshot.clay.color),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            Circle().trim(from: clayFraction, to: 1)
                .stroke(palette.member(snapshot.teal.color).opacity(snapshot.hasPartner ? 1 : 0.4),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
    }
}
