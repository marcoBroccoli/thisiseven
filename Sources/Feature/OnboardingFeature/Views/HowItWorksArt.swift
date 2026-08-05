import Design
import SwiftUI

/// How-it-works art: Design `EvenBeamScale` on weigh; static drawings for drafts / sunday.
@MainActor
enum HowItWorksArt {
    /// Shared slot height — keeps pager layout stable across pages.
    static let illustrationHeight: CGFloat = 248

    @ViewBuilder
    static func page(_ page: OnboardingReducer.State) -> some View {
        switch page {
        case .weigh:
            let beam = DesignPreviewSupport.beamScale
            EvenBeamScale(configuration: beam)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .accessibilityLabel(
                    "Balance scale showing \(beam.leading.name) at \(beam.leading.percent) percent and \(beam.trailing.name) at \(beam.trailing.percent) percent"
                )
        case .drafts:
            DraftIllustration()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .sunday:
            ResetIllustration()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - 2 · Gmail → draft → stamp

private struct DraftIllustration: View {
    private enum Timing {
        static let introPause: UInt64 = 80_000_000
        static let afterGmail: UInt64 = 300_000_000
        static let dashDraw: Double = 0.38
        static let afterDash: UInt64 = 420_000_000
        static let afterCard: UInt64 = 340_000_000
    }

    @State private var showGmail = false
    @State private var dashTop: CGFloat = 0
    @State private var showCard = false
    @State private var dashBottom: CGFloat = 0
    @State private var showStamp = false
    @State private var sequence: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 9) {
            gmailHeader
                .evenSettleIn(visible: showGmail)

            DashedDrop(progress: dashTop)

            draftCard
                .evenSettleIn(visible: showCard)

            DashedDrop(progress: dashBottom)

            approvalStamp
                .opacity(showStamp ? 1 : 0)
                .offset(y: showStamp ? 0 : EvenMotion.fadeUpOffset)
                .scaleEffect(showStamp ? 1 : 0.94)
                .animation(EvenMotion.settle, value: showStamp)
                // Room for the −2° stamp rotation so the bottom stroke isn't cut.
                .padding(.vertical, 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Gmail read-only becomes a draft water bill, then an approved task and calendar event"
        )
        .onAppear { playSequence() }
        .onDisappear {
            sequence?.cancel()
            sequence = nil
        }
    }

    private var gmailHeader: some View {
        HStack(spacing: 8) {
            EnvelopeGlyph()
                .stroke(EvenTokens.espresso, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                .frame(width: 34, height: 26)
            Text("GMAIL · READ-ONLY")
                .font(.system(size: 8.5, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(EvenTokens.stone)
        }
    }

    private var draftCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("CITY OF UTRECHT")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(EvenTokens.espresso)
                Spacer()
                Text("DRAFT")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(EvenTokens.terracotta)
            }
            Text("Water bill — €84, due Friday")
                .font(.system(size: 14.5, design: .serif))
                .foregroundStyle(EvenTokens.espresso)
            Text("NEEDS YOUR PARTNER'S OK")
                .font(.system(size: 8.5, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(EvenTokens.stone)
                .padding(.top, 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(width: 210)
        .background(RoundedRectangle(cornerRadius: 13).fill(EvenTokens.paperCard))
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(EvenTokens.espresso.opacity(0.16), lineWidth: 1.5)
        )
    }

    private var approvalStamp: some View {
        Text("APPROVED → TASK + CALENDAR")
            .font(.system(size: 10.5, weight: .bold))
            .tracking(1.5)
            .foregroundStyle(EvenTokens.espresso)
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(EvenTokens.espresso, lineWidth: 2))
            .rotationEffect(.degrees(-2))
    }

    private func playSequence() {
        sequence?.cancel()
        showGmail = false
        dashTop = 0
        showCard = false
        dashBottom = 0
        showStamp = false

        sequence = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Timing.introPause)
            guard !Task.isCancelled else { return }
            withAnimation(EvenMotion.settle) { showGmail = true }

            try? await Task.sleep(nanoseconds: Timing.afterGmail)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: Timing.dashDraw)) { dashTop = 1 }

            try? await Task.sleep(nanoseconds: Timing.afterDash)
            guard !Task.isCancelled else { return }
            withAnimation(EvenMotion.settle) { showCard = true }

            try? await Task.sleep(nanoseconds: Timing.afterCard)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: Timing.dashDraw)) { dashBottom = 1 }

            try? await Task.sleep(nanoseconds: Timing.afterDash)
            guard !Task.isCancelled else { return }
            withAnimation(EvenMotion.settle) { showStamp = true }
        }
    }
}

/// Vertical dashed connector — `progress` 0…1 draws top → bottom.
private struct DashedDrop: View {
    var progress: CGFloat

    private let height: CGFloat = 20

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(width: 1.5, height: height)
            .overlay(
                Path {
                    $0.move(to: CGPoint(x: 0.75, y: 0))
                    $0.addLine(to: CGPoint(x: 0.75, y: height))
                }
                .trim(from: 0, to: progress)
                .stroke(
                    EvenTokens.stone,
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 4])
                )
            )
    }
}

