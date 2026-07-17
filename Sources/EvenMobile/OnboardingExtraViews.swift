import SwiftUI
import EvenCore
#if canImport(UserNotifications)
import UserNotifications
#endif

// Onboarding pieces from docs/design/even-onboarding.dc.html: the code
// boxes (06/07), how-it-works illustrations (03), the invite-code reveal
// (06) and the notifications ask (10).

// MARK: - Code boxes

/// Six ticket-stub character cells. Display-only.
struct CodeBoxes: View {
    @Environment(\.palette) private var palette
    let code: String
    var isError = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<6, id: \.self) { i in
                let chars = Array(code.uppercased())
                Text(i < chars.count ? String(chars[i]) : "")
                    .font(EvenFont.serif(27, .medium))
                    .foregroundStyle(isError ? palette.clay : palette.ink)
                    .frame(width: 44, height: 58)
                    .background(RoundedRectangle(cornerRadius: 11).fill(palette.card))
                    .overlay(RoundedRectangle(cornerRadius: 11)
                        .stroke(isError ? palette.clay : palette.ink.opacity(0.2), lineWidth: 1.5))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Entry variant: boxes over a hidden text field (kept as "invite-code"
/// for the UI tests). Tapping the boxes focuses the field.
struct CodeEntryBoxes: View {
    @Binding var code: String
    var isError = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            CodeBoxes(code: code, isError: isError)
            // The real input sits on top with invisible glyphs — the boxes
            // below render the characters. Kept as "invite-code" for tests.
            TextField("", text: $code)
                .focused($focused)
                .font(.system(size: 27))
                .foregroundStyle(.clear)
                .tint(.clear)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .contentShape(Rectangle())
                .accessibilityIdentifier("invite-code")
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                #endif
                .autocorrectionDisabled()
                .onChange(of: code) { _, value in
                    let cleaned = value.uppercased().filter { $0.isLetter || $0.isNumber }
                    code = String(cleaned.prefix(6))
                }
        }
    }
}

// MARK: - 03 · how-it-works illustrations (design's 240×160 drawings)

struct HowScaleIllustration: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 240
            let ink = palette.ink
            func stroke(_ p: Path, _ w: CGFloat, _ color: Color, _ opacity: Double = 1) {
                ctx.stroke(p, with: .color(color.opacity(opacity)),
                           style: StrokeStyle(lineWidth: w * s, lineCap: .round))
            }
            // beam + pillar + base
            stroke(Path { $0.move(to: CGPoint(x: 22 * s, y: 80 * s)); $0.addLine(to: CGPoint(x: 218 * s, y: 56 * s)) }, 2.4, ink)
            ctx.fill(Path(ellipseIn: CGRect(x: 116.8 * s, y: 64.8 * s, width: 6.4 * s, height: 6.4 * s)), with: .color(ink))
            stroke(Path { $0.move(to: CGPoint(x: 120 * s, y: 68 * s)); $0.addLine(to: CGPoint(x: 120 * s, y: 132 * s)) }, 2, ink)
            stroke(Path { $0.move(to: CGPoint(x: 94 * s, y: 132 * s)); $0.addLine(to: CGPoint(x: 146 * s, y: 132 * s)) }, 2, ink)
            // left pan (heavier, lower)
            stroke(Path { $0.move(to: CGPoint(x: 26 * s, y: 80 * s)); $0.addLine(to: CGPoint(x: 10 * s, y: 114 * s)); $0.move(to: CGPoint(x: 26 * s, y: 80 * s)); $0.addLine(to: CGPoint(x: 42 * s, y: 114 * s)) }, 1.2, ink, 0.55)
            stroke(Path { $0.move(to: CGPoint(x: 4 * s, y: 114 * s)); $0.addQuadCurve(to: CGPoint(x: 48 * s, y: 114 * s), control: CGPoint(x: 26 * s, y: 130 * s)) }, 2.2, ink)
            for (x, y, r) in [(19, 110, 3.6), (27, 109, 4.2), (35, 111, 3.0), (23, 103, 3.0), (31, 102, 2.6)] {
                ctx.fill(Path(ellipseIn: CGRect(x: (CGFloat(x) - CGFloat(r)) * s, y: (CGFloat(y) - CGFloat(r)) * s,
                                                width: CGFloat(r) * 2 * s, height: CGFloat(r) * 2 * s)),
                         with: .color(palette.clay))
            }
            // right pan (lighter, higher)
            stroke(Path { $0.move(to: CGPoint(x: 214 * s, y: 56 * s)); $0.addLine(to: CGPoint(x: 198 * s, y: 90 * s)); $0.move(to: CGPoint(x: 214 * s, y: 56 * s)); $0.addLine(to: CGPoint(x: 230 * s, y: 90 * s)) }, 1.2, ink, 0.55)
            stroke(Path { $0.move(to: CGPoint(x: 192 * s, y: 90 * s)); $0.addQuadCurve(to: CGPoint(x: 236 * s, y: 90 * s), control: CGPoint(x: 214 * s, y: 106 * s)) }, 2.2, ink)
            for (x, y, r) in [(209, 86, 3.0), (217, 85, 3.4), (224, 87, 2.6)] {
                ctx.fill(Path(ellipseIn: CGRect(x: (CGFloat(x) - CGFloat(r)) * s, y: (CGFloat(y) - CGFloat(r)) * s,
                                                width: CGFloat(r) * 2 * s, height: CGFloat(r) * 2 * s)),
                         with: .color(palette.teal))
            }
        }
        .frame(width: 252, height: 168)
    }
}

