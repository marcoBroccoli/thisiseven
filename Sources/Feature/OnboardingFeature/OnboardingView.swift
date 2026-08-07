#if os(iOS)
    import ComposableArchitecture
    import Design
    import SwiftUI

    @ViewAction(for: OnboardingReducer.self)
    public struct OnboardingView: View {
        @Bindable public var store: StoreOf<OnboardingReducer>

        /// Programmatic page for the content pager (mirrors `store.pageIndex`).
        @State private var illustrationPage: Int?

        public init(store: StoreOf<OnboardingReducer>) {
            self.store = store
        }

        public var body: some View {
            NavigationStack {
                pageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .toolbar {
                        if store.showsBack {
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    send(.backTapped, animation: EvenMotion.page)
                                } label: {
                                    Image(systemName: "chevron.backward")
                                }
                                .accessibilityLabel("Back")
                                .accessibilityIdentifier("onboarding-back")
                                .transition(
                                    .asymmetric(
                                        insertion: .opacity.combined(with: .offset(x: -8)),
                                        removal: .opacity.combined(with: .offset(x: -8))
                                    )
                                )
                            }
                        }
                        ToolbarItem(placement: .principal) {
                            Text("How Even works")
                                .font(.system(size: 17, weight: .medium, design: .serif))
                                .foregroundStyle(EvenTokens.espresso)
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("SKIP") { send(.skipTapped) }
                                .buttonStyle(.evenPlain)
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(1.4)
                                .foregroundStyle(EvenTokens.stone)
                                .accessibilityIdentifier("onboarding-skip")
                        }
                    }
                    .animation(EvenMotion.reveal, value: store.showsBack)
                    // Paper on the stack *content* — a layer behind NavigationStack
                    // is covered by the stack's opaque chrome.
                    .evenPaperNavigationChrome()
                    .onAppear {
                        illustrationPage = store.pageIndex
                    }
                    .onChange(of: store.pageIndex) { _, newValue in
                        withAnimation(EvenMotion.page) {
                            illustrationPage = newValue
                        }
                    }
            }
        }

        private var pageContent: some View {
            contentPager
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    footer
                        .padding(.horizontal, ViewConfig.horizontalInset)
                }
        }

        private var contentPager: some View {
            GeometryReader { geo in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(OnboardingReducer.State.allCases, id: \.pageIndex) { page in
                            pageCard(page)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .id(page.pageIndex)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $illustrationPage)
                .scrollDisabled(true)
                .scrollClipDisabled()
                .evenScrollOnPaper()
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(store.title). \(store.message)")
        }

        private func pageCard(_ page: OnboardingReducer.State) -> some View {
            let isActive = page.pageIndex == store.pageIndex

            return VStack(spacing: 0) {
                Spacer(minLength: 0)

                // Clear frame owns the height even before art mounts; overlaying
                // keeps the title/subtitle from jumping when the page becomes active.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: HowItWorksArt.illustrationHeight)
                    .overlay {
                        if isActive {
                            HowItWorksArt.page(page)
                                .id("art-\(page.pageIndex)")
                        }
                    }

                Text(page.title)
                    .font(.system(size: 30, weight: .medium, design: .serif))
                    .foregroundStyle(EvenTokens.espresso)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, ViewConfig.copyTop)

                Text(page.message)
                    .font(.system(size: 15.5))
                    .foregroundStyle(Color(hex: 0x6E6353))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                    .frame(minHeight: ViewConfig.subtitleMinHeight, alignment: .top)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, ViewConfig.horizontalInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        private var footer: some View {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(OnboardingReducer.State.allCases, id: \.pageIndex) { page in
                        Capsule()
                            .fill(
                                page == store.state
                                    ? EvenTokens.espresso
                                    : EvenTokens.espresso.opacity(0.2)
                            )
                            .frame(width: page == store.state ? 18 : 6, height: 6)
                            .animation(EvenMotion.indicator, value: store.state)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)

                EvenPrimaryButton(
                    store.isLast ? "Get started" : "Next",
                    accessibilityId: "onboarding-next"
                ) {
                    send(.nextTapped, animation: EvenMotion.page)
                }
                .padding(.bottom, 36)
            }
        }

        private enum ViewConfig {
            static let horizontalInset: CGFloat = 28
            static let copyTop: CGFloat = 28
            static let subtitleMinHeight: CGFloat = 130
        }
    }

    #Preview("Onboarding") {
        OnboardingView(store: OnboardingPreviewSupport.flow())
    }
#endif
