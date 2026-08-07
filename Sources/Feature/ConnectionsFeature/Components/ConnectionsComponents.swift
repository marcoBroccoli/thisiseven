#if os(iOS)
    import ComposableArchitecture
    import Design
    import SwiftUI

    struct ConnectionsBenefitRow: View {
        let systemImage: String
        let title: String
        let bodyText: String

        var body: some View {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(EvenTokens.espresso)
                    .frame(width: 34, height: 34)
                    .background(EvenTokens.espresso.opacity(0.055))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium, design: .serif))
                        .foregroundStyle(EvenTokens.espresso)
                    Text(bodyText)
                        .font(.system(size: 13.5))
                        .foregroundStyle(ConnectionsSetupChrome.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    struct ConnectionsScopeCard: View {
        let systemImage: String
        let title: String
        let bodyText: String
        @Binding var isOn: Bool

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(EvenTokens.espresso)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15.5, weight: .medium, design: .serif))
                        .foregroundStyle(EvenTokens.espresso)
                    Text(bodyText)
                        .font(.system(size: 13))
                        .foregroundStyle(ConnectionsSetupChrome.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .tint(EvenTokens.espresso)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(EvenTokens.paperCard)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(EvenTokens.espresso.opacity(0.16), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    struct ConnectGoogleButton: View {
        /// Connect OAuth in flight — shows “Connecting…” + spinner.
        let working: Bool
        /// Initial status check — spinner, keep Connect label.
        var checkingStatus: Bool = false
        let action: () -> Void

        private var busy: Bool {
            working || checkingStatus
        }

        private var title: String {
            working ? "Connecting…" : "Connect Google"
        }

        var body: some View {
            Button {
                guard !busy else { return }
                action()
            } label: {
                HStack(spacing: 10) {
                    icon
                    Text(title)
                        .font(.system(size: 15.5, weight: .semibold))
                        .contentTransition(.numericText())
                        .animation(EvenMotion.ctaSwap, value: title)
                }
                .foregroundStyle(EvenTokens.espresso)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(EvenTokens.paperCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(EvenTokens.espresso.opacity(0.16), lineWidth: 1.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.evenPlain)
            .allowsHitTesting(!busy)
            .accessibilityIdentifier("Connect Google")
        }

        /// Fixed slot so the glyph swap can't shift the label sideways.
        private var icon: some View {
            ZStack {
                if busy {
                    ProgressView()
                        .controlSize(.small)
                        .transition(EvenMotion.blurFade)
                } else {
                    EvenGoogleGMark()
                        .transition(EvenMotion.blurFade)
                }
            }
            .frame(width: 18, height: 18)
            .animation(EvenMotion.ctaSwap, value: busy)
        }
    }

    /// Success badge — checkmark draws first; pine disc lands only after the stroke finishes.
    struct ConnectionsDrawnCheckmark: View {
        var size: CGFloat = 64

        @State private var drawProgress: CGFloat = 0
        @State private var showDisc = false

        private enum Timing {
            /// Beat before the stroke starts — lets the page settle first.
            static let startDelay: Duration = .milliseconds(420)
            static let drawDuration: TimeInterval = 0.48
            static let discDelayAfterDraw: TimeInterval = 0.04
        }

        var body: some View {
            ZStack {
                Circle()
                    .fill(EvenTokens.pine.opacity(0.14))
                    .scaleEffect(showDisc ? 1 : 0.84)
                    .opacity(showDisc ? 1 : 0)

                ConnectionsCheckmarkShape()
                    .trim(from: 0, to: drawProgress)
                    .stroke(
                        EvenTokens.pine,
                        style: StrokeStyle(lineWidth: size * 0.055, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: size * 0.42, height: size * 0.42)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
            .task { await play() }
        }

        @MainActor
        private func play() async {
            drawProgress = 0
            showDisc = false
            try? await Task.sleep(for: Timing.startDelay)
            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: Timing.drawDuration)) {
                drawProgress = 1
            }
            try? await Task.sleep(for: .seconds(Timing.drawDuration + Timing.discDelayAfterDraw))
            guard !Task.isCancelled else { return }

            withAnimation(EvenMotion.reveal) {
                showDisc = true
            }
        }
    }

    /// Single continuous stroke — short leg then long, so `trim` draws left→right.
    struct ConnectionsCheckmarkShape: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.52))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.40, y: rect.minY + rect.height * 0.78))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.90, y: rect.minY + rect.height * 0.22))
            return path
        }
    }

    struct ConnectionsCalendarCallout: View {
        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(EvenTokens.espresso)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text("“Even” calendar subscribed")
                        .font(.system(size: 14.5, weight: .medium, design: .serif))
                        .foregroundStyle(EvenTokens.espresso)
                    Text("Both of you now see the same bills, renewals and visits beside your own plans.")
                        .font(.system(size: 11))
                        .foregroundStyle(EvenTokens.stone)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: 280, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
                    .foregroundStyle(EvenTokens.espresso.opacity(0.22))
            )
        }
    }

    /// Shell-owned CTA strip — always the same two slots.
    ///
    /// Primary is one persistent control that morphs style/title in place.
    /// Secondary is conditional: when it leaves, the VStack collapses and primary
    /// falls to the bottom edge — no footer tree swap, no cross-fade replace.
    @ViewAction(for: ConnectionsReducer.self)
    struct ConnectionsPathFooter: View {
        @Bindable var store: StoreOf<ConnectionsReducer>

        private var footer: ConnectionsReducer.Footer {
            store.footer
        }

        var body: some View {
            VStack(spacing: 14) {
                ConnectionsFooterPrimaryButton(button: footer.primary) {
                    send(.primaryTapped, animation: EvenMotion.page)
                }

                if let secondary = footer.secondary {
                    ConnectionsFooterSecondaryButton(button: secondary) {
                        send(.secondaryTapped)
                    }
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 10)),
                            removal: .opacity.combined(with: .offset(y: 10))
                        )
                    )
                }
            }
            .frame(maxWidth: .infinity)
            // Layout spring so primary rides down when secondary collapses.
            .animation(EvenMotion.page, value: footer.secondary != nil)
            .animation(EvenMotion.ctaSwap, value: footer.primary)
        }
    }

    /// One primary control — google outline and espresso fill share the same button
    /// identity so style/text animate instead of the view being replaced.
    struct ConnectionsFooterPrimaryButton: View {
        let button: ConnectionsReducer.Footer.Button
        let action: () -> Void

        private var isGoogle: Bool {
            button.style == .google
        }

        private var busy: Bool {
            button.working || button.checkingStatus
        }

        private var enabled: Bool {
            button.enabled && !busy
        }

        var body: some View {
            Button {
                guard enabled else { return }
                action()
            } label: {
                HStack(spacing: 10) {
                    if isGoogle {
                        googleIcon
                            .transition(EvenMotion.blurFade)
                    }

                    Text(button.title)
                        .font(
                            isGoogle
                                ? .system(size: 15.5, weight: .semibold)
                                : .system(size: 16, weight: .medium, design: .serif)
                        )
                        .contentTransition(.numericText())
                }
                .foregroundStyle(isGoogle ? EvenTokens.espresso : EvenTokens.paperRaised)
                .frame(maxWidth: .infinity)
                .frame(height: isGoogle ? 52 : 50)
                .background(primaryFill)
                .overlay {
                    EvenPrimaryButton.shape
                        .stroke(
                            isGoogle ? EvenTokens.espresso.opacity(0.16) : .clear,
                            lineWidth: 1.5
                        )
                }
                .clipShape(EvenPrimaryButton.shape)
                .contentShape(EvenPrimaryButton.shape)
            }
            .buttonStyle(.evenPlain)
            .allowsHitTesting(enabled)
            .accessibilityIdentifier(button.accessibilityId)
            .accessibilityAddTraits(enabled ? [] : .isStaticText)
            .accessibilityRemoveTraits(enabled ? [] : .isButton)
        }

        private var primaryFill: Color {
            if isGoogle { return EvenTokens.paperCard }
            return button.enabled ? EvenTokens.espresso : EvenTokens.stone
        }

        private var googleIcon: some View {
            ZStack {
                if busy {
                    ProgressView()
                        .controlSize(.small)
                        .transition(EvenMotion.blurFade)
                } else {
                    EvenGoogleGMark()
                        .transition(EvenMotion.blurFade)
                }
            }
            .frame(width: 18, height: 18)
            .animation(EvenMotion.ctaSwap, value: busy)
        }
    }

    struct ConnectionsFooterSecondaryButton: View {
        let button: ConnectionsReducer.Footer.Button
        let action: () -> Void

        var body: some View {
            Button {
                guard button.enabled else { return }
                action()
            } label: {
                Text(button.title)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.4)
                    .underline(true, color: EvenTokens.stone)
                    .foregroundStyle(EvenTokens.stone)
                    .contentTransition(.numericText())
                    .padding(6)
            }
            .buttonStyle(.evenPlain)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(button.enabled)
            .accessibilityIdentifier(button.accessibilityId)
        }
    }
#endif