struct HowDraftIllustration: View {
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                EnvelopeGlyph()
                    .stroke(palette.ink, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                    .frame(width: 34, height: 26)
                Text("GMAIL · READ-ONLY")
                    .capsLabel(8.5, tracking: 1.5)
                    .foregroundStyle(palette.sub)
            }
            dashedDrop
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("CITY OF UTRECHT")
                        .capsLabel(9, tracking: 0.7, weight: .bold)
                        .foregroundStyle(palette.ink)
                    Spacer()
                    Text("DRAFT")
                        .capsLabel(8, tracking: 0.7, weight: .bold)
                        .foregroundStyle(palette.clay)
                }
                Text("Water bill — €84, due Friday")
                    .font(EvenFont.serif(14.5))
                    .foregroundStyle(palette.ink)
                Text("NEEDS YOUR PARTNER'S OK")
                    .capsLabel(8.5, tracking: 0.5)
                    .foregroundStyle(palette.sub)
                    .padding(.top, 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(width: 210)
            .background(RoundedRectangle(cornerRadius: 13).fill(palette.card))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(palette.line, lineWidth: 1.5))
            dashedDrop
            Text("APPROVED → TASK + CALENDAR")
                .capsLabel(10.5, tracking: 1.5, weight: .bold)
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 15)
                .padding(.vertical, 8)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.ink, lineWidth: 2))
                .rotationEffect(.degrees(-2))
        }
    }

    private var dashedDrop: some View {
        Rectangle()
            .fill(.clear)
            .frame(width: 1.5, height: 20)
            .overlay(
                Path { p in
                    p.move(to: CGPoint(x: 0.75, y: 0))
                    p.addLine(to: CGPoint(x: 0.75, y: 20))
                }
                .stroke(palette.sub, style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
            )
    }
}

struct EnvelopeGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRoundedRect(in: rect.insetBy(dx: 0.75, dy: 0.75), cornerSize: CGSize(width: 5, height: 5))
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.06, y: rect.minY + rect.height * 0.12))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.54))
        p.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.06, y: rect.minY + rect.height * 0.12))
        return p
    }
}

struct HowResetIllustration: View {
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Capsule().fill(palette.ink).frame(width: 210, height: 2)
                Circle().fill(palette.clay).frame(width: 9, height: 9).offset(x: -105, y: -1)
                Circle().fill(palette.teal).frame(width: 9, height: 9).offset(x: 105, y: -1)
                Triangle()
                    .stroke(palette.ink, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                    .frame(width: 16, height: 11)
                    .offset(y: 8)
                // poured-out pebbles
                Circle().fill(palette.clay).opacity(0.40).frame(width: 6, height: 6).offset(x: -78, y: 32)
                Circle().fill(palette.clay).opacity(0.25).frame(width: 8, height: 8).offset(x: -58, y: 46)
                Circle().fill(palette.clay).opacity(0.18).frame(width: 5, height: 5).offset(x: -70, y: 62)
                Circle().fill(palette.teal).opacity(0.35).frame(width: 7, height: 7).offset(x: 74, y: 36)
                Circle().fill(palette.teal).opacity(0.25).frame(width: 5, height: 5).offset(x: 52, y: 50)
                Circle().fill(palette.teal).opacity(0.16).frame(width: 6, height: 6).offset(x: 66, y: 64)
            }
            .frame(width: 210, height: 90)
            Text("SUNDAY · 6 PM")
                .capsLabel(8, tracking: 2.5)
                .foregroundStyle(palette.sub)
        }
    }
}

