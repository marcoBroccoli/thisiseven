import SwiftUI
import EvenCore

// Even iOS root — native structure (system TabView, SF Symbols, system
// motion) wearing the Even Play design language: paper ground, serif
// wordmark chrome, grain, ink-stamp toasts.

public struct EvenRootView: View {
    @State private var session = SessionStore()
    @State private var model: AppModel?
    @State private var splashHoldDone = false
    @AppStorage("even-dark") private var isDark = false

    public init() {}

    private var palette: EvenPalette { isDark ? .dark : .light }

    private var showSplash: Bool {
        !splashHoldDone || session.phase == .booting
    }

    public var body: some View {
        ZStack {
            palette.bg.ignoresSafeArea()

            ZStack {
                if showSplash {
                    SplashView()
                        .transition(.opacity)
                } else {
                    switch session.phase {
                    case .booting:
                        EmptyView()
                    case .signedOut, .needsHousehold:
                        OnboardingFlow(session: session)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    case .ready:
                        if let model {
                            MainScaffold(model: model, isDark: $isDark)
                                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.4), value: session.phase)
            .animation(.easeInOut(duration: 0.4), value: showSplash)

            GrainOverlay()
        }
        .environment(\.palette, palette)
        .animation(.easeInOut(duration: 0.35), value: isDark)
        .task {
            EvenFont.register()
            let holdUntil = Date().addingTimeInterval(1.0)
            await session.bootstrap()
            // Returning users get a breath of splash; a signed-out launch
            // cuts straight to the welcome screen's own choreography.
            if session.phase != .signedOut {
                let remaining = holdUntil.timeIntervalSinceNow
                if remaining > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                }
            }
            splashHoldDone = true
        }
        .onChange(of: session.phase) { _, phase in
            if phase == .ready, model == nil {
                model = AppModel(session: session)
            }
        }
        .preferredColorScheme(isDark ? .dark : .light)
    }
}

// MARK: - Splash

/// 01 · Splash — the glyph assembles element by element (beam draws,
/// pointer appears, base draws), then the wordmark lands.
struct SplashView: View {
    @Environment(\.palette) private var palette
    @State private var glyphProgress: CGFloat = 0
    @State private var showWordmark = false

    var body: some View {
        VStack(spacing: 12) {
            ScaleGlyph()
                .trim(from: 0, to: glyphProgress)
                .stroke(palette.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 52, height: 52)
            Text("Even")
                .font(EvenFont.serif(34, .semibold, italic: true))
                .foregroundStyle(palette.ink)
                .opacity(showWordmark ? 1 : 0)
                .offset(y: showWordmark ? 0 : 8)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.65)) { glyphProgress = 1 }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.45)) {
                showWordmark = true
            }
        }
    }
}

/// The glyph split into its three strokes so the splash can draw them in turn.
struct GlyphBeam: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.09 * rect.width, y: 0.42 * rect.height))
        p.addLine(to: CGPoint(x: 0.91 * rect.width, y: 0.29 * rect.height))
        return p
    }
}

struct GlyphTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.5 * rect.width, y: 0.4 * rect.height))
        p.addLine(to: CGPoint(x: 0.66 * rect.width, y: 0.66 * rect.height))
        p.addLine(to: CGPoint(x: 0.34 * rect.width, y: 0.66 * rect.height))
        p.closeSubpath()
        return p
    }
}

struct GlyphBase: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.28 * rect.width, y: 0.84 * rect.height))
        p.addLine(to: CGPoint(x: 0.72 * rect.width, y: 0.84 * rect.height))
        return p
    }
}

// MARK: - Main scaffold (native TabView)

struct MainScaffold: View {
    @Bindable var model: AppModel
    @Binding var isDark: Bool
    @Environment(\.palette) private var palette
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("even-google-prompted") private var googlePrompted = false
    @AppStorage("even-seen-invite-reveal") private var seenInviteReveal = false
    @AppStorage("even-notif-prompted") private var notifPrompted = false
    @State private var currentExtra: OnboardingExtra?

