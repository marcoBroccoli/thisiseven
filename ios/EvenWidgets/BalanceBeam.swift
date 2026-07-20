import SwiftUI
import EvenCore

// The original Even balance beam, ported to a 100×100 design space and scaled to
// fit whatever frame the widget gives it. A tilting arm carries two hanging bowls
// with member discs (ADA left / UMUT right). +tilt ⇒ the heavier ADA (left) pan
// dips. Frozen — widgets don't animate.
struct BalanceBeam: View {
    let snapshot: EvenWidgetSnapshot
    let palette: WidgetPalette

    // Exact geometry parameters (100×100 space).
    private let cx: CGFloat = 50
    private let pivotY: CGFloat = 40
    private let arm: CGFloat = 32
    private let hang: CGFloat = 13
    private let bowl: CGFloat = 7
    private let disc: CGFloat = 5
    private let baseY: CGFloat = 84
    private let stroke: CGFloat = 2.6

    private var adaShare: Int { snapshot.clay.share }

    /// tilt = clamp(-24, 24, (adaShare-50)*0.7) degrees.
    private var tilt: CGFloat {
        max(-24, min(24, CGFloat(adaShare - 50) * 0.7))
    }

    var body: some View {
        Canvas { ctx, size in
            // Fit the 100×100 space, centred, preserving aspect.
            let s = min(size.width, size.height) / 100
            ctx.translateBy(x: (size.width - 100 * s) / 2, y: (size.height - 100 * s) / 2)
            ctx.scaleBy(x: s, y: s)

            let ink = palette.beamInk
            let t = tilt * .pi / 180
            let ct = cos(t), st = sin(t)

            // Arm ends (screen y grows downward → +st lowers the left pan).
            let Lx = 50 - arm * ct, Ly = 40 + arm * st
            let Rx = 50 + arm * ct, Ry = 40 - arm * st
            let La = Ly + hang, Ra = Ry + hang

            func line(_ a: CGPoint, _ b: CGPoint, _ w: CGFloat, _ color: Color) {
                var p = Path(); p.move(to: a); p.addLine(to: b)
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: w, lineCap: .round))
            }
            func dot(_ c: CGPoint, _ r: CGFloat, _ color: Color) {
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .color(color))
            }

            // Base line.
            line(CGPoint(x: 28, y: baseY), CGPoint(x: 72, y: baseY), stroke, ink)

            // Stand triangle: M50,40 L56,84 L44,84 (stroke, no fill, round join).
            var stand = Path()
            stand.move(to: CGPoint(x: 50, y: 40))
            stand.addLine(to: CGPoint(x: 56, y: baseY))
            stand.addLine(to: CGPoint(x: 44, y: baseY))
            ctx.stroke(stand, with: .color(ink),
                       style: StrokeStyle(lineWidth: stroke, lineJoin: .round))

            // Beam.
            line(CGPoint(x: Lx, y: Ly), CGPoint(x: Rx, y: Ry), stroke, ink)

            // Pivot dot.
            dot(CGPoint(x: 50, y: 40), 2.3, ink)

            // Pans (hanger + bowl + disc + initial). Right pan ghosts when solo.
            drawPan(&ctx, ax: Lx, ay: Ly, anchorY: La, ink: ink,
                    color: palette.member(snapshot.clay.color),
                    initial: snapshot.clay.initial, ghost: false)
            drawPan(&ctx, ax: Rx, ay: Ry, anchorY: Ra, ink: ink,
                    color: palette.member(snapshot.teal.color),
                    initial: snapshot.teal.initial, ghost: !snapshot.hasPartner)
        }
    }

    private func drawPan(_ ctx: inout GraphicsContext, ax: CGFloat, ay: CGFloat, anchorY: CGFloat,
                         ink: Color, color: Color, initial: String, ghost: Bool) {
        let inkC = ink.opacity(ghost ? 0.35 : 1)

        // Hanger (thinner).
        var hanger = Path()
        hanger.move(to: CGPoint(x: ax, y: ay)); hanger.addLine(to: CGPoint(x: ax, y: anchorY))
        ctx.stroke(hanger, with: .color(inkC),
                   style: StrokeStyle(lineWidth: stroke * 0.7, lineCap: .round))

        // Bowl: downward half-circle arc, radius `bowl`, centred at (ax, anchorY).
        var arc = Path()
        arc.addArc(center: CGPoint(x: ax, y: anchorY), radius: bowl,
                   startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        ctx.stroke(arc, with: .color(inkC),
                   style: StrokeStyle(lineWidth: stroke, lineCap: .round))

        // Disc + initial (disc centre one unit above the bowl centre).
        let dc = CGPoint(x: ax, y: anchorY - 1)
        ctx.fill(Path(ellipseIn: CGRect(x: dc.x - disc, y: dc.y - disc, width: disc * 2, height: disc * 2)),
                 with: .color(color.opacity(ghost ? 0.4 : 1)))
        let label = Text(initial)
            .font(WidgetFont.sans(6, .bold))
            .foregroundStyle(WT.cream.opacity(ghost ? 0.7 : 1))
        ctx.draw(label, at: dc, anchor: .center)
    }
}

/// The split ring: a faint full track, the ADA arc sized to the ADA share
/// starting at the top (−90°), and the UMUT arc filling the remainder. Optional
/// centre content (a mini beam, the share number, or nothing).
struct SplitRing: View {
    let snapshot: EvenWidgetSnapshot
    var lineWidth: CGFloat = 5
    var center: Center = .none

    enum Center { case none, miniBeam, number }

    private var adaFraction: CGFloat {
        let total = max(1, snapshot.clay.share + snapshot.teal.share)
        return CGFloat(snapshot.clay.share) / CGFloat(total)
    }

    var body: some View {
        ZStack {
            Circle().stroke(WT.ringTrack, lineWidth: lineWidth)
            Circle().trim(from: 0, to: adaFraction)
                .stroke(WT.ada, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            Circle().trim(from: adaFraction, to: 1)
                .stroke(WT.umut.opacity(snapshot.hasPartner ? 1 : 0.4),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            centerContent
        }
        .padding(lineWidth / 2)
    }

    @ViewBuilder private var centerContent: some View {
        switch center {
        case .none:
            EmptyView()
        case .number:
            Text("\(snapshot.clay.share)")
                .font(WidgetFont.serif(15, .medium))
                .minimumScaleFactor(0.6)
        case .miniBeam:
            MiniBeam(tiltShare: snapshot.clay.share)
                .padding(lineWidth + 2)
        }
    }
}

/// A thin cream mini-beam for the ring centre (tilts with the ADA share).
struct MiniBeam: View {
    let tiltShare: Int
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let cx = w / 2, cy = h * 0.5
            let arm = w * 0.36
            let tilt = max(-24, min(24, CGFloat(tiltShare - 50) * 0.7)) * .pi / 180
            let ct = cos(tilt), st = sin(tilt)
            Path { p in
                // stand
                p.move(to: CGPoint(x: cx, y: cy))
                p.addLine(to: CGPoint(x: cx, y: h * 0.9))
                // beam
                p.move(to: CGPoint(x: cx - arm * ct, y: cy + arm * st))
                p.addLine(to: CGPoint(x: cx + arm * ct, y: cy - arm * st))
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: max(1, w * 0.05), lineCap: .round))
        }
    }
}