// MARK: - 06 · invite code reveal

struct InviteRevealView: View {
    @Bindable var model: AppModel
    let done: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\((model.household?.name ?? "HOUSEHOLD").uppercased()) · CREATED")
                .capsLabel(10, tracking: 1.8)
                .foregroundStyle(palette.sub)
                .padding(.top, 46)

            Text("Now, your\npartner.")
                .font(EvenFont.serif(34, .medium))
                .foregroundStyle(palette.ink)
                .lineSpacing(2)
                .padding(.top, 10)

            Text("One code. It works exactly once.")
                .font(EvenFont.serif(14, italic: true))
                .foregroundStyle(palette.sub)
                .padding(.top, 12)

            CodeBoxes(code: model.household?.inviteCode ?? "")
                .padding(.top, 32)

            shareButton
                .padding(.top, 24)

            VStack(alignment: .leading, spacing: 6) {
                Text("WHAT YOUR PARTNER DOES NEXT")
                    .capsLabel(9, tracking: 1.6)
                    .foregroundStyle(palette.sub)
                Text("They install Even, choose \"Join with a code\", and type this in. The moment they land, the code retires — a household holds exactly two.")
                    .font(EvenFont.serif(14, italic: true))
                    .foregroundStyle(palette.ink)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(RoundedRectangle(cornerRadius: 13).fill(palette.faint))
            .padding(.top, 20)

            Spacer()

            HStack {
                Spacer()
                Button(action: done) {
                    Text("CONTINUE — THE CODE STAYS ON TODAY")
                        .capsLabel(10, tracking: 1.4)
                        .foregroundStyle(palette.sub)
                        .underline()
                }
                Spacer()
            }
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 28)
        .background(palette.bg.ignoresSafeArea())
    }

    private var shareButton: some View {
        ShareLink(item: "Join our household on Even — invite code \(model.household?.inviteCode ?? "")") {
            HStack(spacing: 9) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .medium))
                Text("Share the code")
                    .font(EvenFont.serif(16, .medium))
            }
            .foregroundStyle(palette.bg)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 10).fill(palette.ink))
        }
        .buttonStyle(PressScaleStyle())
    }
}

// MARK: - 10 · notifications ask

struct NotificationsPromptView: View {
    let done: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("BEFORE iOS ASKS")
                .capsLabel(10, tracking: 1.8)
                .foregroundStyle(palette.sub)
                .padding(.top, 46)

            Text("Two nudges.\nThat's all.")
                .font(EvenFont.serif(34, .medium))
                .foregroundStyle(palette.ink)
                .lineSpacing(2)
                .padding(.top, 10)

            Text("Even is quiet by design.")
                .font(EvenFont.serif(14, italic: true))
                .foregroundStyle(palette.sub)
                .padding(.top, 12)

            VStack(spacing: 14) {
                nudgeCard(icon: "arrow.clockwise",
                          title: "Sunday, 6:00 PM",
                          body: "One reminder for the weekly reset. Move it or mute it whenever you like.")
                nudgeCard(icon: "tray",
                          title: "A draft needs you",
                          body: "One ping when your partner sends something for your approval.")
            }
            .padding(.top, 30)

            Text("No streaks, no re-engagement, no guilt.")
                .font(EvenFont.serif(13, italic: true))
                .foregroundStyle(palette.sub)
                .frame(maxWidth: .infinity)
                .padding(.top, 18)

            Spacer()

            PrimaryButton(title: "Turn them on") {
                requestAuthorization()
            }
            Text("iOS WILL CONFIRM NEXT")
                .capsLabel(9, tracking: 1)
                .foregroundStyle(Color(hex: 0xB8AC99))
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
            HStack {
                Spacer()
                Button(action: done) {
                    Text("NOT NOW")
                        .capsLabel(10, tracking: 1.4)
                        .foregroundStyle(palette.sub)
                        .underline()
                }
                Spacer()
            }
            .padding(.top, 10)
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 28)
        .background(palette.bg.ignoresSafeArea())
    }

    private func nudgeCard(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.ink)
                .frame(width: 34, height: 34)
                .background(Circle().fill(palette.faint))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(EvenFont.serif(16, .medium))
                    .foregroundStyle(palette.ink)
                Text(body)
                    .font(EvenFont.serif(13.5))
                    .foregroundStyle(Color(hex: 0x6E6353))
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 15)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.card))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.line, lineWidth: 1.5))
    }

    private func requestAuthorization() {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            DispatchQueue.main.async { done() }
        }
        #else
        done()
        #endif
    }
}
