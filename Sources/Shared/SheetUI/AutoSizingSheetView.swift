#if os(iOS)
    import SwiftUI
    import UIKit

    /// A sheet that sizes itself to whatever it is given.
    ///
    /// Content arrives in two roles, because a sheet that sizes itself has two kinds of child. The **body** is
    /// elastic: it drives the height, and it is what scrolls once there is no more height to be had. The
    /// **footer** is rigid: it never scrolls, never shrinks and never moves, so a CTA stays under the thumb
    /// wherever the body has got to. Naming them is what lets this component guarantee that rather than ask
    /// each caller to arrange it — see `measuredContent` for how the two are made to add up.
    ///
    /// The header stays native: `.toolbar` and `.navigationTitle` attached to the body reach the
    /// `NavigationStack` this provides.
    ///
    /// ```swift
    /// .sheet(isPresented: $isPresented) {
    ///     AutoSizingSheetView {
    ///         ScrollView { body }                     // elastic: drives the height, scrolls at the ceiling
    ///             .scrollBounceBehavior(.basedOnSize, axes: .vertical)
    ///             .toolbar { ToolbarItem(placement: .principal) { Text(title) } }
    ///     } footer: {
    ///         footer                                  // rigid: pinned, always visible — omit if there is none
    ///     }
    /// }
    /// ```
    ///
    /// Copied into Even as a portable kit (`SheetUI`). Keep brand-free: pass `surface` for the sheet fill.
    ///
    /// ## Why the detent is applied through an `Animatable` modifier
    ///
    /// There is no content-sized detent on any iOS version, so a height has to be measured and fed back.
    /// The obvious way — assign a new `.height` detent, or animate a selection between two — hands the
    /// resize to `UISheetPresentationController`, which animates the frame on its own schedule while
    /// SwiftUI lays the content out on another. The content then arrives at its new size a frame early and
    /// anything pinned low corrects abruptly at the end, and the two cannot be matched because UIKit's
    /// curve is not exposed.
    ///
    /// `SheetHeightModifier` is `Animatable`, so SwiftUI interpolates the height itself and installs a new
    /// detent on every frame. The sheet's frame and its content then move on one clock.
    ///
    /// ## How the measurement avoids chasing itself
    ///
    /// `fixedSize` makes the content report its *ideal* height, which does not depend on how tall the sheet
    /// currently is. That is not sufficient on its own: a geometry read reports the size the content is being
    /// presented at, and during a resize that is an interpolated value, so each frame of the resize comes back
    /// looking like a fresh change. `contentDidMeasure` therefore holds reads while a resize is in flight and
    /// commits the last one at the end — see it for what that costs when it is not done.
    ///
    /// Only a quantity independent of the sheet's height may be fed back into it, and there is exactly one: the
    /// body's `fixedSize`d read. The footer is never measured — a safe-area inset resolves it in the same pass as
    /// the body. Anything derived from the sheet's own frame — the area the stack hands its content, most
    /// temptingly, as a way to learn what the navigation bar took — depends on the value it is about to change,
    /// and the sheet then resizes on stale reads of its own size forever: it drifts while idle, with nothing
    /// touching it.
    ///
    /// The navigation bar's height is therefore not accounted for at all, and the body's top is what pays: it
    /// runs under the bar by however much the bar took. The only real fix is for the bar not to exist — a header
    /// role alongside the footer, measured like everything else.
    ///
    /// ## What the content is responsible for
    ///
    /// Both roles have their vertical insets applied for them, and neither should add its own: the body clears the
    /// navigation bar's translucent background at the top, and the sheet's bottom edge when nothing is below it;
    /// the footer is inset above and below, clear of both the body and the sheet's edge.
    ///
    /// Drag-to-dismiss is off unless `isSwipeToDismissEnabled` says otherwise, so the content must offer a
    /// way out — a close button in the toolbar.
    ///
    /// - **Scrolling.** The sheet stops growing at its ceiling; a scroll view in the body takes over from
    ///   there. A body without one is clipped instead — bottom-aligned, so its top is what is lost.
    /// - **Animating its own changes**, with the same spring the sheet uses
    ///   (`.spring(response: 0.35, dampingFraction: 1)`). The sheet resizes with that token and takes
    ///   no animation parameter: the resize cannot inherit the transaction that caused it — it starts a layout
    ///   pass later, once the new height is measured — so the two only land together while both name the same
    ///   curve. A change sent without any animation resizes the sheet abruptly.
    /// - **Grouping its own geometry.** The body as a whole is grouped for you; what is *inside* it is not. Each
    ///   child of a stack whose height changes resolves its own geometry, so parts of a changing body drift
    ///   against each other while it settles: apply `geometryGroup()` to the changing part and its
    ///   container, one call per unit that must not come apart. The footer needs none of this; it is not in the
    ///   body.
    public struct AutoSizingSheetView<Content: View, Footer: View>: View {
        /// Shared with content that animates its own height changes — see type docs.
        private let animation: Animation = .spring(response: 0.35, dampingFraction: 1)
        private let maxHeightFraction: CGFloat
        private let isSwipeToDismissEnabled: Bool
        private let isFooterBackgroundVisible: Bool
        private let surface: Color
        private let content: Content
        private let footer: Footer?

        @State private var contentHeight: CGFloat = 0
        @State private var sheetHeight: CGFloat = Layout.initialSheetHeight
        /// Whether the sheet has finished *arriving* at its size, as opposed to changing it.
        @State private var isSettled = false
        /// The most recent read, whether or not it has been acted on — see `contentDidMeasure`.
        @State private var latestMeasuredHeight: CGFloat = 0
        @State private var isResizing = false
        /// Whether the stack's area has been laid out at a real size yet — the gate for the first commit.
        @State private var isContainerSized = false

        /// - Parameters:
        ///   - maxHeightFraction: How much of the screen the sheet may occupy before it stops growing.
        ///   - isSwipeToDismissEnabled: Whether dragging the sheet down closes it. Off by default.
        ///   - isFooterBackgroundVisible: Whether the footer paints the sheet's surface behind itself.
        ///   - surface: Sheet backdrop (and footer fill when visible). Brand-free default is system background.
        ///   - content: Body — drives height; attach `.toolbar` / `.navigationTitle` here.
        ///   - footer: Rigid bottom chrome. Omit for a sheet with nothing to hold still.
        public init(
            maxHeightFraction: CGFloat = 0.85,
            isSwipeToDismissEnabled: Bool = false,
            isFooterBackgroundVisible: Bool = true,
            surface: Color = Color(uiColor: .systemBackground),
            @ViewBuilder content: () -> Content,
            @ViewBuilder footer: () -> Footer
        ) {
            self.maxHeightFraction = maxHeightFraction
            self.isSwipeToDismissEnabled = isSwipeToDismissEnabled
            self.isFooterBackgroundVisible = isFooterBackgroundVisible
            self.surface = surface
            self.content = content()
            self.footer = footer()
        }

        /// A sheet with nothing to hold still: all of it is body, and the body carries the bottom inset itself.
        public init(
            maxHeightFraction: CGFloat = 0.85,
            isSwipeToDismissEnabled: Bool = false,
            surface: Color = Color(uiColor: .systemBackground),
            @ViewBuilder content: () -> Content
        ) where Footer == EmptyView {
            self.maxHeightFraction = maxHeightFraction
            self.isSwipeToDismissEnabled = isSwipeToDismissEnabled
            isFooterBackgroundVisible = false
            self.surface = surface
            self.content = content()
            footer = nil
        }

        public var body: some View {
            NavigationStack {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) {
                        containerDidResolve(height: $0)
                    }
                    .overlay(alignment: .bottom) { measuredContent }
                    .clipped()
                    .ignoresSafeArea()
            }
            .modifier(SheetHeightModifier(height: sheetHeight))
            .presentationBackground(surface)
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled(!isSwipeToDismissEnabled)
            .task { await settleAfterArrival() }
        }

        private var measuredContent: some View {
            content
                .navigationBarTitleDisplayMode(.inline)
                .geometryGroup()
                .opacity(isSettled ? 1 : 0)
                .padding(.top, Layout.contentTopInset)
                .padding(.bottom, hasFooter ? 0 : Layout.contentBottomInset)
                .frame(maxWidth: .infinity)
                .safeAreaInset(edge: .bottom) { measuredFooter }
                .frame(maxHeight: maxHeight, alignment: .bottom)
                .fixedSize(horizontal: false, vertical: true)
                .measuringHeight { contentDidMeasure($0) }
        }

        @ViewBuilder
        private var measuredFooter: some View {
            if let footer {
                footer
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Layout.contentBottomInset)
                    .background { footerBackground }
            }
        }

        @ViewBuilder
        private var footerBackground: some View {
            if isFooterBackgroundVisible {
                surface
            }
        }

        private var hasFooter: Bool {
            footer != nil
        }

        private var maxHeight: CGFloat {
            UIScreen.main.bounds.height * maxHeightFraction
        }

        private func contentDidMeasure(_ height: CGFloat) {
            let height = height.rounded(.up)
            guard height > 0 else { return }
            latestMeasuredHeight = height
            guard isContainerSized else { return }
            commitContentHeight(height)
        }

        private func containerDidResolve(height: CGFloat) {
            guard height > 0, !isContainerSized else { return }
            isContainerSized = true
            commitContentHeight(latestMeasuredHeight)
        }

        private func settleAfterArrival() async {
            try? await Task.sleep(for: Layout.arrivalWindow)
            isSettled = true
        }

        private func commitContentHeight(_ height: CGFloat) {
            guard height > 0, height != contentHeight else { return }
            contentHeight = height
            applySheetHeight()
        }

        private func applySheetHeight() {
            guard contentHeight > 0 else { return }
            let target = min(contentHeight, maxHeight)
            guard target != sheetHeight else { return }
            guard isSettled else {
                sheetHeight = target
                return
            }
            isResizing = true
            withAnimation(animation) {
                sheetHeight = target
            } completion: {
                isResizing = false
                commitContentHeight(latestMeasuredHeight)
            }
        }
    }

    // MARK: - Layout

    private enum Layout {
        static let initialSheetHeight: CGFloat = 240
        static let arrivalWindow: Duration = .milliseconds(150)
        static let contentTopInset: CGFloat = 30
        static let contentBottomInset: CGFloat = 20
    }

    // MARK: - Detent

    private struct SheetHeightModifier: ViewModifier, @preconcurrency Animatable {
        var height: CGFloat

        nonisolated var animatableData: CGFloat {
            get { height }
            set { height = newValue }
        }

        func body(content: Content) -> some View {
            content.presentationDetents([.height(height)])
        }
    }

    // MARK: - Measurement

    public extension View {
        /// Reports this view's height, as presented, whenever it changes.
        ///
        /// Apply under `fixedSize(horizontal: false, vertical: true)` when the value must be an *ideal* height.
        func measuringHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
            onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: onChange)
        }
    }

    // MARK: - Previews

    #Preview("AutoSizingSheet · short") {
        AutoSizingSheetPreviewHost(tall: false)
    }

    #Preview("AutoSizingSheet · scrolls at ceiling") {
        AutoSizingSheetPreviewHost(tall: true)
    }

    private struct AutoSizingSheetPreviewHost: View {
        let tall: Bool
        @State private var isPresented = true

        var body: some View {
            Color.gray.opacity(0.35)
                .ignoresSafeArea()
                .sheet(isPresented: $isPresented) {
                    AutoSizingSheetView {
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(tall ? "Past the ceiling" : "A short step")
                                    .font(.system(size: 22, weight: .medium, design: .serif))
                                Text(
                                    tall
                                        ? String(
                                            repeating: "This paragraph repeats until the step is taller than "
                                                + "the sheet's maximum, so the sheet stops growing and this "
                                                + "text scrolls while the CTA stays put. ",
                                            count: 12
                                        )
                                        : "Two lines of copy, so the sheet starts near its smallest."
                                )
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                        }
                        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                        .toolbar {
                            ToolbarItem(placement: .principal) {
                                Text("Preview")
                                    .font(.system(size: 17, weight: .medium, design: .serif))
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Close") { isPresented = false }
                            }
                        }
                    } footer: {
                        Button("Confirm") { isPresented = false }
                            .font(.system(size: 16, weight: .medium, design: .serif))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .foregroundStyle(.white)
                            .background(Color.black, in: RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal, 20)
                    }
                }
        }
    }
#endif
