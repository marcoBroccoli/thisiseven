#if os(iOS)
    import SwiftUI
    import UIKit

    /// Segment content for ``IGStyleTabBar``.
    public enum IGTabBarItem: Equatable, Sendable {
        case symbol(String)
        case title(String)
    }

    /// Sizing / tint for ``IGStyleTabBar``.
    public struct IGStyleTabBarConfiguration: Equatable, Sendable {
        public enum Width: Equatable, Sendable {
            /// Fill the proposed width (app tab bar).
            case flexible
            /// Fixed width (Today organize bar).
            case fixed(CGFloat)
        }

        public var height: CGFloat
        public var width: Width
        public var selectedSegmentTint: Color
        /// Label / symbol color.
        public var foreground: Color
        public var symbolPointSize: CGFloat
        public var titleFont: UIFont

        public init(
            height: CGFloat = 50,
            width: Width = .flexible,
            selectedSegmentTint: Color = Color.gray.opacity(0.25),
            foreground: Color = Color.primary,
            symbolPointSize: CGFloat = 20,
            titleFont: UIFont = .systemFont(ofSize: 12, weight: .semibold)
        ) {
            self.height = height
            self.width = width
            self.selectedSegmentTint = selectedSegmentTint
            self.foreground = foreground
            self.symbolPointSize = symbolPointSize
            self.titleFont = titleFont
        }

        /// App bottom tab bar — expands to the available width.
        public static let floating = IGStyleTabBarConfiguration()

        /// Compact fixed control (e.g. Day / Type / Person).
        public static func fixed(width: CGFloat, height: CGFloat = 40) -> IGStyleTabBarConfiguration {
            IGStyleTabBarConfiguration(height: height, width: .fixed(width))
        }
    }

    /// Instagram-style ``UISegmentedControl`` wrapper (Kavsoft / Balaji pattern).
    ///
    /// Segments are **always images** (SF Symbols or rendered title bitmaps). The
    /// control’s top-level `UIImageView`s are chrome; content images live deeper,
    /// which is why the Kavsoft “fade chrome except the thumb” trick works.
    public struct IGStyleTabBar<Value: CaseIterable & Hashable>: UIViewRepresentable {
        @Binding private var selection: Value
        private var item: (Value) -> IGTabBarItem
        private var onInteraction: () -> Void
        private var configuration: IGStyleTabBarConfiguration

        public init(
            selection: Binding<Value>,
            configuration: IGStyleTabBarConfiguration = .floating,
            onInteraction: @escaping () -> Void = {},
            item: @escaping (Value) -> IGTabBarItem
        ) {
            _selection = selection
            self.configuration = configuration
            self.onInteraction = onInteraction
            self.item = item
        }

        public func makeUIView(context: Context) -> IGSegmentedControl {
            let values = Array(Value.allCases)
            let images = values.map { segmentImage(for: $0) }
            let control = IGSegmentedControl(items: images)
            control.selectedSegmentIndex = values.firstIndex(of: selection) ?? 0
            applyChrome(to: control)
            control.addTarget(
                context.coordinator,
                action: #selector(Coordinator.valueChanged(_:)),
                for: .valueChanged
            )
            control.onTouchBegan = onInteraction
            control.clearTrackChrome()
            return control
        }

        public func updateUIView(_ uiView: IGSegmentedControl, context _: Context) {
            let values = Array(Value.allCases)
            let selectedIndex = values.firstIndex(of: selection) ?? 0
            if uiView.selectedSegmentIndex != selectedIndex {
                uiView.selectedSegmentIndex = selectedIndex
            }
            applyChrome(to: uiView)
            for (index, value) in values.enumerated() where index < uiView.numberOfSegments {
                uiView.setImage(segmentImage(for: value), forSegmentAt: index)
                uiView.setTitle(nil, forSegmentAt: index)
            }
            uiView.clearTrackChrome()
        }

        public func sizeThatFits(
            _ proposal: ProposedViewSize,
            uiView _: IGSegmentedControl,
            context _: Context
        ) -> CGSize? {
            let height = configuration.height
            switch configuration.width {
            case .flexible:
                return CGSize(
                    width: proposal.replacingUnspecifiedDimensions().width,
                    height: height
                )
            case let .fixed(width):
                return CGSize(width: width, height: height)
            }
        }

        public func makeCoordinator() -> Coordinator {
            Coordinator(parent: self)
        }

        public final class Coordinator: NSObject {
            var parent: IGStyleTabBar
            init(parent: IGStyleTabBar) {
                self.parent = parent
            }

            @objc func valueChanged(_ sender: UISegmentedControl) {
                let values = Array(Value.allCases)
                guard sender.selectedSegmentIndex >= 0,
                      sender.selectedSegmentIndex < values.count
                else { return }
                parent.selection = values[sender.selectedSegmentIndex]
            }
        }

        private func segmentImage(for value: Value) -> UIImage {
            switch item(value) {
            case let .symbol(name):
                symbolImage(name)
            case let .title(title):
                titleImage(title)
            }
        }

        private func symbolImage(_ name: String) -> UIImage {
            let config = UIImage.SymbolConfiguration(
                font: .systemFont(ofSize: configuration.symbolPointSize, weight: .medium)
            )
            let base = (UIImage(systemName: name) ?? UIImage()).withConfiguration(config)
            return base
                .withTintColor(UIColor(configuration.foreground), renderingMode: .alwaysOriginal)
        }

        /// Rasterize copy so titles take the same image path as SF Symbols.
        /// Plain `setTitle` disappears on iOS 26 once track chrome is cleared.
        private func titleImage(_ title: String) -> UIImage {
            let foreground = UIColor(configuration.foreground)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: configuration.titleFont,
                .foregroundColor: foreground,
            ]
            let textSize = (title as NSString).size(withAttributes: attributes)
            let horizontal: CGFloat = 6
            let vertical: CGFloat = 2
            let canvas = CGSize(
                width: max(1, ceil(textSize.width + horizontal * 2)),
                height: max(1, ceil(textSize.height + vertical * 2))
            )
            let format = UIGraphicsImageRendererFormat.default()
            format.opaque = false
            let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
            return renderer.image { _ in
                let origin = CGPoint(
                    x: (canvas.width - textSize.width) / 2,
                    y: (canvas.height - textSize.height) / 2
                )
                (title as NSString).draw(at: origin, withAttributes: attributes)
            }.withRenderingMode(.alwaysOriginal)
        }

        private func applyChrome(to control: IGSegmentedControl) {
            control.selectedSegmentTintColor = UIColor(configuration.selectedSegmentTint)
            control.tintColor = UIColor(configuration.foreground)
            control.backgroundColor = .clear
            // Official clear-track API — avoids grey fills without nuking content layers.
            let clear = UIImage()
            control.setBackgroundImage(clear, for: .normal, barMetrics: .default)
            control.setBackgroundImage(clear, for: .selected, barMetrics: .default)
            control.setBackgroundImage(clear, for: .highlighted, barMetrics: .default)
            control.setDividerImage(
                clear,
                forLeftSegmentState: .normal,
                rightSegmentState: .normal,
                barMetrics: .default
            )
        }
    }

    public final class IGSegmentedControl: UISegmentedControl {
        var onTouchBegan: (() -> Void)?

        override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesBegan(touches, with: event)
            onTouchBegan?()
        }

        /// Kavsoft: fade top-level chrome `UIImageView`s, keep the last (thumb).
        /// Content segment images live deeper and stay visible.
        func clearTrackChrome() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                for subview in self.subviews {
                    if subview is UIImageView, subview !== self.subviews.last {
                        subview.alpha = 0
                    }
                }
            }
        }
    }

    // MARK: - Floating chrome

    public extension View {
        /// Capsule chrome + optional scroll-collapse scale (Instagram sample).
        ///
        /// - Parameters:
        ///   - progress: 0 expanded → 1 minimized (ignored when `collapses` is false).
        ///   - collapses: When false, bar stays full scale (Today organize).
        ///   - horizontalPadding: Outer padding; use `0` when the parent already insets.
        func igTabBarChrome(
            progress: CGFloat = 0,
            collapses: Bool = true,
            horizontalPadding: CGFloat = 20
        ) -> some View {
            modifier(
                IGTabBarChromeModifier(
                    progress: progress,
                    collapses: collapses,
                    horizontalPadding: horizontalPadding
                )
            )
        }
    }

    private struct IGTabBarChromeModifier: ViewModifier {
        var progress: CGFloat
        var collapses: Bool
        var horizontalPadding: CGFloat

        func body(content: Content) -> some View {
            content
                .padding(4)
                .modifier(IGTabBarGlassModifier())
                .scaleEffect(collapses ? (1 - (progress * 0.15)) : 1, anchor: .bottom)
                .padding(.horizontal, horizontalPadding)
        }
    }

    private struct IGTabBarGlassModifier: ViewModifier {
        func body(content: Content) -> some View {
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular.interactive(), in: .capsule)
            } else {
                content.background(.ultraThinMaterial, in: Capsule())
            }
        }
    }
#endif
