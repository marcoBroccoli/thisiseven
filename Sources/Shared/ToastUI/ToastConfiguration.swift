import SwiftUI

/// Everything the toast needs to look like it belongs to a given app.
///
/// The module ships a neutral default so it works untouched; host apps pass
/// their own palette and motion in via `.toastHost(_:)`.
public struct ToastConfiguration: Sendable {
    public var style: ToastStyle
    public var motion: ToastMotion

    public init(style: ToastStyle = .standard, motion: ToastMotion = .standard) {
        self.style = style
        self.motion = motion
    }

    public static let standard = ToastConfiguration()
}

public struct ToastStyle: Sendable {
    /// Pill fill. Black reads as an extension of the Dynamic Island; any other
    /// colour breaks the illusion that the pill and the Island are one object.
    public var ink: Color
    public var label: Color
    public var font: Font
    public var neutralAccent: Color
    public var successAccent: Color
    public var errorAccent: Color
    public var maxTextWidth: CGFloat
    public var horizontalPadding: CGFloat
    public var verticalPadding: CGFloat
    public var accentDiameter: CGFloat
    public var spacing: CGFloat
    public var shadowColor: Color
    public var shadowRadius: CGFloat
    public var shadowOffsetY: CGFloat

    public init(
        ink: Color = .black,
        label: Color = .white,
        font: Font = .system(size: 14, weight: .semibold),
        neutralAccent: Color = .gray,
        successAccent: Color = .green,
        errorAccent: Color = .orange,
        maxTextWidth: CGFloat = 250,
        horizontalPadding: CGFloat = 20,
        verticalPadding: CGFloat = 15,
        accentDiameter: CGFloat = 7,
        spacing: CGFloat = 10,
        shadowColor: Color = .black.opacity(0.24),
        shadowRadius: CGFloat = 18,
        shadowOffsetY: CGFloat = 10
    ) {
        self.ink = ink
        self.label = label
        self.font = font
        self.neutralAccent = neutralAccent
        self.successAccent = successAccent
        self.errorAccent = errorAccent
        self.maxTextWidth = maxTextWidth
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.accentDiameter = accentDiameter
        self.spacing = spacing
        self.shadowColor = shadowColor
        self.shadowRadius = shadowRadius
        self.shadowOffsetY = shadowOffsetY
    }

    public static let standard = ToastStyle()

    func accent(for tone: Toast.Tone) -> Color {
        switch tone {
        case .neutral: neutralAccent
        case .success: successAccent
        case .error: errorAccent
        }
    }
}

public struct ToastMotion: Sendable {
    /// Pill stretching out of the Island. Underdamp it a little to land with a
    /// single bounce; the morph amplifies the overshoot into vertical travel.
    public var emerge: Animation
    /// Pill being pulled back in. Critically damped — no wobble on the way home.
    public var retract: Animation
    /// Must outlast `retract`, or the toast is torn down mid-morph and vanishes
    /// instead of seating back inside the Island.
    public var retractSettle: Duration
    /// Applied to any toast that doesn't carry its own duration.
    public var defaultDuration: Duration

    public init(
        emerge: Animation = .spring(response: 0.72, dampingFraction: 0.74),
        retract: Animation = .spring(response: 0.6, dampingFraction: 1),
        retractSettle: Duration = .milliseconds(900),
        defaultDuration: Duration = .seconds(2.6)
    ) {
        self.emerge = emerge
        self.retract = retract
        self.retractSettle = retractSettle
        self.defaultDuration = defaultDuration
    }

    public static let standard = ToastMotion()
}

public extension EnvironmentValues {
    @Entry var toastConfiguration: ToastConfiguration = .standard
}
