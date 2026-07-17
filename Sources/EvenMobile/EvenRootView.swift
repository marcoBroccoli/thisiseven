import SwiftUI
import EvenCore

// Even iOS root — session routing + the app chrome per the Even Play design:
// serif wordmark with the floating scale glyph, manual dark toggle, custom
// four-item tab bar, paper grain, global ink-stamp toast.

public struct EvenRootView: View {
    @State private var session = SessionStore()
    @State private var model: AppModel?
    @AppStorage("even-dark") private var isDark = false

    public init() {}

    private var palette: EvenPalette { isDark ? .dark : .light }

    public var body: some View {
        ZStack {
            palette.bg.ignoresSafeArea()

            switch session.phase {
            case .booting:
                ProgressView().tint(palette.sub)
            case .signedOut, .needsHousehold:
                OnboardingFlow(session: session)
            case .ready:
                if let model {
                    MainScaffold(model: model, isDark: $isDark)
                }
            }

            GrainOverlay()
        }
        .environment(\.palette, palette)
        .animation(.easeInOut(duration: 0.35), value: isDark)
        .task {
            EvenFont.register()
            await session.bootstrap()
        }
        .onChange(of: session.phase) { _, phase in
            if phase == .ready, model == nil {
                model = AppModel(session: session)
            }
        }
        .preferredColorScheme(isDark ? .dark : .light)
    }
}

// MARK: - Main scaffold

struct MainScaffold: View {
    @Bindable var model: AppModel
    @Binding var isDark: Bool
    @Environment(\.palette) private var palette
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                switch model.tab {
                case .today: TodayView(model: model)
                case .inbox: InboxView(model: model)
                case .money: MoneyView(model: model)
                case .reset: ResetView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            EvenTabBar(model: model)
        }
        .overlay(alignment: .bottom) {
            if let message = model.stampMessage {
                StampToast(message: message)
                    .padding(.bottom, 110)
            }
        }
        .overlay(alignment: .top) {
            if let error = model.errorMessage {
                ErrorBanner(message: error) { model.errorMessage = nil }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: model.stampMessage)
        .task { await model.refreshAll() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refreshAll() }
            }
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 7) {
                ScaleGlyph()
                    .stroke(palette.ink, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 15, height: 15)
                Text("Even")
                    .font(EvenFont.serif(18, .semibold, italic: true))
                    .foregroundStyle(palette.ink)
            }
            Spacer()
            Button {
                isDark.toggle()
            } label: {
                Image(systemName: isDark ? "sun.max" : "moon")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.sub)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().stroke(palette.line, lineWidth: 1))
            }
            .buttonStyle(PressScaleStyle(scale: 0.9))
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

/// The little balance-scale mark: beam, pointer triangle, base.
struct ScaleGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: 0.09 * w, y: 0.42 * h))
        p.addLine(to: CGPoint(x: 0.91 * w, y: 0.29 * h))
        p.move(to: CGPoint(x: 0.5 * w, y: 0.4 * h))
        p.addLine(to: CGPoint(x: 0.66 * w, y: 0.66 * h))
        p.addLine(to: CGPoint(x: 0.34 * w, y: 0.66 * h))
        p.closeSubpath()
        p.move(to: CGPoint(x: 0.28 * w, y: 0.84 * h))
        p.addLine(to: CGPoint(x: 0.72 * w, y: 0.84 * h))
        return p
    }
}

// MARK: - Tab bar

struct EvenTabBar: View {
    @Bindable var model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            item(.today, label: "TODAY") {
                ScaleGlyph().stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 21, height: 21)
            }
            item(.inbox, label: badgeLabel) {
                Image(systemName: "tray")
                    .font(.system(size: 18, weight: .light))
            }
            item(.money, label: "MONEY") {
                CoinsGlyph().stroke(lineWidth: 1.5)
                    .frame(width: 21, height: 21)
            }
            item(.reset, label: "RESET") {
                Image(systemName: "arrow.trianglehead.clockwise")
                    .font(.system(size: 17, weight: .light))
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .background(
            palette.bg
                .overlay(alignment: .top) { palette.line.frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var badgeLabel: String {
        let count = model.summary?.pendingDraftCount ?? model.drafts.count
        return count > 0 ? "INBOX · \(count)" : "INBOX"
    }

    private func item<Icon: View>(_ tab: EvenTab, label: String,
                                  @ViewBuilder icon: () -> Icon) -> some View {
        let active = model.tab == tab
        return Button {
            model.tab = tab
            if tab == .reset {
                Task { await model.refreshReset() }
            }
        } label: {
            VStack(spacing: 4) {
                icon()
                Text(label).capsLabel(8.5, tracking: 0.9)
            }
            .foregroundStyle(active ? palette.ink : palette.sub)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.9))
    }
}

struct CoinsGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.width * 0.225
        p.addEllipse(in: CGRect(x: rect.midX - r * 1.6 - r, y: rect.midY - r, width: r * 2, height: r * 2))
        p.addEllipse(in: CGRect(x: rect.midX + r * 1.6 - r, y: rect.midY - r, width: r * 2, height: r * 2))
        return p
    }
}

// MARK: - Error banner

struct ErrorBanner: View {
    @Environment(\.palette) private var palette
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(message)
                .font(EvenFont.serif(13, italic: true))
                .foregroundStyle(palette.ink)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.sub)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Capsule().fill(palette.card).shadow(color: .black.opacity(0.12), radius: 10, y: 4))
        .overlay(Capsule().stroke(palette.line, lineWidth: 1))
        .padding(.top, 6)
        .transition(.move(edge: .top).combined(with: .opacity))
        .task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            dismiss()
        }
    }
}