private struct EnvelopeGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRoundedRect(
            in: rect.insetBy(dx: 0.75, dy: 0.75),
            cornerSize: CGSize(width: 5, height: 5)
        )
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.06, y: rect.minY + rect.height * 0.12))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.54))
        p.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.06, y: rect.minY + rect.height * 0.12))
        return p
    }
}

// MARK: - 3 · Sunday pour

private struct ResetIllustration: View {
    private enum Layout {
        static let beamWidth: CGFloat = 210
        static let endPebble: CGFloat = 9
        static var tipX: CGFloat {
            beamWidth / 2
        }
    }

    private enum Timing {
        static let introPause: UInt64 = 80_000_000
        static let holdOnBeam: UInt64 = 380_000_000
        static let betweenTrail: UInt64 = 90_000_000
        static let beforeCaption: UInt64 = 220_000_000
    }

    /// Ghost pebbles that rain from each arm while the tip stones stay put.
    private static let trail: [PourPebble] = [
        .init(id: 0, color: EvenTokens.terracotta, size: 6, x: -78, y: 32, opacity: 0.40),
        .init(id: 1, color: EvenTokens.terracotta, size: 8, x: -58, y: 46, opacity: 0.25),
        .init(id: 2, color: EvenTokens.terracotta, size: 5, x: -70, y: 62, opacity: 0.18),
        .init(id: 3, color: EvenTokens.pine, size: 7, x: 74, y: 36, opacity: 0.35),
        .init(id: 4, color: EvenTokens.pine, size: 5, x: 52, y: 50, opacity: 0.25),
        .init(id: 5, color: EvenTokens.pine, size: 6, x: 66, y: 64, opacity: 0.16),
    ]

    @State private var showBeam = false
    @State private var pouredTrail: Set<Int> = []
    @State private var showCaption = false
    @State private var sequence: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Capsule()
                    .fill(EvenTokens.espresso)
                    .frame(width: Layout.beamWidth, height: 2)
                    .evenSettleIn(visible: showBeam)

                TriangleMark()
                    .stroke(EvenTokens.espresso, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                    .frame(width: 16, height: 11)
                    .offset(y: 8)
                    .evenSettleIn(visible: showBeam)

                // Tip pebbles stay on the arms for the whole beat.
                tipPebble(color: EvenTokens.terracotta, sign: -1)
                tipPebble(color: EvenTokens.pine, sign: 1)

                ForEach(Self.trail) { pebble in
                    trailPebble(pebble)
                }
            }
            .frame(width: Layout.beamWidth + Layout.endPebble, height: 90)

            Text("SUNDAY · 6 PM")
                .font(.system(size: 8, weight: .semibold))
                .tracking(2.5)
                .foregroundStyle(EvenTokens.stone)
                .evenSettleIn(visible: showCaption)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sunday at 6 PM — pour the pans and start the week level")
        .onAppear { playSequence() }
        .onDisappear {
            sequence?.cancel()
            sequence = nil
        }
    }

    private func tipPebble(color: Color, sign: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: Layout.endPebble, height: Layout.endPebble)
            .offset(x: sign * Layout.tipX)
            .evenSettleIn(visible: showBeam)
    }

    private func trailPebble(_ pebble: PourPebble) -> some View {
        let poured = pouredTrail.contains(pebble.id)
        return Circle()
            .fill(pebble.color)
            .frame(width: pebble.size, height: pebble.size)
            .opacity(poured ? pebble.opacity : 0)
            .offset(x: pebble.x, y: poured ? pebble.y : pebble.y - 36)
            .animation(EvenMotion.settle, value: poured)
    }

    private func playSequence() {
        sequence?.cancel()
        showBeam = false
        pouredTrail = []
        showCaption = false

        sequence = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Timing.introPause)
            guard !Task.isCancelled else { return }
            withAnimation(EvenMotion.settle) { showBeam = true }

            try? await Task.sleep(nanoseconds: Timing.holdOnBeam)
            guard !Task.isCancelled else { return }

            // Alternate left / right so both pans pour together.
            let order = [0, 3, 1, 4, 2, 5]
            for id in order {
                guard !Task.isCancelled else { return }
                withAnimation(EvenMotion.settle) { pouredTrail.insert(id) }
                try? await Task.sleep(nanoseconds: Timing.betweenTrail)
            }

            try? await Task.sleep(nanoseconds: Timing.beforeCaption)
            guard !Task.isCancelled else { return }
            withAnimation(EvenMotion.settle) { showCaption = true }
        }
    }
}

private struct PourPebble: Identifiable {
    let id: Int
    let color: Color
    let size: CGFloat
    let x: CGFloat
    let y: CGFloat
    let opacity: Double
}

private struct TriangleMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.09))
        p.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.07, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.07, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
