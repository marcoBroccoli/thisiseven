#if os(iOS)
    import SwiftUI

    public extension View {
        /// Hides the system tab bar so ``IGStyleTabBar`` can float over content.
        func hideNativeTabBar() -> some View {
            toolbarVisibility(.hidden, for: .tabBar)
        }

        /// Tracks vertical scroll to drive floating tab-bar collapse progress (0…1).
        ///
        /// Also hides the native tab bar and pads the bottom by 50pt for the overlay.
        func adoptForIGTabBar(_ progress: Binding<CGFloat>) -> some View {
            modifier(IGTabBarScrollModifier(progress: progress))
        }

        /// No-op when `progress` is nil (previews / Watch / embedded).
        @ViewBuilder
        func adoptForIGTabBar(_ progress: Binding<CGFloat>?) -> some View {
            if let progress {
                adoptForIGTabBar(progress)
            } else {
                self
            }
        }
    }

    /// 0 = expanded, 1 = minimized. Port of Kavsoft `IGTabBarViewModifier`.
    private struct IGTabBarScrollModifier: ViewModifier {
        @Binding var progress: CGFloat
        @GestureState private var isDragging = false
        @State private var isScrolledUp: Bool?
        @State private var shiftOffset: CGFloat = 0
        @State private var scrollOffset: CGFloat = 0
        @State private var isLargerContent = false
        @State private var scrollPhase: ScrollPhase = .idle

        private var distance: CGFloat {
            100
        }

        private var animation: Animation {
            .interpolatingSpring(duration: 0.25, bounce: 0, initialVelocity: 0)
        }

        func body(content: Content) -> some View {
            content
                .toolbarVisibility(.hidden, for: .tabBar)
                .safeAreaPadding(.bottom, 50)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .scrollView)
                        .updating($isDragging) { _, out, _ in
                            out = true
                        }
                        .onEnded { value in
                            guard scrollPhase != .idle else { return }
                            let velocity = -value.velocity.height / 5
                            let resultOffset = scrollOffset + velocity
                            let rawProgress = (resultOffset - shiftOffset) / distance
                            let clampedProgress = max(0, min(1, rawProgress))

                            withAnimation(animation) {
                                progress =
                                    resultOffset > (distance / 2) && isLargerContent
                                        ? (clampedProgress > 0.5 ? 1 : 0)
                                        : 0
                            }

                            isScrolledUp = nil
                            shiftOffset = scrollOffset - (progress * distance)
                        }
                )
                .onScrollPhaseChange { _, newPhase in
                    scrollPhase = newPhase
                }
                .onScrollGeometryChange(for: CGFloat.self, of: {
                    $0.contentSize.height - $0.containerSize.height
                }, action: { _, newValue in
                    isLargerContent = newValue > 0
                })
                .onScrollGeometryChange(for: CGFloat.self, of: {
                    $0.contentOffset.y + $0.contentInsets.top
                }, action: { oldValue, newValue in
                    guard isDragging else { return }
                    scrollOffset = newValue
                    let scrolledUp = oldValue < newValue

                    if isScrolledUp != scrolledUp {
                        isScrolledUp = scrolledUp
                        shiftOffset = newValue - (progress * distance)
                    }

                    let rawProgress = (newValue - shiftOffset) / distance
                    let clampedProgress = max(0, min(1, rawProgress))
                    withAnimation(animation) {
                        progress = clampedProgress
                    }
                })
        }
    }
#endif
