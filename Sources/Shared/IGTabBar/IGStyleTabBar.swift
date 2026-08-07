#if os(iOS)
    import SwiftUI
    import UIKit

    /// Segment content for ``IGStyleTabBar``.
    public enum IGTabBarItem: Equatable, Sendable {
        case symbol(String, badge: Int = 0)
        case title(String, badge: Int = 0)

        public var badge: Int {
            switch self {
            case let .symbol(_, badge), let .title(_, badge): badge
            }
        }
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
        /// Unread / count pip on a segment image.
        public var badgeFill: Color
        public var badgeForeground: Color
        public var symbolPointSize: CGFloat
        public var titleFont: UIFont

        public init(
            height: CGFloat = 50,
            width: Width = .flexible,
            selectedSegmentTint: Color = Color.gray.opacity(0.25),
            foreground: Color = Color.primary,
            badgeFill: Color = Color.red,
            badgeForeground: Color = Color.white,
            symbolPointSize: CGFloat = 20,
            titleFont: UIFont = .systemFont(ofSize: 12, weight: .semibold)
        ) {
            self.height = height
            self.width = width
            self.selectedSegmentTint = selectedSegmentTint
            self.foreground = foreground
            self.badgeFill = badgeFill
            self.badgeForeground = badgeForeground
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
            control.selectedSegmentTintColor = UIColor(configuration.selectedSegmentTint)
            control.tintColor = UIColor(configuration.foreground)
            control.addTarget(
                context.coordinator,
                action: #selector(Coordinator.valueChanged(_:)),
                for: .valueChanged
            )
            control.onTouchBegan = onInteraction
            // Kavsoft: fade track chrome UIImageViews once after layout. Do NOT
            // setBackgroundImage(clear) or re-run this on every update — on iOS
            // 26 segment symbols also sit in top-level UIImageViews and go blank.
            DispatchQueue.main.async { [weak control] in
                guard let control else { return }
                for subview in control.subviews {
                    if subview is UIImageView, subview != control.subviews.last {
                        subview.alpha = 0
                    }
                }
            }
            return control
        }

        public func updateUIView(_ uiView: IGSegmentedControl, context: Context) {
            context.coordinator.parent = self
            uiView.onTouchBegan = onInteraction
            let values = Array(Value.allCases)
            let selectedIndex = values.firstIndex(of: selection) ?? 0
            if uiView.selectedSegmentIndex != selectedIndex {
                uiView.selectedSegmentIndex = selectedIndex
            }
            uiView.selectedSegmentTintColor = UIColor(configuration.selectedSegmentTint)
            uiView.tintColor = UIColor(configuration.foreground)
            // Refresh segment images when badges / symbols change. Do not re-run
            // the chrome alpha fade — that blanks icons on iOS 26.
            for (index, value) in values.enumerated() where index < uiView.numberOfSegments {
                uiView.setImage(segmentImage(for: value), forSegmentAt: index)
            }
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
            case let .symbol(name, badge):
                let base = symbolImage(name)
                return badge > 0 ? badged(base, count: badge) : base
            case let .title(title, badge):
                let base = titleImage(title)
                return badge > 0 ? badged(base, count: badge) : base
            }
        }

        private func symbolImage(_ name: String) -> UIImage {
            // Match Kavsoft: template SF Symbol + SymbolConfiguration(font:).
            // Badged composites rasterize tint into alwaysOriginal below.
            let config = UIImage.SymbolConfiguration(
                font: .systemFont(ofSize: configuration.symbolPointSize)
            )
            return (UIImage(systemName: name) ?? UIImage()).withConfiguration(config)
        }

        /// Rasterize titles onto the same image-segment path as SF Symbols.
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

        /// Corner count pip composited onto the segment image (UISegmentedControl
        /// has no native badge API).
        private func badged(_ image: UIImage, count: Int) -> UIImage {
            let tinted = image.withTintColor(
                UIColor(configuration.foreground),
                renderingMode: .alwaysOriginal
            )
            let badgeText = count > 9 ? "9+" : "\(count)"
            let badgeFont = UIFont.systemFont(ofSize: 9, weight: .bold)
            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: badgeFont,
                .foregroundColor: UIColor(configuration.badgeForeground),
            ]
            let textSize = (badgeText as NSString).size(withAttributes: textAttributes)
            let badgeSide = max(14, ceil(max(textSize.width, textSize.height) + 4))
            let pad: CGFloat = 3
            let symbolSize = tinted.size
            let canvas = CGSize(
                width: ceil(symbolSize.width + badgeSide * 0.45),
                height: ceil(symbolSize.height + badgeSide * 0.35)
            )
            let format = UIGraphicsImageRendererFormat.default()
            format.opaque = false
            let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
            return renderer.image { _ in
                let symbolOrigin = CGPoint(x: 0, y: canvas.height - symbolSize.height)
                tinted.draw(at: symbolOrigin)
                let badgeOrigin = CGPoint(
                    x: canvas.width - badgeSide,
                    y: 0
                )
                let badgeRect = CGRect(origin: badgeOrigin, size: CGSize(width: badgeSide, height: badgeSide))
                UIColor(configuration.badgeFill).setFill()
                UIBezierPath(ovalIn: badgeRect).fill()
                let textOrigin = CGPoint(
                    x: badgeRect.midX - textSize.width / 2,
                    y: badgeRect.midY - textSize.height / 2 - pad * 0.1
                )
                (badgeText as NSString).draw(at: textOrigin, withAttributes: textAttributes)
            }.withRenderingMode(.alwaysOriginal)
        }
    }

    public final class IGSegmentedControl: UISegmentedControl {
        var onTouchBegan: (() -> Void)?

        override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesBegan(touches, with: event)
            onTouchBegan?()
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