    enum OnboardingExtra: Identifiable {
        case inviteReveal, google, notifications
        var id: Int {
            switch self { case .inviteReveal: 0; case .google: 1; case .notifications: 2 }
        }
    }

    private var resetSymbol: String {
        if #available(iOS 18.0, *) { return "arrow.trianglehead.clockwise" }
        return "arrow.clockwise"
    }

    var body: some View {
        TabView(selection: $model.tab) {
            screen { TodayView(model: model) }
                .tabItem { Label("Today", systemImage: "scalemass") }
                .tag(EvenTab.today)

            screen { InboxView(model: model) }
                .tabItem { Label("Inbox", systemImage: "tray") }
                .badge(model.summary?.pendingDraftCount ?? 0)
                .tag(EvenTab.inbox)

            screen { MoneyView(model: model) }
                .tabItem { Label("Money", systemImage: "eurosign.circle") }
                .tag(EvenTab.money)

            screen { ResetView(model: model) }
                .tabItem { Label("Reset", systemImage: resetSymbol) }
                .tag(EvenTab.reset)
        }
        .tint(palette.clay)
        .overlay(alignment: .bottom) {
            if let message = model.stampMessage {
                StampToast(message: message)
                    .padding(.bottom, 100)
            }
        }
        .overlay(alignment: .top) {
            if let error = model.errorMessage {
                ErrorBanner(message: error) { model.errorMessage = nil }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: model.stampMessage)
        .task { await model.refreshAll() }
        .onChange(of: model.tab) { _, tab in
            if tab == .reset {
                Task { await model.refreshReset() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refreshAll() }
            }
        }
        .onChange(of: model.googleStatus?.connected) { _, _ in advanceExtras() }
        .onChange(of: model.household?.members.count) { _, _ in advanceExtras() }
        .promptCover(isPresented: Binding(get: { currentExtra != nil },
                                          set: { if !$0 { currentExtra = nil } })) {
            extraView
        }
    }

    /// Post-setup onboarding pages (design 06 → 08 → 10), each shown once,
    /// all suppressed for the UI test suites.
    private func advanceExtras() {
        guard currentExtra == nil, !skipOnboardingExtras else { return }
        if !seenInviteReveal, model.household?.partner == nil, model.household != nil {
            currentExtra = .inviteReveal
        } else if !googlePrompted, GoogleConnectConfig.isEnabled,
                  model.googleStatus?.connected == false {
            currentExtra = .google
        } else if !notifPrompted, model.googleStatus != nil {
            currentExtra = .notifications
        }
    }

    @ViewBuilder
    private var extraView: some View {
        switch currentExtra {
        case .inviteReveal:
            InviteRevealView(model: model) {
                seenInviteReveal = true
                currentExtra = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { advanceExtras() }
            }
        case .google:
            GoogleConnectPrompt(model: model) {
                googlePrompted = true
                currentExtra = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { advanceExtras() }
            }
        case .notifications:
            NotificationsPromptView {
                notifPrompted = true
                currentExtra = nil
            }
        case nil:
            EmptyView()
        }
    }

    /// Each tab: paper ground + the wordmark header above its content.
    private func screen<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            header
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(palette.bg.ignoresSafeArea())
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
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressScaleStyle(scale: 0.9))
            .accessibilityIdentifier("dark-toggle")
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


private extension View {
    /// fullScreenCover is iOS-only; the mac package build gets a sheet.
    @ViewBuilder
    func promptCover<C: View>(isPresented: Binding<Bool>,
                              @ViewBuilder content: @escaping () -> C) -> some View {
        #if os(iOS)
        self.fullScreenCover(isPresented: isPresented, content: content)
        #else
        self.sheet(isPresented: isPresented, content: content)
        #endif
    }
}
